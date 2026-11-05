-- DF-031: Admin tạo tài khoản Sinh viên và gắn phòng - Test Suite
-- Chạy với database owner/SQL Editor. Mọi dữ liệu fixture và mutation đều rollback.
begin;

-- Fixture temporary table
create temporary table test_create_student_fixture (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;

insert into test_create_student_fixture(key) values
  ('admin'),
  ('admin_gated'),
  ('admin_locked'),
  ('student_actor'),
  ('active_room'),
  ('inactive_room'),
  ('revoked_student');

grant select on test_create_student_fixture to authenticated, anon;

create function pg_temp.cs_id(p_key text) returns uuid language sql stable as $$
  select id from test_create_student_fixture where key = p_key;
$$;

create function pg_temp.cs_expect_error(p_sql text, p_state text, p_message text default null)
returns void language plpgsql as $$
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

grant execute on function pg_temp.cs_id(text), pg_temp.cs_expect_error(text, text, text)
  to authenticated, anon;

-- Setup Auth users and profiles
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@cs-test.invalid', now(), now(), now()
from test_create_student_fixture
where key in ('admin', 'admin_gated', 'admin_locked', 'student_actor', 'revoked_student');

insert into public.rooms (id, code, building, is_active)
values
  (pg_temp.cs_id('active_room'), 'CS-ACTIVE-101', 'Tòa A', true),
  (pg_temp.cs_id('inactive_room'), 'CS-INACTIVE-999', 'Tòa B', false);

insert into public.profiles (
  id, identity_code, full_name, email, phone, role, status, room_id, must_change_password
) values
  (pg_temp.cs_id('admin'), 'CS-ADMIN01', 'Test Admin',
   pg_temp.cs_id('admin')::text || '@cs-test.invalid', null, 'admin', 'active', null, false),
  (pg_temp.cs_id('admin_gated'), 'CS-ADMIN02', 'Gated Admin',
   pg_temp.cs_id('admin_gated')::text || '@cs-test.invalid', null, 'admin', 'active', null, true),
  (pg_temp.cs_id('admin_locked'), 'CS-ADMIN03', 'Locked Admin',
   pg_temp.cs_id('admin_locked')::text || '@cs-test.invalid', null, 'admin', 'locked', null, false),
  (pg_temp.cs_id('student_actor'), 'CS-SV001', 'Test Student',
   pg_temp.cs_id('student_actor')::text || '@cs-test.invalid', '0900000001', 'student', 'active',
   pg_temp.cs_id('active_room'), false),
  (pg_temp.cs_id('revoked_student'), 'CS-REVOKED-SV', 'Revoked Student',
   'revoked_student@cs-test.invalid', '0900000002', 'student', 'revoked',
   pg_temp.cs_id('active_room'), true);

-- TEST 1: Anon caller bị từ chối
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SVTEST'', ''Name'', ''test@ex.com'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '42501'
);

-- TEST 2: Student caller bị từ chối
reset role;
select set_config('request.jwt.claim.sub', pg_temp.cs_id('student_actor')::text, true);
set local role authenticated;
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SVTEST'', ''Name'', ''test@ex.com'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '42501',
  'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.'
);

-- TEST 3: Admin đang bị khóa hoặc chưa đổi mật khẩu bị từ chối
reset role;
select set_config('request.jwt.claim.sub', pg_temp.cs_id('admin_gated')::text, true);
set local role authenticated;
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SVTEST'', ''Name'', ''test@ex.com'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '42501',
  'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.cs_id('admin_locked')::text, true);
set local role authenticated;
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SVTEST'', ''Name'', ''test@ex.com'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '42501',
  'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.'
);

-- BẮT ĐẦU TEST VỚI ADMIN HỢP LỆ
reset role;
select set_config('request.jwt.claim.sub', pg_temp.cs_id('admin')::text, true);
set local role authenticated;

-- TEST 4: Kiểm tra dữ liệu bắt buộc và định dạng
-- 4a. Mã SV rỗng
select pg_temp.cs_expect_error(
  format('select public.admin_create_student('''', ''Nguyễn Văn A'', ''sv@test.com'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '22023',
  'Mã Sinh viên không được để trống.'
);

-- 4b. Họ tên rỗng
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SV99001'', '''', ''sv@test.com'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '22023',
  'Họ tên Sinh viên không được để trống.'
);

-- 4c. Email rỗng hoặc sai định dạng
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SV99001'', ''Nguyễn Văn A'', '''', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '22023',
  'Email không được để trống.'
);

select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SV99001'', ''Nguyễn Văn A'', ''invalid-email'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '22023',
  'Email không đúng định dạng.'
);

-- 4d. Số điện thoại sai định dạng (dưới 10 số, chứa chữ,...)
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SV99001'', ''Nguyễn Văn A'', ''sv@test.com'', ''0912345'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '22023',
  'Số điện thoại không đúng định dạng.'
);

select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SV99001'', ''Nguyễn Văn A'', ''sv@test.com'', ''09abcdef12'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '22023',
  'Số điện thoại không đúng định dạng.'
);

-- 4e. Phòng không tồn tại
select pg_temp.cs_expect_error(
  'select public.admin_create_student(''SV99001'', ''Nguyễn Văn A'', ''sv@test.com'', ''0912345678'', gen_random_uuid())',
  'P0002',
  'Phòng không tồn tại.'
);

-- 4f. Phòng không hoạt động
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SV99001'', ''Nguyễn Văn A'', ''sv@test.com'', ''0912345678'', ''%s''::uuid)', pg_temp.cs_id('inactive_room')),
  '22023',
  'Chỉ được gắn Sinh viên vào phòng đang hoạt động.'
);

-- TEST 5: Tạo tài khoản Sinh viên thành công
do $$
declare
  v_res jsonb;
  v_new_id uuid;
begin
  v_res := public.admin_create_student(
    'SV99001',
    'Trần Sinh Viên Mới',
    'sv99001@example.com',
    '0912345678',
    pg_temp.cs_id('active_room')
  );

  v_new_id := (v_res->>'id')::uuid;
  if v_new_id is null then raise exception 'FAIL: user id is null'; end if;
  if (v_res->>'identity_code') <> 'SV99001' then raise exception 'FAIL: identity_code mismatch'; end if;
  if (v_res->>'must_change_password') <> 'true' then raise exception 'FAIL: must_change_password not true'; end if;
  if (v_res->>'role') <> 'student' then raise exception 'FAIL: role is not student'; end if;
  if (v_res->>'status') <> 'active' then raise exception 'FAIL: status is not active'; end if;
  if (v_res->>'temporary_password') is null or length(v_res->>'temporary_password') < 6 then
    raise exception 'FAIL: temporary password missing or too short';
  end if;

  -- Xác minh dữ liệu trong bảng public.profiles
  if not exists (
    select 1 from public.profiles
    where id = v_new_id
      and identity_code = 'SV99001'
      and email = 'sv99001@example.com'
      and phone = '0912345678'
      and role = 'student'
      and status = 'active'
      and must_change_password = true
      and room_id = pg_temp.cs_id('active_room')
  ) then
    raise exception 'FAIL: profile row was not created properly';
  end if;

  -- Xác minh bản ghi auth.users
  if not exists (select 1 from auth.users where id = v_new_id and email = 'sv99001@example.com') then
    raise exception 'FAIL: auth user was not created';
  end if;

  -- Xác minh lịch sử request_history
  if not exists (
    select 1 from public.request_history
    where entity_type = 'profile' and entity_id = v_new_id and action = 'create_student'
  ) then
    raise exception 'FAIL: request_history not logged';
  end if;
end $$;

-- TEST 6: Trùng mã Sinh viên (case-insensitive)
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''sv99001'', ''Người Khác'', ''other@example.com'', ''0988888888'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '23505',
  'Mã Sinh viên đã tồn tại trên hệ thống.'
);

-- TEST 7: Trùng email (case-insensitive)
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SV99002'', ''Người Khác'', ''SV99001@example.com'', ''0988888888'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '23505',
  'Email đã tồn tại trên hệ thống.'
);

-- TEST 8: Tài khoản đã thu hồi (revoked) KHÔNG được tái sử dụng mã hoặc email
-- 8a. Trùng mã sinh viên đã thu hồi
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''cs-revoked-sv'', ''Người Khác'', ''newmail@example.com'', ''0988888888'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '23505',
  'Mã Sinh viên đã tồn tại trên hệ thống.'
);

-- 8b. Trùng email tài khoản đã thu hồi
select pg_temp.cs_expect_error(
  format('select public.admin_create_student(''SVNEW99'', ''Người Khác'', ''revoked_student@cs-test.invalid'', ''0988888888'', ''%s''::uuid)', pg_temp.cs_id('active_room')),
  '23505',
  'Email đã tồn tại trên hệ thống.'
);

-- TEST 9: Sinh viên đăng nhập lần đầu phải đổi mật khẩu (can_access = false)
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code = 'SV99001'), true);
set local role authenticated;
do $$
declare
  v_my_prof jsonb;
begin
  v_my_prof := public.get_my_profile();
  if (v_my_prof->>'must_change_password') <> 'true' then
    raise exception 'FAIL: first login must have must_change_password=true';
  end if;
  if (v_my_prof->>'can_access') <> 'false' then
    raise exception 'FAIL: first login must have can_access=false';
  end if;
end $$;

-- TEST 10: Ràng buộc không cho phép thay đổi mã Sinh viên và Email sau khi tạo
reset role;
do $$ begin
  update public.profiles set identity_code = 'SV-CHANGED' where identity_code = 'SV99001';
  raise exception 'FAIL: updating identity_code should have thrown error';
exception when others then
  if sqlstate <> '22023' then raise exception 'FAIL: unexpected error %', sqlstate; end if;
end $$;

do $$ begin
  update public.profiles set email = 'changed@example.com' where identity_code = 'SV99001';
  raise exception 'FAIL: updating email should have thrown error';
exception when others then
  if sqlstate <> '22023' then raise exception 'FAIL: unexpected error %', sqlstate; end if;
end $$;

-- TEST 11: admin_get_active_rooms chỉ trả phòng đang hoạt động
reset role;
select set_config('request.jwt.claim.sub', pg_temp.cs_id('admin')::text, true);
set local role authenticated;
do $$
declare
  v_rooms jsonb;
begin
  v_rooms := public.admin_get_active_rooms();
  if not exists (select 1 from jsonb_array_elements(v_rooms) r where (r->>'id')::uuid = pg_temp.cs_id('active_room')) then
    raise exception 'FAIL: active room missing from active rooms list';
  end if;
  if exists (select 1 from jsonb_array_elements(v_rooms) r where (r->>'id')::uuid = pg_temp.cs_id('inactive_room')) then
    raise exception 'FAIL: inactive room should not be present in active rooms list';
  end if;
end $$;

rollback;

select 'PASS: Tất cả kiểm thử DF-031 Admin tạo tài khoản Sinh viên và gắn phòng đã thành công' as result;

