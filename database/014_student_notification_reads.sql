-- DF-017: mark only the current active student's own notifications read.
-- Apply once after 013_technician_tracking.sql. No direct table writes granted.
begin;

create function public._student_notification_actor() returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;
  -- Serialize reads with account blocks, revocations and password flag changes.
  select * into v_profile from public.profiles where id = v_uid for share;
  if not found or v_profile.role <> 'student' or v_profile.status <> 'active'
     or v_profile.must_change_password then
    raise exception using errcode = '42501', message = 'STUDENT_ACCESS_DENIED';
  end if;
  return v_uid;
end $$;

create function public.student_mark_notification_read(p_notification_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._student_notification_actor();
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

create function public.student_mark_all_notifications_read() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._student_notification_actor();
  v_now timestamptz := clock_timestamp();
  v_updated_count bigint;
begin
  update public.notifications set read_at = v_now
  where recipient_id = v_uid and read_at is null;
  get diagnostics v_updated_count = row_count;
  return jsonb_build_object('updated_count', v_updated_count, 'read_at', v_now);
end $$;

revoke all on function public._student_notification_actor() from public, anon, authenticated;
revoke all on function public.student_mark_notification_read(uuid) from public, anon;
revoke all on function public.student_mark_all_notifications_read() from public, anon;
grant execute on function public.student_mark_notification_read(uuid) to authenticated;
grant execute on function public.student_mark_all_notifications_read() to authenticated;

comment on function public.student_mark_notification_read(uuid) is
 'DF-017: active password-cleared student marks only an own notification read; server time and idempotent receipt.';
comment on function public.student_mark_all_notifications_read() is
 'DF-017: active password-cleared student marks only unread own notifications; one server timestamp and changed-row count.';

commit;
