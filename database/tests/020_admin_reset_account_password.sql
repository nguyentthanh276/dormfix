-- DF-038: Admin reset-password regression; all changes roll back.
-- Run as database owner after migrations 015-020.
begin;

create temporary table test_reset_password_fixture (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;
insert into test_reset_password_fixture(key) values
  ('admin'), ('student'), ('technician_locked'), ('admin_target'),
  ('student_session'), ('technician_session'), ('room');

create function pg_temp.rp_id(p_key text) returns uuid language sql stable as $$
  select id from test_reset_password_fixture where key = p_key;
$$;
create function pg_temp.rp_expect_error(
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
create function pg_temp.rp_assert(p_ok boolean, p_message text)
returns void language plpgsql as $$
begin
  if not p_ok then raise exception 'FAIL: %', p_message; end if;
end $$;
do $$ begin
  execute format('grant usage on schema %I to authenticated, anon',
    (select nspname from pg_namespace where oid = pg_my_temp_schema()));
end $$;
grant select on test_reset_password_fixture to authenticated, anon;
grant execute on function pg_temp.rp_id(text), pg_temp.rp_expect_error(text, text, text),
  pg_temp.rp_assert(boolean, text) to authenticated, anon;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  (pg_temp.rp_id('admin'), 'authenticated', 'authenticated', 'rp-admin@example.invalid',
   extensions.crypt('AdminPass1', extensions.gen_salt('bf', 4)), now(), now(), now()),
  (pg_temp.rp_id('student'), 'authenticated', 'authenticated', 'rp-student@example.invalid',
   extensions.crypt('OldStudent1', extensions.gen_salt('bf', 4)), now(), now(), now()),
  (pg_temp.rp_id('technician_locked'), 'authenticated', 'authenticated', 'rp-tech@example.invalid',
   extensions.crypt('OldTechPass1', extensions.gen_salt('bf', 4)), now(), now(), now()),
  (pg_temp.rp_id('admin_target'), 'authenticated', 'authenticated', 'rp-admin-target@example.invalid',
   extensions.crypt('AdminTarget1', extensions.gen_salt('bf', 4)), now(), now(), now());

insert into auth.sessions (id, user_id, created_at, updated_at) values
  (pg_temp.rp_id('student_session'), pg_temp.rp_id('student'), now(), now()),
  (pg_temp.rp_id('technician_session'), pg_temp.rp_id('technician_locked'), now(), now());

insert into public.rooms (id, code, building, is_active)
values (pg_temp.rp_id('room'), 'RP-ROOM-' || pg_temp.rp_id('room')::text, 'Reset Test', true);

insert into public.profiles (
  id, identity_code, full_name, email, phone, role, status, room_id, must_change_password
) values
  (pg_temp.rp_id('admin'), 'RP-ADMIN', 'Reset Admin', 'rp-admin@example.invalid', null, 'admin', 'active', null, false),
  (pg_temp.rp_id('student'), 'RP-STUDENT', 'Reset Student', 'rp-student@example.invalid', '0900000001', 'student', 'active', pg_temp.rp_id('room'), false),
  (pg_temp.rp_id('technician_locked'), 'RP-TECH', 'Locked Technician', 'rp-tech@example.invalid', '0900000002', 'technician', 'locked', null, false),
  (pg_temp.rp_id('admin_target'), 'RP-ADMIN-TARGET', 'Not Resettable Admin', 'rp-admin-target@example.invalid', null, 'admin', 'active', null, false);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rp_id('student')::text, true);
set local role authenticated;
select pg_temp.rp_expect_error(
  'select public.admin_reset_account_password(''RP-STUDENT'')', '42501'
);

reset role;
select set_config('request.jwt.claim.sub', pg_temp.rp_id('admin')::text, true);
set local role authenticated;
select pg_temp.rp_expect_error(
  'select public.admin_reset_account_password(''MISSING'')',
  'P0002', 'Không tìm thấy tài khoản hợp lệ.'
);
select pg_temp.rp_expect_error(
  'select public.admin_reset_account_password(''RP-ADMIN-TARGET'')',
  'P0002', 'Không tìm thấy tài khoản hợp lệ.'
);

do $$ declare v_student jsonb; v_technician jsonb;
begin
  v_student := public.admin_reset_account_password('RP-STUDENT');
  v_technician := public.admin_reset_account_password('RP-TECH');

  if v_student->>'temporary_password' is null
    or length(v_student->>'temporary_password') < 6
    or v_student->>'must_change_password' <> 'true'
    or v_student ? 'encrypted_password'
    or v_student ? 'password_hash' then
    raise exception 'FAIL: student receipt missing temp password/flag or leaked hash';
  end if;
  if v_technician->>'temporary_password' is null
    or v_technician->>'must_change_password' <> 'true'
    or v_technician->>'status' <> 'locked'
    or v_technician ? 'encrypted_password'
    or v_technician ? 'password_hash' then
    raise exception 'FAIL: technician reset changed status or leaked hash';
  end if;

  if not exists (
    select 1 from auth.users
    where id = pg_temp.rp_id('student')
      and encrypted_password = extensions.crypt(v_student->>'temporary_password', encrypted_password)
      and extensions.crypt('OldStudent1', encrypted_password) <> encrypted_password
  ) then raise exception 'FAIL: student password not hashed/reset'; end if;
  if not exists (
    select 1 from auth.users
    where id = pg_temp.rp_id('technician_locked')
      and encrypted_password = extensions.crypt(v_technician->>'temporary_password', encrypted_password)
      and extensions.crypt('OldTechPass1', encrypted_password) <> encrypted_password
  ) then raise exception 'FAIL: technician password not hashed/reset'; end if;
  if not exists (
    select 1 from public.profiles where id = pg_temp.rp_id('student') and must_change_password
  ) or not exists (
    select 1 from public.profiles where id = pg_temp.rp_id('technician_locked')
      and must_change_password and status = 'locked'
  ) then raise exception 'FAIL: password-change flag or account status mismatch'; end if;
  if exists (
    select 1 from auth.sessions
    where user_id in (pg_temp.rp_id('student'), pg_temp.rp_id('technician_locked'))
  ) then raise exception 'FAIL: old auth sessions were not revoked'; end if;
  if not exists (
    select 1 from public.request_history
    where entity_type = 'profile' and action = 'admin_reset_password'
      and entity_id = pg_temp.rp_id('student') and actor_id = pg_temp.rp_id('admin')
      and occurred_at is not null
  ) then raise exception 'FAIL: student reset history missing'; end if;
end $$;

rollback;
select 'PASS: DF-038 reset password checks completed' as result;