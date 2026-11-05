-- DF-037: Restore revoked accounts and keep related requests; all fixtures roll back.
-- Run as database owner after migrations 015-019.
begin;

create temporary table test_restore_account_fixture (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;
insert into test_restore_account_fixture(key) values
  ('admin'), ('student'), ('tech_blocked'), ('tech_clean'), ('active_student'),
  ('room_old'), ('room_new'), ('room_inactive'), ('category'),
  ('student_pending'), ('student_confirmation'), ('tech_rework'), ('tech_completed');

create function pg_temp.rs_id(p_key text) returns uuid language sql stable as $$
  select id from test_restore_account_fixture where key = p_key;
$$;
create function pg_temp.rs_expect_error(
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
create function pg_temp.rs_assert(p_ok boolean, p_message text)
returns void language plpgsql as $$
begin
  if not p_ok then raise exception 'FAIL: %', p_message; end if;
end $$;
do $$ begin
  execute format('grant usage on schema %I to authenticated, anon',
    (select nspname from pg_namespace where oid = pg_my_temp_schema()));
end $$;
grant select on test_restore_account_fixture to authenticated, anon;
grant execute on function pg_temp.rs_id(text), pg_temp.rs_expect_error(text, text, text),
  pg_temp.rs_assert(boolean, text) to authenticated, anon;

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@rs-test.invalid', now(), now(), now()
from test_restore_account_fixture
where key in ('admin', 'student', 'tech_blocked', 'tech_clean', 'active_student');
update auth.users set banned_until = now() + interval '100 years'
where id in (pg_temp.rs_id('student'), pg_temp.rs_id('tech_blocked'), pg_temp.rs_id('tech_clean'));

insert into public.rooms (id, code, building, is_active) values
  (pg_temp.rs_id('room_old'), 'RS-OLD-' || pg_temp.rs_id('room_old')::text, 'Old', true),
  (pg_temp.rs_id('room_new'), 'RS-NEW-' || pg_temp.rs_id('room_new')::text, 'New', true),
  (pg_temp.rs_id('room_inactive'), 'RS-INACTIVE-' || pg_temp.rs_id('room_inactive')::text, 'Closed', false);
insert into public.incident_categories (id, name, is_active)
values (pg_temp.rs_id('category'), 'RS-Category-' || pg_temp.rs_id('category')::text, true);

insert into public.profiles (
  id, identity_code, full_name, email, phone, role, status, room_id, must_change_password
) values
  (pg_temp.rs_id('admin'), 'RS-ADMIN', 'Restore Admin', 'rs-admin@example.invalid', null, 'admin', 'active', null, false),
  (pg_temp.rs_id('student'), 'RS-STUDENT', 'Restored Student', 'rs-student@example.invalid', '0900000001', 'student', 'revoked', pg_temp.rs_id('room_old'), true),
  (pg_temp.rs_id('tech_blocked'), 'RS-TECH-BLOCKED', 'Blocked Technician', 'rs-tech-blocked@example.invalid', '0900000002', 'technician', 'revoked', null, false),
  (pg_temp.rs_id('tech_clean'), 'RS-TECH-CLEAN', 'Restored Technician', 'rs-tech-clean@example.invalid', '0900000003', 'technician', 'revoked', null, true),
  (pg_temp.rs_id('active_student'), 'RS-ACTIVE', 'Already Active', 'rs-active@example.invalid', '0900000004', 'student', 'active', pg_temp.rs_id('room_old'), false);

insert into public.repair_requests (
  id, student_id, room_id, room_code_snapshot, building_snapshot,
  category_id, category_name_snapshot, title, description, status,
  assigned_technician_id
) values
  (pg_temp.rs_id('student_pending'), pg_temp.rs_id('student'), pg_temp.rs_id('room_old'), 'OLD-ROOM', 'Old Building',
   pg_temp.rs_id('category'), 'RS Category', 'Old pending request', 'Keep unchanged', 'pending', null),
  (pg_temp.rs_id('student_confirmation'), pg_temp.rs_id('student'), pg_temp.rs_id('room_old'), 'OLD-ROOM', 'Old Building',
   pg_temp.rs_id('category'), 'RS Category', 'Awaiting student confirmation', 'Student must confirm', 'awaiting_confirmation', pg_temp.rs_id('tech_blocked')),
  (pg_temp.rs_id('tech_rework'), pg_temp.rs_id('student'), pg_temp.rs_id('room_old'), 'OLD-ROOM', 'Old Building',
    pg_temp.rs_id('category'), 'RS Category', 'Technician rework', 'Still unfinished', 'awaiting_rework', pg_temp.rs_id('tech_blocked')),
    (pg_temp.rs_id('tech_completed'), pg_temp.rs_id('student'), pg_temp.rs_id('room_old'), 'OLD-ROOM', 'Old Building',
    pg_temp.rs_id('category'), 'RS Category', 'Technician completed job', 'Terminal work does not block restore', 'completed', pg_temp.rs_id('tech_clean'));

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rs_id('student')::text, true);
set local role authenticated;
select pg_temp.rs_expect_error(
  'select public.admin_restore_account(''RS-STUDENT'', ''' || pg_temp.rs_id('room_new')::text || '''::uuid)',
  '42501'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rs_id('admin')::text, true);
set local role authenticated;
select pg_temp.rs_expect_error(
  'select public.admin_restore_account(''RS-STUDENT'', null)',
  '22023', 'Vui lòng chọn phòng đang hoạt động cho Sinh viên.'
);
select pg_temp.rs_expect_error(
  'select public.admin_restore_account(''RS-STUDENT'', ''' || pg_temp.rs_id('room_inactive')::text || '''::uuid)',
  'P0002', 'Chỉ được khôi phục Sinh viên vào phòng đang hoạt động.'
);
select pg_temp.rs_expect_error(
  'select public.admin_restore_account(''RS-TECH-BLOCKED'', null)',
  'P0001', 'Không thể khôi phục Kỹ thuật viên còn công việc chưa hoàn tất.'
);
select pg_temp.rs_expect_error(
  'select public.admin_restore_account(''RS-ACTIVE'', ''' || pg_temp.rs_id('room_new')::text || '''::uuid)',
  'P0001', 'Tài khoản chưa bị thu hồi.'
);

do $$ declare v_student jsonb; v_technician jsonb; begin
  v_student := public.admin_restore_account('RS-STUDENT', pg_temp.rs_id('room_new'));
  v_technician := public.admin_restore_account('RS-TECH-CLEAN', null);
  if v_student->>'status' <> 'active'
    or v_student->>'identity_code' <> 'RS-STUDENT'
    or v_student->>'room_id' <> pg_temp.rs_id('room_new')::text
    or v_student->>'must_change_password' <> 'true' then
    raise exception 'FAIL: student restore result mismatch';
  end if;
  if v_technician->>'status' <> 'active'
    or v_technician->>'role' <> 'technician'
    or v_technician->>'room_id' is not null
    or v_technician->>'must_change_password' <> 'true' then
    raise exception 'FAIL: technician restore result mismatch';
  end if;
end $$;

select pg_temp.rs_expect_error(
  'select public.admin_confirm_revoked_student_request(''' || pg_temp.rs_id('student_confirmation')::text || '''::uuid, ''Admin note'')',
  'P0001', 'Chỉ xử lý thay khi tài khoản Sinh viên đang Đã thu hồi.'
);
select pg_temp.rs_expect_error(
  'select public.admin_request_rework_revoked_student_request(''' || pg_temp.rs_id('student_confirmation')::text || '''::uuid, ''Admin reason'')',
  'P0001', 'Chỉ xử lý thay khi tài khoản Sinh viên đang Đã thu hồi.'
);

reset role;
select pg_temp.rs_assert(exists (
  select 1 from public.profiles
  where id = pg_temp.rs_id('student') and status = 'active'
    and identity_code = 'RS-STUDENT' and email = 'rs-student@example.invalid'
    and room_id = pg_temp.rs_id('room_new') and must_change_password
), 'restored student profile mismatch');
select pg_temp.rs_assert(exists (
  select 1 from auth.users where id = pg_temp.rs_id('student') and banned_until is null
) and exists (
  select 1 from auth.users where id = pg_temp.rs_id('tech_clean') and banned_until is null
), 'Auth ban was not cleared');
select pg_temp.rs_assert(exists (
  select 1 from public.profiles where id = pg_temp.rs_id('tech_clean')
    and status = 'active' and role = 'technician' and room_id is null and must_change_password
), 'restored technician profile mismatch');
select pg_temp.rs_assert(exists (
  select 1 from public.repair_requests where id = pg_temp.rs_id('student_pending')
    and status = 'pending' and room_id = pg_temp.rs_id('room_old') and room_code_snapshot = 'OLD-ROOM'
) and exists (
  select 1 from public.repair_requests where id = pg_temp.rs_id('student_confirmation')
    and status = 'awaiting_confirmation' and room_code_snapshot = 'OLD-ROOM'
), 'student requests or room snapshots changed');
select pg_temp.rs_assert(exists (
  select 1 from public.request_history where entity_type = 'profile'
    and entity_id = pg_temp.rs_id('student') and action = 'admin_restore_account'
    and actor_id = pg_temp.rs_id('admin') and old_status = 'revoked'
    and new_status = 'active' and occurred_at is not null
), 'restore history missing');

rollback;
select 'PASS: DF-037 restore account checks completed' as result;