-- Owner-run Admin account regression. Synthetic Auth credentials are fake
-- hash placeholders used only to exercise the database gate, never to log in.
-- Every fixture and mutation is rolled back.
begin;

create temporary table account_test_ids(key text primary key,id uuid not null default gen_random_uuid()) on commit drop;
insert into account_test_ids(key) values
 ('admin'),('second_admin'),('student'),('technician'),('unmanaged'),('failed_user'),
 ('old_room'),('new_room'),('inactive_room'),('missing');
grant select on account_test_ids to anon,authenticated;
do $$ begin
  execute format('grant usage on schema %I to anon,authenticated',
    (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;
create function pg_temp.ap_id(p_key text) returns uuid language sql stable as $$
  select id from account_test_ids where key=p_key;
$$;
create function pg_temp.ap_code(p_key text) returns text language sql stable as $$
  select 'AP-'||pg_temp.ap_id(p_key)::text;
$$;
create function pg_temp.ap_email(p_key text) returns text language sql stable as $$
  select pg_temp.ap_id(p_key)::text||'@account-test.invalid';
$$;
create function pg_temp.ap_expect_error(p_sql text,p_state text,p_message text default null)
returns void language plpgsql as $$
declare v_state text; v_message text;
begin
  begin execute p_sql;
  exception when others then
    get stacked diagnostics v_state=returned_sqlstate,v_message=message_text;
    if v_state<>p_state or (p_message is not null and v_message<>p_message) then
      raise exception 'FAIL: expected % %, got % %',p_state,p_message,v_state,v_message;
    end if;
    return;
  end;
  raise exception 'FAIL: expected % %',p_state,p_message;
end $$;
grant execute on function pg_temp.ap_id(text),pg_temp.ap_code(text),pg_temp.ap_email(text),
  pg_temp.ap_expect_error(text,text,text) to anon,authenticated;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',pg_temp.ap_email(key),now(),now(),now()
from account_test_ids where key in ('admin','second_admin','unmanaged');
insert into public.profiles(id,identity_code,full_name,email,role,must_change_password)
select id,pg_temp.ap_code(key),'Provision test Admin',pg_temp.ap_email(key),'admin',false
from account_test_ids where key in ('admin','second_admin');
insert into public.rooms(id,code,building,is_active)
select id,pg_temp.ap_code(key),'Fixture building',key<>'inactive_room'
from account_test_ids where key in ('old_room','new_room','inactive_room');

do $$ declare v_sig text; begin
  foreach v_sig in array array['public.admin_get_account(text)',
    'public.admin_prepare_account_provision(text,text,text,text,text,uuid)',
    'public.admin_cancel_account_provision(uuid)','public.admin_update_account(uuid,text,text,uuid)',
    'public.complete_change_password()'] loop
    if has_function_privilege('anon',v_sig,'EXECUTE')
      or not has_function_privilege('authenticated',v_sig,'EXECUTE') then
      raise exception 'FAIL: incorrect account RPC ACL'; end if;
  end loop;
  if has_schema_privilege('authenticated','dormfix_private','USAGE')
    or has_schema_privilege('anon','dormfix_private','USAGE')
    or has_schema_privilege('service_role','dormfix_private','USAGE')
    or has_table_privilege('authenticated','dormfix_private.account_provisions','SELECT')
    or has_table_privilege('authenticated','dormfix_private.initial_password_gates','SELECT')
    or has_table_privilege('authenticated','public.profiles','UPDATE')
    or has_table_privilege('authenticated','public.profiles','INSERT') then
    raise exception 'FAIL: private state or profile mutation exposed'; end if;
end $$;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.ap_expect_error('select public.complete_change_password()','42501');
select pg_temp.ap_expect_error('select public.admin_get_account(null)','42501');
reset role;

-- Only the active Admin can prepare, target roles/rooms/identity are validated.
select set_config('request.jwt.claim.sub',pg_temp.ap_id('admin')::text,true);
set local role authenticated;
do $$ declare v_provision jsonb; begin
  perform pg_temp.ap_expect_error('select public.admin_get_account(pg_temp.ap_code(''admin''))','P0002','ACCOUNT_NOT_FOUND');
  perform pg_temp.ap_expect_error('select public.admin_prepare_account_provision(''x'',''x'',''x@invalid.example'',''0900000000'',''admin'',null)',
    '22023','INVALID_ACCOUNT_INPUT');
  perform pg_temp.ap_expect_error('select public.admin_prepare_account_provision(''x'',''x'',''x@invalid.example'',''bad'',''technician'',null)',
    '22023','INVALID_ACCOUNT_PHONE');
  perform pg_temp.ap_expect_error('select public.admin_prepare_account_provision(''x'',''x'',''x@invalid.example'',''0900000000'',''student'',pg_temp.ap_id(''inactive_room''))',
    '22023','ACTIVE_STUDENT_ROOM_REQUIRED');
  perform pg_temp.ap_expect_error('select public.admin_prepare_account_provision(''x'',''x'',''x@invalid.example'',''0900000000'',''technician'',pg_temp.ap_id(''old_room''))',
    '22023','INVALID_ACCOUNT_INPUT');
  perform pg_temp.ap_expect_error('select public.admin_prepare_account_provision(''x'',''x'',pg_temp.ap_email(''unmanaged''),''0900000000'',''technician'',null)',
    '23505','ACCOUNT_EMAIL_ALREADY_EXISTS');
  v_provision:=public.admin_prepare_account_provision(' '||pg_temp.ap_code('student')||' ',
    ' Student Fixture ',upper(pg_temp.ap_email('student')),'090.000.0000','student',pg_temp.ap_id('old_room'));
  if v_provision->>'email' is distinct from pg_temp.ap_email('student')
    or jsonb_typeof(v_provision->'provision_id') is distinct from 'string'
    or (select count(*) from jsonb_object_keys(v_provision))<>2 then
    raise exception 'FAIL: preparation receipt'; end if;
  perform set_config('dormfix.test.student_provision',v_provision->>'provision_id',true);
  v_provision:=public.admin_prepare_account_provision(pg_temp.ap_code('technician'),
    'Technician Fixture',pg_temp.ap_email('technician'),'+84 900 000 000','technician',null);
  perform set_config('dormfix.test.tech_provision',v_provision->>'provision_id',true);
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.ap_id('second_admin')::text,true);
set local role authenticated;
do $$ begin
  if public.admin_cancel_account_provision(current_setting('dormfix.test.student_provision')::uuid) then
    raise exception 'FAIL: another Admin can consume provision'; end if;
end $$;
reset role;

-- Current GoTrue writes app_metadata after INSERT in the same transaction.
-- Raw user metadata is not a trusted provisioning signal.
insert into auth.users(id,aud,role,email,email_confirmed_at,encrypted_password,raw_user_meta_data,created_at,updated_at)
values(pg_temp.ap_id('student'),'authenticated','authenticated',pg_temp.ap_email('student'),now(),'fixture-initial-hash',
  jsonb_build_object('dormfix_provision_id',current_setting('dormfix.test.student_provision')),now(),now());
do $$ begin
  if exists(select 1 from public.profiles where id=pg_temp.ap_id('student')) then
    raise exception 'FAIL: client user metadata created an app profile'; end if;
end $$;
update auth.users set raw_app_meta_data=jsonb_build_object('provider','email',
  'dormfix_provision_id',current_setting('dormfix.test.student_provision')) where id=pg_temp.ap_id('student');
insert into auth.users(id,aud,role,email,email_confirmed_at,encrypted_password,raw_app_meta_data,created_at,updated_at)
values(pg_temp.ap_id('technician'),'authenticated','authenticated',pg_temp.ap_email('technician'),now(),'fixture-initial-hash',
  jsonb_build_object('dormfix_provision_id',current_setting('dormfix.test.tech_provision')),now(),now());
do $$ begin
  if (select count(*) from public.profiles where id in(pg_temp.ap_id('student'),pg_temp.ap_id('technician'))
      and must_change_password and status='active')<>2
    or (select count(*) from dormfix_private.initial_password_gates
        where account_id in(pg_temp.ap_id('student'),pg_temp.ap_id('technician')))<>2
    or exists(select 1 from dormfix_private.account_provisions where id in(
        current_setting('dormfix.test.student_provision')::uuid,current_setting('dormfix.test.tech_provision')::uuid))
    or exists(select 1 from auth.users where id in(pg_temp.ap_id('student'),pg_temp.ap_id('technician'))
        and raw_app_meta_data ? 'dormfix_provision_id')
    or (select count(*) from public.request_history where entity_type='profile'
      and entity_id in(pg_temp.ap_id('student'),pg_temp.ap_id('technician'))
      and action='admin_account_created' and actor_id=pg_temp.ap_id('admin') and request_id is null)<>2 then
    raise exception 'FAIL: atomic Auth/profile/gate/audit provisioning'; end if;
end $$;

-- Metadata mismatch must roll back the Auth insertion too, with no leaked row.
do $$ begin
  begin
    insert into auth.users(id,aud,role,email,encrypted_password,created_at,updated_at)
    values(pg_temp.ap_id('failed_user'),'authenticated','authenticated',pg_temp.ap_email('failed_user'),
      'fixture-initial-hash',now(),now());
    update auth.users set raw_app_meta_data=jsonb_build_object('dormfix_provision_id',
      current_setting('dormfix.test.student_provision')) where id=pg_temp.ap_id('failed_user');
    raise exception 'FAIL: replayed provisioning accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'INVALID_ACCOUNT_PROVISION' then raise; end if;
  end;
  if exists(select 1 from auth.users where id=pg_temp.ap_id('failed_user'))
     or exists(select 1 from public.profiles where id=pg_temp.ap_id('failed_user')) then
    raise exception 'FAIL: failed provision retained Auth/profile row'; end if;
end $$;

-- The existing first-login RPC cannot be forged from a temporary-password JWT.
select set_config('request.jwt.claim.sub',pg_temp.ap_id('student')::text,true);
set local role authenticated;
select pg_temp.ap_expect_error('select public.admin_get_account(pg_temp.ap_code(''student''))','42501');
select pg_temp.ap_expect_error('select public.complete_change_password()','P0001','PASSWORD_CHANGE_NOT_VERIFIED');
reset role;
select pg_temp.ap_expect_error('update auth.users set email=''changed@account-test.invalid'' where id=pg_temp.ap_id(''student'')',
 '42501','ACCOUNT_EMAIL_IMMUTABLE');
select pg_temp.ap_expect_error('update auth.users set email_change=''changed@account-test.invalid'' where id=pg_temp.ap_id(''student'')',
 '42501','ACCOUNT_EMAIL_IMMUTABLE');
update auth.users set email='changed-'||pg_temp.ap_email('unmanaged') where id=pg_temp.ap_id('unmanaged');
update auth.users set encrypted_password='fixture-changed-hash' where id=pg_temp.ap_id('student');
set local role authenticated;
do $$ declare v_first jsonb; v_retry jsonb; begin
  v_first:=public.complete_change_password();
  v_retry:=public.complete_change_password();
  if v_first->>'can_access' is distinct from 'true' or v_first->>'must_change_password' is distinct from 'false'
    or v_retry is distinct from v_first then raise exception 'FAIL: verified password completion'; end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.ap_id('admin')::text,true);
set local role authenticated;
do $$ declare v_original jsonb; v_updated jsonb; v_retry jsonb; begin
  v_original:=public.admin_get_account(lower(pg_temp.ap_code('student')));
  if v_original->>'email' is distinct from pg_temp.ap_email('student')
    or v_original->>'phone' is distinct from '0900000000'
    or v_original->>'room_id' is distinct from pg_temp.ap_id('old_room')::text then
    raise exception 'FAIL: normalized Admin detail'; end if;
  perform pg_temp.ap_expect_error('select public.admin_prepare_account_provision(lower(pg_temp.ap_code(''student'')),''x'',''x@invalid.example'',''0900000000'',''technician'',null)',
    '23505','ACCOUNT_IDENTITY_ALREADY_EXISTS');
  perform pg_temp.ap_expect_error('select public.admin_prepare_account_provision(''x'',''x'',pg_temp.ap_email(''student''),''0900000000'',''technician'',null)',
    '23505','ACCOUNT_EMAIL_ALREADY_EXISTS');
  perform pg_temp.ap_expect_error('select public.admin_update_account(pg_temp.ap_id(''student''),''Student Updated'',''0900000001'',pg_temp.ap_id(''inactive_room''))',
    '22023','ACTIVE_STUDENT_ROOM_REQUIRED');
  perform pg_temp.ap_expect_error('select public.admin_update_account(pg_temp.ap_id(''admin''),''Admin Updated'',''0900000001'',null)',
    'P0002','ACCOUNT_NOT_FOUND');
  v_updated:=public.admin_update_account(pg_temp.ap_id('student'),' Student Updated ','0900 000 001',pg_temp.ap_id('new_room'));
  v_retry:=public.admin_update_account(pg_temp.ap_id('student'),'Student Updated','0900000001',pg_temp.ap_id('new_room'));
  if v_updated->>'full_name' is distinct from 'Student Updated'
    or v_updated->>'room_id' is distinct from pg_temp.ap_id('new_room')::text
    or v_updated->>'identity_code' is distinct from v_original->>'identity_code'
    or v_updated->>'email' is distinct from v_original->>'email'
    or v_updated->>'role' is distinct from v_original->>'role'
    or v_updated->>'changed' is distinct from 'true'
    or v_retry is distinct from jsonb_set(v_updated,'{changed}','false') then
    raise exception 'FAIL: guarded update receipt or no-op'; end if;
end $$;
reset role;

-- Losing access between the Edge prepare and Auth write aborts the write.
set local role authenticated;
select set_config('dormfix.test.denied_provision',public.admin_prepare_account_provision(
  pg_temp.ap_code('failed_user'),'Denied Fixture',pg_temp.ap_email('failed_user'),'0900000000','technician',null)->>'provision_id',true);
reset role;
update public.profiles set status='locked' where id=pg_temp.ap_id('admin');
select pg_temp.ap_expect_error('insert into auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,created_at,updated_at)
 values(pg_temp.ap_id(''failed_user''),''authenticated'',''authenticated'',pg_temp.ap_email(''failed_user''),''fixture-initial-hash'',
 jsonb_build_object(''dormfix_provision_id'',current_setting(''dormfix.test.denied_provision'')),now(),now())',
 '42501','ACCOUNT_PROVISION_ADMIN_DENIED');
update public.profiles set status='active' where id=pg_temp.ap_id('admin');
set local role authenticated;
do $$ declare v_first boolean; v_retry boolean; begin
  v_first:=public.admin_cancel_account_provision(current_setting('dormfix.test.denied_provision')::uuid);
  v_retry:=public.admin_cancel_account_provision(current_setting('dormfix.test.denied_provision')::uuid);
  if not v_first or v_retry then
    raise exception 'FAIL: own provisioning cancellation'; end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from auth.users where id=pg_temp.ap_id('failed_user'))
    or exists(select 1 from dormfix_private.initial_password_gates where account_id=pg_temp.ap_id('student'))
    or (select count(*) from public.request_history where entity_type='profile'
      and entity_id=pg_temp.ap_id('student') and action='admin_account_updated' and actor_id=pg_temp.ap_id('admin'))<>1 then
    raise exception 'FAIL: account audit, consumed password gate or denied Auth write'; end if;
end $$;

rollback;
select 'PASS: Admin account provisioning, immutable identity/email, guarded update and verified password change' as result;
