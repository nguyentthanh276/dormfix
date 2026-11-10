-- DF-017: notify the owning student when Admin assigns or rejects a pending request.
-- Existing KTV notifications and student repair_reported events retain their sources.
begin;

create function public._notify_student_admin_request_event() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_message text;
begin
  if public.current_active_role() is distinct from 'admin'::public.app_role then
    return new;
  end if;

  case new.status
    when 'assigned' then
      if old.assigned_technician_id is not null or new.assigned_technician_id is null then
        return new;
      end if;
      v_message := 'Yêu cầu sửa chữa đã được phân công.';
    when 'rejected' then
      v_message := 'Yêu cầu sửa chữa đã bị từ chối.';
  end case;

  insert into public.notifications(recipient_id, request_id, event_type, message)
  select p.id, new.id, new.status::text, v_message
  from public.profiles p
  where p.id = new.student_id and p.role = 'student';

  return new;
end $$;

revoke all on function public._notify_student_admin_request_event() from public, anon, authenticated;

create trigger student_admin_request_events
after update of status on public.repair_requests
for each row
when (old.status = 'pending' and new.status in ('assigned', 'rejected'))
execute function public._notify_student_admin_request_event();

comment on trigger student_admin_request_events on public.repair_requests is
  'DF-017: one private student event for an Admin assignment or rejection of a pending request, in the same transaction.';

commit;
