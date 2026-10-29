-- DF-045/046: Admin assignment/rejection checks. Run after migrations 010 and 011.
-- All fixture rows are rolled back at the end.
begin;
create temporary table admin_write_fixture(key text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into admin_write_fixture(key) values
  ('admin'), ('student'), ('tech_first_login'), ('tech_locked'),
  ('room'), ('category'), ('pending'), ('cancelled'), ('rejectable');
grant select on admin_write_fixture to authenticated;

insert into auth.users(id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@admin-write-test.invalid', now(), now(), now()
from admin_write_fixture where key in ('admin','student','tech_first_login','tech_locked');
insert into public.rooms(id, code, building)
select id, 'ADMIN-WRITE-A101', 'Test building' from admin_write_fixture where key='room';
insert into public.incident_categories(id, name)
select id, 'Admin write test' from admin_write_fixture where key='category';
insert into public.profiles(id, identity_code, full_name, email, phone, role, status, room_id, must_change_password)
select id, 'AW-'||id::text,
  case key when 'admin' then 'Workflow Admin' when 'student' then 'Workflow Student'
    when 'tech_first_login' then 'First login Technician' else 'Locked Technician' end,
  id::text || '@admin-write-test.invalid', case when key='admin' then null else '0900000001' end,
  case when key='admin' then 'admin'::public.app_role when key='student' then 'student'::public.app_role
    else 'technician'::public.app_role end,
  case when key='tech_locked' then 'locked'::public.account_status else 'active'::public.account_status end,
  case when key='student' then (select id from admin_write_fixture where key='room') end,
  key='tech_first_login'
from admin_write_fixture where key in ('admin','student','tech_first_login','tech_locked');
insert into public.repair_requests(id, student_id, room_id, room_code_snapshot, building_snapshot,
  category_id, category_name_snapshot, title, description, status)
select f.id, (select id from admin_write_fixture where key='student'),
  (select id from admin_write_fixture where key='room'), 'ADMIN-WRITE-A101', 'Test building',
  (select id from admin_write_fixture where key='category'), 'Admin write test',
  'Fixture '||f.key, 'Fixture description',
  case f.key when 'pending' then 'pending'::public.repair_status else 'cancelled'::public.repair_status end
from admin_write_fixture f where key in ('pending','cancelled','rejectable');

select set_config('request.jwt.claim.sub', (select id::text from admin_write_fixture where key='admin'), true);
set local role authenticated;
do $$ declare v_result jsonb; v_admin uuid := auth.uid(); v_request uuid := (select id from admin_write_fixture where key='pending'); begin
  if not exists (select 1 from jsonb_array_elements(public.admin_request_active_technicians()) as e(item)
      where item->>'id' = (select id::text from admin_write_fixture where key='tech_first_login')) then
    raise exception 'FAIL DF-045: active first-login technician missing';
  end if;
  if exists (select 1 from jsonb_array_elements(public.admin_request_active_technicians()) as e(item)
      where item->>'id' = (select id::text from admin_write_fixture where key='tech_locked')) then
    raise exception 'FAIL DF-045: locked technician offered';
  end if;
  v_result := public.admin_assign_request(v_request, (select id from admin_write_fixture where key='tech_first_login'));
  if v_result->>'status' <> 'assigned' or not exists (
      select 1 from public.request_assignments where request_id=v_request and ended_at is null
        and technician_id=(select id from admin_write_fixture where key='tech_first_login')) then
    raise exception 'FAIL DF-045: pending request not assigned';
  end if;
  if not exists(select 1 from public.request_history where request_id=v_request
      and actor_id=v_admin and old_status='pending' and new_status='assigned') then
    raise exception 'FAIL DF-045: assignment history missing';
  end if;
  begin
    declare v_conflict boolean := false;
    begin
      perform public.admin_assign_request((select id from admin_write_fixture where key='cancelled'),
        (select id from admin_write_fixture where key='tech_first_login'));
    exception when sqlstate 'P0001' then v_conflict := true;
    end;
    if not v_conflict or (select status from public.repair_requests where id=(select id from admin_write_fixture where key='cancelled')) <> 'cancelled' then
      raise exception 'FAIL DF-045: cancelled request accepted or modified';
    end if;
  end;
  begin
    declare v_rejected boolean := false;
    begin
      perform public.admin_reject_request((select id from admin_write_fixture where key='rejectable'), '   ');
    exception when sqlstate '22023' then v_rejected := true;
    end;
    if not v_rejected then raise exception 'FAIL DF-046: blank reason accepted'; end if;
  end;
  begin
    declare v_rejected boolean := false;
    begin
      perform public.admin_reject_request((select id from admin_write_fixture where key='rejectable'), 'Lý do kiểm thử');
    exception when sqlstate 'P0001' then v_rejected := true;
    end;
    if v_rejected or (select status from public.repair_requests where id=(select id from admin_write_fixture where key='rejectable')) <> 'rejected' then
      raise exception 'FAIL DF-046: valid rejection was not saved';
    end if;
    if not exists (select 1 from public.request_history where request_id=(select id from admin_write_fixture where key='rejectable')
        and actor_id=v_admin and new_status='rejected' and note='Lý do kiểm thử') then
      raise exception 'FAIL DF-046: student-readable reason not written to history';
    end if;
  end;
  begin
    declare v_rejected boolean := false;
    begin
    perform public.admin_reject_request(v_request, '   ');
    exception when sqlstate '22023' then v_rejected := true;
    end;
    if not v_rejected then raise exception 'FAIL DF-046: blank reason accepted on assigned request'; end if;
  end;
  begin
    declare v_rejected boolean := false;
    begin
      perform public.admin_reject_request(v_request, 'Không tiếp nhận');
    exception when sqlstate 'P0001' then v_rejected := true;
    end;
    if not v_rejected then raise exception 'FAIL DF-046: assigned request accepted'; end if;
  end;
  if (select status from public.repair_requests where id=v_request) <> 'assigned' then
    raise exception 'FAIL DF-046: invalid rejection changed request';
  end if;
  raise notice 'PASS DF-045: Admin gate, active first-login technician, locked technician exclusion, row status and history';
  raise notice 'PASS DF-046: required reason and pending-only transition';
end $$;
reset role;

select set_config('request.jwt.claim.sub', (select id::text from admin_write_fixture where key='student'), true);
set local role authenticated;
do $$ declare v_denied boolean := false; begin
  begin
    perform public.admin_reject_request((select id from admin_write_fixture where key='pending'), 'reason');
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'FAIL: non-Admin mutation accepted'; end if;
  if not exists (select 1 from public.request_history
      where request_id=(select id from admin_write_fixture where key='rejectable')
        and note='Lý do kiểm thử' and new_status='rejected') then
    raise exception 'FAIL DF-046: student cannot read rejection reason through request history';
  end if;
  raise notice 'PASS role gate: non-Admin cannot reject';
  raise notice 'PASS DF-046: student can read rejection reason from request_history';
end $$;
reset role;
rollback;
select 'PASS: DF-045/046 transactional rollback fixtures removed' as result;
