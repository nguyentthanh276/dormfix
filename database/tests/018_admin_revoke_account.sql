-- DF-036: Admin revoke account regression; all changes roll back.
-- Run as database owner after migrations 015-018.
begin;

create temporary table test_revoke_account_fixture (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;
insert into test_revoke_account_fixture(key) values
  ('admin'), ('student'), ('tech_assigned'), ('tech_rework'), ('tech_idle'),
  ('room'), ('category'), ('student_pending'), ('student_confirm'), ('student_rework'),
  ('tech_assigned_request'), ('tech_rework_request'), ('tech_completed_request');

create function pg_temp.ra_id(p_key text) returns uuid language sql stable as $$
  select id from test_revoke_account_fixture where key = p_key;
$$;
create function pg_temp.ra_expect_error(
  p_sql text, p_state text, p_message text default null
) returns void language plpgsql as $$
declare v_state text; v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state <> p_state or (p_message is not null and v_message <> p_message) then
      raise exception 'FAIL: expected % %, got % %', p_state, p_message, v_state, v_message;
    end if;
    return;
  end;
  raise exception 'FAIL: expected error % %, but succeeded', p_state, p_message;
end $$;
do $$ begin
  execute format('grant usage on schema %I to authenticated, anon',
    (select nspname from pg_namespace where oid = pg_my_temp_schema()));
end $$;
grant select on test_revoke_account_fixture to authenticated, anon;
grant execute on function pg_temp.ra_id(text), pg_temp.ra_expect_error(text, text, text)
  to authenticated, anon;

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@ra-test.invalid', now(), now(), now()
from test_revoke_account_fixture
where key in ('admin', 'student', 'tech_assigned', 'tech_rework', 'tech_idle');

insert into public.rooms (id, code, building, is_active)
values (pg_temp.ra_id('room'), 'RA-ROOM-' || pg_temp.ra_id('room')::text, 'Revoke Test', true);
insert into public.incident_categories (id, name, is_active)
values (pg_temp.ra_id('category'), 'RA-Category-' || pg_temp.ra_id('category')::text, true);

insert into public.profiles (
  id, identity_code, full_name, email, phone, role, status, room_id, must_change_password
) values
  (pg_temp.ra_id('admin'), 'RA-ADMIN', 'Revoke Admin', 'ra-admin@example.invalid', null, 'admin', 'active', null, false),
  (pg_temp.ra_id('student'), 'RA-STUDENT', 'Revoke Student', 'ra-student@example.invalid', '0900000001', 'student', 'active', pg_temp.ra_id('room'), false),
  (pg_temp.ra_id('tech_assigned'), 'RA-TECH-ASSIGNED', 'Assigned Technician', pg_temp.ra_id('tech_assigned')::text || '@ra-test.invalid', '0900000002', 'technician', 'active', null, false),
  (pg_temp.ra_id('tech_rework'), 'RA-TECH-REWORK', 'Rework Technician', pg_temp.ra_id('tech_rework')::text || '@ra-test.invalid', '0900000003', 'technician', 'active', null, false),
  (pg_temp.ra_id('tech_idle'), 'RA-TECH-IDLE', 'Idle Technician', pg_temp.ra_id('tech_idle')::text || '@ra-test.invalid', '0900000004', 'technician', 'active', null, false);

insert into public.repair_requests (
  id, student_id, room_id, room_code_snapshot, building_snapshot,
  category_id, category_name_snapshot, title, description, status,
  assigned_technician_id
) values
  (pg_temp.ra_id('student_pending'), pg_temp.ra_id('student'), pg_temp.ra_id('room'), 'RA-ROOM', 'Revoke Test',
   pg_temp.ra_id('category'), 'RA Category', 'Student pending', 'Keep after revoke', 'pending', null),
  (pg_temp.ra_id('student_confirm'), pg_temp.ra_id('student'), pg_temp.ra_id('room'), 'RA-ROOM', 'Revoke Test',
   pg_temp.ra_id('category'), 'RA Category', 'Student confirmation', 'Admin can confirm', 'awaiting_confirmation', pg_temp.ra_id('tech_idle')),
  (pg_temp.ra_id('student_rework'), pg_temp.ra_id('student'), pg_temp.ra_id('room'), 'RA-ROOM', 'Revoke Test',
   pg_temp.ra_id('category'), 'RA Category', 'Student rework', 'Admin can request rework', 'awaiting_confirmation', pg_temp.ra_id('tech_idle')),
  (pg_temp.ra_id('tech_assigned_request'), pg_temp.ra_id('student'), pg_temp.ra_id('room'), 'RA-ROOM', 'Revoke Test',
   pg_temp.ra_id('category'), 'RA Category', 'Open assignment', 'Must block revoke', 'assigned', pg_temp.ra_id('tech_assigned')),
  (pg_temp.ra_id('tech_rework_request'), pg_temp.ra_id('student'), pg_temp.ra_id('room'), 'RA-ROOM', 'Revoke Test',
   pg_temp.ra_id('category'), 'RA Category', 'Rework assignment', 'Rework is unfinished', 'awaiting_rework', pg_temp.ra_id('tech_rework')),
  (pg_temp.ra_id('tech_completed_request'), pg_temp.ra_id('student'), pg_temp.ra_id('room'), 'RA-ROOM', 'Revoke Test',
   pg_temp.ra_id('category'), 'RA Category', 'Completed assignment', 'Completed work is terminal', 'completed', pg_temp.ra_id('tech_idle'));

reset role;
select set_config('request.jwt.claim.sub', pg_temp.ra_id('student')::text, true);
set local role authenticated;
select pg_temp.ra_expect_error(
  'select public.admin_revoke_account(''RA-STUDENT'', ''Not an admin'')', '42501'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.ra_id('admin')::text, true);
set local role authenticated;
select pg_temp.ra_expect_error(
  'select public.admin_revoke_account(''RA-STUDENT'', ''   '')',
  '22023', 'Vui lòng nhập lý do thu hồi.'
);
select pg_temp.ra_expect_error(
  'select public.admin_revoke_account(''RA-TECH-ASSIGNED'', ''Lý do'')',
  'P0001', 'Không thể thu hồi Kỹ thuật viên còn công việc chưa hoàn tất.'
);
select pg_temp.ra_expect_error(
  'select public.admin_revoke_account(''RA-TECH-REWORK'', ''Lý do'')',
  'P0001', 'Không thể thu hồi Kỹ thuật viên còn công việc chưa hoàn tất.'
);

do $$
declare v_student_result jsonb; v_tech_result jsonb;
begin
  v_student_result := public.admin_revoke_account('RA-STUDENT', 'Đã kết thúc lưu trú');
  v_tech_result := public.admin_revoke_account('RA-TECH-IDLE', 'Kết thúc hợp đồng');
  if v_student_result->>'status' <> 'revoked'
    or v_student_result->>'revoked_by' <> pg_temp.ra_id('admin')::text
    or v_student_result->>'reason' <> 'Đã kết thúc lưu trú'
    or (v_student_result->>'revoked_at')::timestamptz is null then
    raise exception 'FAIL: student revoke receipt missing actor/time/reason';
  end if;
  if v_tech_result->>'status' <> 'revoked' then
    raise exception 'FAIL: idle technician revoke failed';
  end if;
end $$;

-- Existing Admin handling for a revoked student's awaiting requests remains enabled.
select public.admin_confirm_revoked_student_request(
  pg_temp.ra_id('student_confirm'), 'Đã xác nhận hoàn tất'
);
select public.admin_request_rework_revoked_student_request(
  pg_temp.ra_id('student_rework'), 'Cần tiếp tục khắc phục'
);

reset role;
do $$
begin
  if not exists (
    select 1 from public.profiles
    where id = pg_temp.ra_id('student') and identity_code = 'RA-STUDENT'
      and email = 'ra-student@example.invalid' and status = 'revoked'
  ) then raise exception 'FAIL: revoked student profile was deleted or altered'; end if;
  if not exists (select 1 from auth.users where id = pg_temp.ra_id('student')) then
    raise exception 'FAIL: Auth user was deleted';
  end if;
  if not exists (
    select 1 from auth.users where id = pg_temp.ra_id('student') and banned_until > now()
  ) then raise exception 'FAIL: revoked account is not Auth-banned'; end if;
  if not exists (
    select 1 from public.repair_requests where id = pg_temp.ra_id('student_pending')
      and student_id = pg_temp.ra_id('student') and status = 'pending'
  ) then raise exception 'FAIL: student request was changed or deleted'; end if;
  if (select status from public.repair_requests where id = pg_temp.ra_id('student_confirm')) <> 'completed'
    or (select status from public.repair_requests where id = pg_temp.ra_id('student_rework')) <> 'awaiting_rework' then
    raise exception 'FAIL: Admin can no longer resolve revoked student requests'; end if;
  if not exists (
    select 1 from public.request_history
    where entity_type = 'profile' and entity_id = pg_temp.ra_id('student')
      and action = 'admin_revoke_account' and actor_id = pg_temp.ra_id('admin')
      and note = 'Đã kết thúc lưu trú' and occurred_at is not null
  ) then raise exception 'FAIL: revoke actor/time/reason history missing'; end if;
  if not exists (
    select 1 from public.profiles where id = pg_temp.ra_id('tech_assigned') and status = 'active'
  ) or not exists (
    select 1 from public.profiles where id = pg_temp.ra_id('tech_rework') and status = 'active'
  ) then raise exception 'FAIL: technician with unfinished work was revoked'; end if;
  if not exists (
    select 1 from public.profiles where id = pg_temp.ra_id('tech_idle') and status = 'revoked'
  ) or not exists (
    select 1 from auth.users where id = pg_temp.ra_id('tech_idle') and banned_until > now()
  ) then raise exception 'FAIL: idle technician revoke or Auth ban missing'; end if;
end $$;

rollback;
select 'PASS: DF-036 account revocation checks completed' as result;