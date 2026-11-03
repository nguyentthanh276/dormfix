-- DF-027: technician assignment history and in-app notifications.
-- Apply once after 012_admin_request_resolution.sql. Existing rows are not backfilled.
begin;

create function public.technician_list_work_history() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;
  if public.current_active_role() is distinct from 'technician'::public.app_role then
    raise exception using errcode = '42501', message = 'TECHNICIAN_ACCESS_DENIED';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'assignment_id', a.id,
    'request_id', case when a.ended_at is null and r.assigned_technician_id = v_uid then r.id end,
    'request_code', case when a.ended_at is null and r.assigned_technician_id = v_uid
      then r.request_code else a.request_code_snapshot end,
    'title', case when a.ended_at is null and r.assigned_technician_id = v_uid
      then r.title else a.title_snapshot end,
    'room_code', case when a.ended_at is null and r.assigned_technician_id = v_uid
      then r.room_code_snapshot else a.room_code_snapshot end,
    'assigned_at', a.assigned_at, 'ended_at', a.ended_at,
    'status', case when a.ended_at is null and r.assigned_technician_id = v_uid then r.status end,
    'can_open_detail', coalesce(a.ended_at is null and r.assigned_technician_id = v_uid, false)
  ) order by a.assigned_at desc, a.id desc), '[]'::jsonb)
  into v_rows
  from public.request_assignments a
  join public.repair_requests r on r.id = a.request_id
  where a.technician_id = v_uid;
  return v_rows;
end $$;

create function public.technician_list_notifications() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;
  if public.current_active_role() is distinct from 'technician'::public.app_role then
    raise exception using errcode = '42501', message = 'TECHNICIAN_ACCESS_DENIED';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'event_type', n.event_type, 'message', n.message,
    'created_at', n.created_at, 'read_at', n.read_at,
    'request_id', case when r.assigned_technician_id = v_uid then r.id end,
    'can_open_detail', coalesce(r.assigned_technician_id = v_uid, false)
  ) order by n.created_at desc, n.id desc), '[]'::jsonb)
  into v_rows
  from public.notifications n
  join public.repair_requests r on r.id = n.request_id
  where n.recipient_id = v_uid;
  return v_rows;
end $$;

create function public.technician_mark_notification_read(p_notification_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  -- The existing helper also holds a shared profile lock until this write commits.
  v_uid uuid := public._technician_workflow_actor();
  v_notification public.notifications%rowtype;
begin
  update public.notifications set read_at = coalesce(read_at, clock_timestamp())
  where id = p_notification_id and recipient_id = v_uid
  returning * into v_notification;
  if not found then
    raise exception using errcode = 'P0002', message = 'NOTIFICATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_notification.id, 'read_at', v_notification.read_at);
end $$;

-- These messages contain only the event. Request contents, contacts, photos and
-- results are never copied into notifications belonging to a former technician.
create function public._notify_technician_tracking_event() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_recipient uuid;
  v_event text;
  v_message text;
begin
  if new.assigned_technician_id is distinct from old.assigned_technician_id
     and new.assigned_technician_id is not null then
    insert into public.notifications (recipient_id, request_id, event_type, message, created_at)
    select p.id, new.id,
      case when old.assigned_technician_id is null then 'assigned' else 'transferred_in' end,
      case when old.assigned_technician_id is null then 'Bạn được giao một công việc sửa chữa.'
        else 'Bạn được chuyển giao một công việc sửa chữa.' end, v_now
    from public.profiles p where p.id = new.assigned_technician_id and p.role = 'technician';

    if old.assigned_technician_id is not null then
      insert into public.notifications (recipient_id, request_id, event_type, message, created_at)
      select p.id, new.id, 'transferred_out',
        'Công việc của bạn đã được chuyển cho Kỹ thuật viên khác.', v_now
      from public.profiles p where p.id = old.assigned_technician_id and p.role = 'technician';
    end if;
  end if;

  if new.status is distinct from old.status then
    v_recipient := coalesce(new.assigned_technician_id, old.assigned_technician_id);
    case new.status
      when 'cancelled' then
        v_event := 'cancelled'; v_message := 'Yêu cầu sửa chữa đã được hủy.';
      when 'awaiting_rework' then
        v_event := 'rework_requested'; v_message := 'Công việc có yêu cầu sửa lại, vui lòng kiểm tra.';
      when 'completed' then
        v_event := 'completed'; v_message := 'Yêu cầu sửa chữa đã được xác nhận hoàn tất.';
      else null;
    end case;
    if v_recipient is not null and v_event is not null then
      insert into public.notifications (recipient_id, request_id, event_type, message, created_at)
      select p.id, new.id, v_event, v_message, v_now
      from public.profiles p where p.id = v_recipient and p.role = 'technician';
    end if;
  end if;
  return new;
end $$;

create trigger technician_tracking_events
after update of assigned_technician_id, status on public.repair_requests
for each row execute function public._notify_technician_tracking_event();

revoke all on function public.technician_list_work_history() from public, anon;
revoke all on function public.technician_list_notifications() from public, anon;
revoke all on function public.technician_mark_notification_read(uuid) from public, anon;
revoke all on function public._notify_technician_tracking_event() from public, anon, authenticated;
grant execute on function public.technician_list_work_history() to authenticated;
grant execute on function public.technician_list_notifications() to authenticated;
grant execute on function public.technician_mark_notification_read(uuid) to authenticated;

comment on function public.technician_list_work_history() is
 'DF-027: own assignments only; former assignments expose frozen summary fields, never later request updates.';
comment on function public.technician_list_notifications() is
 'DF-027: own generic in-app notifications with current detail-access eligibility; no push notifications.';
comment on function public.technician_mark_notification_read(uuid) is
 'DF-027: idempotently mark only the current active technician recipient notification read; no direct table writes.';

commit;
