-- DF-032: SQL regression for Admin-created technician accounts.
-- Run as database owner after migrations 015 and 016; all fixtures roll back.
begin;

create temporary table test_create_technician_fixture (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;

insert into test_create_technician_fixture(key) values
  ('admin'), ('admin_gated'), ('admin_locked'), ('student_actor'),
  ('revoked_technician'), ('auth_only'), ('active_technician'), ('room');

create function pg_temp.ct_id(p_key text) returns uuid language sql stable as $$
  select id from test_create_technician_fixture where key = p_key;
$$;

create function pg_temp.ct_expect_error(
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
grant select on test_create_technician_fixture to authenticated, anon;
grant execute on function pg_temp.ct_id(text), pg_temp.ct_expect_error(text, text, text)
  to authenticated, anon;

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@ct-test.invalid', now(), now(), now()
from test_create_technician_fixture
where key in ('admin', 'admin_gated', 'admin_locked', 'student_actor', 'revoked_technician', 'active_technician');
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values (pg_temp.ct_id('auth_only'), 'authenticated', 'authenticated', 'auth-only@ct-test.invalid', now(), now(), now());

insert into public.rooms (id, code, building, is_active)
values (pg_temp.ct_id('room'), 'CT-TEST-' || pg_temp.ct_id('room')::text, 'Test', true);

insert into public.profiles (
  id, identity_code, full_name, email, phone, role, status, room_id, must_change_password
) values
  (pg_temp.ct_id('admin'), 'CT-ADMIN', 'Test Admin', pg_temp.ct_id('admin')::text || '@ct-test.invalid', null, 'admin', 'active', null, false),
  (pg_temp.ct_id('admin_gated'), 'CT-ADMIN-GATED', 'Gated Admin', pg_temp.ct_id('admin_gated')::text || '@ct-test.invalid', null, 'admin', 'active', null, true),
  (pg_temp.ct_id('admin_locked'), 'CT-ADMIN-LOCKED', 'Locked Admin', pg_temp.ct_id('admin_locked')::text || '@ct-test.invalid', null, 'admin', 'locked', null, false),
  (pg_temp.ct_id('student_actor'), 'CT-STUDENT', 'Test Student', pg_temp.ct_id('student_actor')::text || '@ct-test.invalid', '0900000001', 'student', 'active', pg_temp.ct_id('room'), false),
  (pg_temp.ct_id('revoked_technician'), 'KTV-REVOKED-CT', 'Revoked Technician', 'revoked-ct@ct-test.invalid', '0900000002', 'technician', 'revoked', null, true),
  (pg_temp.ct_id('active_technician'), 'KTV-ACTIVE-CT', 'Active Technician', pg_temp.ct_id('active_technician')::text || '@ct-test.invalid', '0900000003', 'technician', 'active', null, false);

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-TEST'', ''Name'', ''test@ct.com'', ''0912345678'')',
  '42501'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.ct_id('student_actor')::text, true);
set local role authenticated;
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-TEST'', ''Name'', ''test@ct.com'', ''0912345678'')',
  '42501', 'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.ct_id('admin_gated')::text, true);
set local role authenticated;
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-TEST'', ''Name'', ''test@ct.com'', ''0912345678'')',
  '42501', 'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.'
);
reset role;
select set_config('request.jwt.claim.sub', pg_temp.ct_id('admin_locked')::text, true);
set local role authenticated;
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-TEST'', ''Name'', ''test@ct.com'', ''0912345678'')',
  '42501', 'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.ct_id('admin')::text, true);
set local role authenticated;
select pg_temp.ct_expect_error(
  'select public.admin_create_technician('''', ''Name'', ''new@ct.com'', ''0912345678'')',
  '22023', 'Mã Kỹ thuật viên không được để trống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-X'', '''', ''new@ct.com'', ''0912345678'')',
  '22023', 'Họ tên Kỹ thuật viên không được để trống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-X'', ''Name'', '''', ''0912345678'')',
  '22023', 'Email không được để trống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-X'', ''Name'', ''bad-email'', ''0912345678'')',
  '22023', 'Email không đúng định dạng.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-X'', ''Name'', ''new@ct.com'', '''')',
  '22023', 'Số điện thoại không được để trống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-X'', ''Name'', ''new@ct.com'', ''12345'')',
  '22023', 'Số điện thoại không đúng định dạng.'
);

do $$
declare v_result jsonb; v_id uuid;
begin
  v_result := public.admin_create_technician(
    'KTV-NEW-CT', 'New Technician', 'new-ct@ct-test.invalid', '0912345678', 'Temp@123'
  );
  v_id := (v_result->>'id')::uuid;
  if v_id is null or v_result->>'role' <> 'technician'
    or v_result->>'status' <> 'active'
    or v_result->>'must_change_password' <> 'true'
    or v_result->>'temporary_password' <> 'Temp@123' then
    raise exception 'FAIL: incorrect creation response';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = v_id and identity_code = 'KTV-NEW-CT'
      and email = 'new-ct@ct-test.invalid' and phone = '0912345678'
      and role = 'technician' and status = 'active'
      and room_id is null and must_change_password
  ) then raise exception 'FAIL: incorrect technician profile'; end if;
  if not exists (
    select 1 from auth.users where id = v_id and email = 'new-ct@ct-test.invalid'
      and encrypted_password is not null
  ) then raise exception 'FAIL: Auth user or password hash missing'; end if;
  if not exists (
    select 1 from public.request_history
    where entity_type = 'profile' and entity_id = v_id and action = 'create_technician'
  ) then raise exception 'FAIL: creation history missing'; end if;
end $$;

select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''ktv-revoked-ct'', ''Other'', ''newer@ct.com'', ''0988888888'')',
  '23505', 'Mã Kỹ thuật viên đã tồn tại trên hệ thống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-OTHER-CT'', ''Other'', ''REVOKED-CT@CT-TEST.INVALID'', ''0988888888'')',
  '23505', 'Email đã tồn tại trên hệ thống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-OTHER-CT'', ''Other'', ''AUTH-ONLY@CT-TEST.INVALID'', ''0988888888'')',
  '23505', 'Email đã tồn tại trên hệ thống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-NEW-CT'', ''Other'', ''another@ct.com'', ''0988888888'')',
  '23505', 'Mã Kỹ thuật viên đã tồn tại trên hệ thống.'
);
select pg_temp.ct_expect_error(
  'select public.admin_create_technician(''KTV-OTHER-CT'', ''Other'', ''new-ct@ct-test.invalid'', ''0988888888'')',
  '23505', 'Email đã tồn tại trên hệ thống.'
);

do $$
declare v_first jsonb; v_second jsonb;
begin
  v_first := public.admin_create_technician(
    'KTV-SHARED-PHONE-1', 'First Shared Phone', 'shared1@ct-test.invalid', '0909999999'
  );
  v_second := public.admin_create_technician(
    'KTV-SHARED-PHONE-2', 'Second Shared Phone', 'shared2@ct-test.invalid', '0909999999'
  );
  if v_first->>'temporary_password' is null or length(v_first->>'temporary_password') < 6
    or v_second->>'temporary_password' is null or length(v_second->>'temporary_password') < 6 then
    raise exception 'FAIL: generated temporary password missing';
  end if;
  if v_first->>'phone' <> v_second->>'phone' then
    raise exception 'FAIL: shared phone should be allowed';
  end if;
end $$;

rollback;
select 'PASS: DF-032 technician account creation checks completed' as result;