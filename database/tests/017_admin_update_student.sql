-- DF-033: Admin update student profile and room; every fixture rolls back.
-- Run as database owner after migrations 015-017.
begin;

create temporary table test_update_student_fixture (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;
insert into test_update_student_fixture(key) values
  ('admin'), ('student'), ('revoked_student'), ('old_room'),
  ('new_room'), ('inactive_room'), ('category'), ('old_request');

create function pg_temp.us_id(p_key text) returns uuid language sql stable as $$
  select id from test_update_student_fixture where key = p_key;
$$;
create function pg_temp.us_expect_error(
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
grant select on test_update_student_fixture to authenticated, anon;
grant execute on function pg_temp.us_id(text), pg_temp.us_expect_error(text, text, text)
  to authenticated, anon;

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@us-test.invalid', now(), now(), now()
from test_update_student_fixture where key in ('admin', 'student', 'revoked_student');

insert into public.rooms (id, code, building, is_active) values
  (pg_temp.us_id('old_room'), 'US-OLD-' || pg_temp.us_id('old_room')::text, 'Old Building', true),
  (pg_temp.us_id('new_room'), 'US-NEW-' || pg_temp.us_id('new_room')::text, 'New Building', true),
  (pg_temp.us_id('inactive_room'), 'US-INACTIVE-' || pg_temp.us_id('inactive_room')::text, 'Closed Building', false);
insert into public.incident_categories (id, name, is_active)
values (pg_temp.us_id('category'), 'US-Test-' || pg_temp.us_id('category')::text, true);

insert into public.profiles (
  id, identity_code, full_name, email, phone, role, status, room_id, must_change_password
) values
  (pg_temp.us_id('admin'), 'US-ADMIN', 'Test Admin', 'us-admin@example.invalid', null, 'admin', 'active', null, false),
  (pg_temp.us_id('student'), 'US-STUDENT', 'Before Name', 'us-student@example.invalid', '0900000001', 'student', 'active', pg_temp.us_id('old_room'), false),
  (pg_temp.us_id('revoked_student'), 'US-REVOKED', 'Revoked Student', 'us-revoked@example.invalid', '0900000002', 'student', 'revoked', pg_temp.us_id('old_room'), true);

insert into public.repair_requests (
  id, student_id, room_id, room_code_snapshot, building_snapshot,
  category_id, category_name_snapshot, title, description
) values (
  pg_temp.us_id('old_request'), pg_temp.us_id('student'), pg_temp.us_id('old_room'),
  (select code from public.rooms where id = pg_temp.us_id('old_room')),
  'Old Building', pg_temp.us_id('category'), 'US Test', 'Existing request', 'Snapshot must remain unchanged'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.us_id('student')::text, true);
set local role authenticated;
select pg_temp.us_expect_error(
  'select public.admin_update_student(''US-STUDENT'', ''Name'', ''0912345678'', ''' || pg_temp.us_id('new_room')::text || '''::uuid)',
  '42501'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.us_id('admin')::text, true);
set local role authenticated;
do $$
declare v_details jsonb;
begin
  v_details := public.admin_get_student_edit_details('US-STUDENT');
  if v_details->>'full_name' <> 'Before Name'
    or v_details->>'phone' <> '0900000001'
    or v_details->'room'->>'id' <> pg_temp.us_id('old_room')::text
    or v_details ? 'email' or v_details ? 'identity_code' then
    raise exception 'FAIL: student edit details mismatch or exposes immutable fields';
  end if;
end $$;
select pg_temp.us_expect_error(
  'select public.admin_update_student(''US-STUDENT'', '''', ''0912345678'', ''' || pg_temp.us_id('new_room')::text || '''::uuid)',
  '22023', 'Họ tên Sinh viên không được để trống.'
);
select pg_temp.us_expect_error(
  'select public.admin_update_student(''US-STUDENT'', ''Name'', '''', ''' || pg_temp.us_id('new_room')::text || '''::uuid)',
  '22023', 'Số điện thoại không được để trống.'
);
select pg_temp.us_expect_error(
  'select public.admin_update_student(''US-STUDENT'', ''Name'', ''12345'', ''' || pg_temp.us_id('new_room')::text || '''::uuid)',
  '22023', 'Số điện thoại không đúng định dạng.'
);
select pg_temp.us_expect_error(
  'select public.admin_update_student(''US-STUDENT'', ''Name'', ''0912345678'', ''' || pg_temp.us_id('inactive_room')::text || '''::uuid)',
  'P0002', 'Chỉ được chuyển Sinh viên vào phòng đang hoạt động.'
);

select public.admin_update_student(
  'US-STUDENT', 'After Name', '+84912345678', pg_temp.us_id('new_room')
);

reset role;
do $$
begin
  if not exists (
    select 1 from public.profiles
    where id = pg_temp.us_id('student')
      and identity_code = 'US-STUDENT'
      and email = 'us-student@example.invalid'
      and full_name = 'After Name'
      and phone = '+84912345678'
      and room_id = pg_temp.us_id('new_room')
      and status = 'active'
      and not must_change_password
  ) then raise exception 'FAIL: updated student profile mismatch'; end if;
  if not exists (
    select 1 from public.repair_requests
    where id = pg_temp.us_id('old_request')
      and room_id = pg_temp.us_id('old_room')
      and room_code_snapshot = (select code from public.rooms where id = pg_temp.us_id('old_room'))
      and building_snapshot = 'Old Building'
  ) then raise exception 'FAIL: existing request room snapshot changed'; end if;
  if not exists (
    select 1 from public.request_history
    where entity_type = 'profile' and entity_id = pg_temp.us_id('student')
      and action = 'update_student'
  ) then raise exception 'FAIL: update history missing'; end if;
end $$;

set local role authenticated;
select pg_temp.us_expect_error(
  'select public.admin_update_student(''US-REVOKED'', ''Name'', ''0912345678'', ''' || pg_temp.us_id('new_room')::text || '''::uuid)',
  'P0002', 'Không tìm thấy Sinh viên có thể cập nhật.'
);
select pg_temp.us_expect_error(
  'select public.admin_get_student_edit_details(''US-REVOKED'')',
  'P0002', 'Không tìm thấy Sinh viên có thể cập nhật.'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.us_id('student')::text, true);
set local role authenticated;
do $$
begin
  if public.current_student_room() <> pg_temp.us_id('new_room') then
    raise exception 'FAIL: current student room was not updated';
  end if;
end $$;

rollback;
select 'PASS: DF-033 student profile and room update checks completed' as result;