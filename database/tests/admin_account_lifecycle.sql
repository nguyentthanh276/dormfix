-- Owner-run rollback test for DF-035–038. Auth hashes and sessions are fixtures.
begin;

create temporary table lifecycle_ids(key text primary key,id uuid not null default gen_random_uuid()) on commit drop;
insert into lifecycle_ids(key) values
 ('admin'),('other_admin'),('student'),('technician'),('old_room'),('new_room'),('inactive_room'),
 ('category'),('request'),('old_session'),('late_session'),('reset_session'),('new_session');
grant select on lifecycle_ids to anon,authenticated;
do $$ begin
  execute format('grant usage on schema %I to anon,authenticated',
    (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;
create function pg_temp.al_id(p_key text) returns uuid language sql stable as $$
  select id from lifecycle_ids where key=p_key;
$$;
create function pg_temp.al_claims(p_account text,p_session text default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'role','authenticated','sub',pg_temp.al_id(p_account),'session_id',pg_temp.al_id(p_session))::text,true);
end $$;
create function pg_temp.al_expect_error(p_sql text,p_state text,p_message text default null)
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
grant execute on function pg_temp.al_id(text),pg_temp.al_claims(text,text),
  pg_temp.al_expect_error(text,text,text) to anon,authenticated;

insert into auth.users(id,aud,role,email,email_confirmed_at,encrypted_password,banned_until,created_at,updated_at)
select id,'authenticated','authenticated',id::text||'@account-lifecycle-test.invalid',now(),
  'fixture-original-hash',case when key='technician' then now()+interval '4 days' end,now(),now()
from lifecycle_ids where key in ('admin','other_admin','student','technician');
insert into public.rooms(id,code,building,is_active)
select id,'AL-'||id::text,'Fixture building',key<>'inactive_room'
from lifecycle_ids where key in ('old_room','new_room','inactive_room');
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'AL-'||id::text,'Lifecycle fixture',id::text||'@account-lifecycle-test.invalid','0900000000',
  case key when 'student' then 'student' when 'technician' then 'technician' else 'admin' end::public.app_role,
  case when key='student' then pg_temp.al_id('old_room') end,false
from lifecycle_ids where key in ('admin','other_admin','student','technician');
insert into auth.sessions(id,user_id,created_at,updated_at)
values(pg_temp.al_id('old_session'),pg_temp.al_id('student'),now()-interval '1 hour',now());
insert into public.incident_categories(id,name)
values(pg_temp.al_id('category'),'Lifecycle fixture '||pg_temp.al_id('category')::text);
insert into public.repair_requests(id,request_number,student_id,room_id,room_code_snapshot,building_snapshot,
  category_id,category_name_snapshot,title,description,status,assigned_technician_id) overriding system value
values(pg_temp.al_id('request'),-1-(('x'||left(replace(pg_temp.al_id('request')::text,'-',''),15))::bit(60)::bigint),
  pg_temp.al_id('student'),pg_temp.al_id('old_room'),'Old room','Fixture building',pg_temp.al_id('category'),
  'Fixture category','Unfinished work','Fixture description','awaiting_rework',pg_temp.al_id('technician'));

do $$ declare v_sig text; begin
  foreach v_sig in array array['public.admin_change_account_status(uuid,public.account_status,text,text,uuid)',
    'public.admin_prepare_password_reset(uuid,public.account_status)','public.admin_cancel_password_reset(uuid)'] loop
    if has_function_privilege('anon',v_sig,'EXECUTE')
      or not has_function_privilege('authenticated',v_sig,'EXECUTE') then
      raise exception 'FAIL: incorrect lifecycle RPC ACL'; end if;
  end loop;
  if has_schema_privilege('authenticated','dormfix_private','USAGE')
    or has_table_privilege('authenticated','dormfix_private.password_reset_requests','SELECT')
    or has_table_privilege('authenticated','dormfix_private.account_session_fences','SELECT')
    or not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
      and policyname='repair_images_current_session' and permissive='RESTRICTIVE') then
    raise exception 'FAIL: private lifecycle state or Storage session fence'; end if;
end $$;
set local role anon;
select pg_temp.al_expect_error('select public.admin_change_account_status(null,''active'',''lock'')','42501');
select pg_temp.al_expect_error('select public.admin_prepare_password_reset(null,''active'')','42501');
reset role;

select pg_temp.al_claims('student','old_session');
set local role authenticated;
select public.dormfix_verify_session();
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''technician''),''active'',''lock'',''reason'')','42501');
select pg_temp.al_expect_error('select public.admin_prepare_password_reset(pg_temp.al_id(''student''),''active'')','42501');
reset role;

select pg_temp.al_claims('admin');
set local role authenticated;
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''admin''),''active'',''lock'',''reason'')',
 'P0002','ACCOUNT_NOT_FOUND');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''student''),''active'',''lock'',chr(9))',
 '22023','ACCOUNT_REASON_REQUIRED');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''student''),''active'',''revoke'')',
 '22023','ACCOUNT_REASON_REQUIRED');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''student''),''active'',''revoke'',repeat(''ế'',501))',
 '22023','ACCOUNT_REASON_TOO_LONG');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''technician''),''active'',''lock'',''reason'')',
 'P0001','ACCOUNT_HAS_OPEN_JOBS');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''technician''),''active'',''revoke'',''reason'')',
 'P0001','ACCOUNT_HAS_OPEN_JOBS');
do $$ declare v_receipt jsonb; begin
  v_receipt:=public.admin_change_account_status(pg_temp.al_id('student'),'active','lock','  Fixture lock reason  ');
  if v_receipt->>'status' is distinct from 'locked' or v_receipt->>'changed' is distinct from 'true'
    or v_receipt->>'room_id' is distinct from pg_temp.al_id('old_room')::text then
    raise exception 'FAIL: student lock receipt'; end if;
end $$;
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''student''),''active'',''revoke'',''reason'')',
 'P0001','ACCOUNT_STATUS_CHANGED');
reset role;
do $$ begin
  if not exists(select 1 from auth.users where id=pg_temp.al_id('student') and banned_until>clock_timestamp())
    or exists(select 1 from auth.sessions where id=pg_temp.al_id('old_session'))
    or not exists(select 1 from public.request_history where entity_type='profile' and entity_id=pg_temp.al_id('student')
      and actor_id=pg_temp.al_id('admin') and action='admin_account_locked' and old_status='active'
      and new_status='locked' and note='Fixture lock reason') then
    raise exception 'FAIL: lock ban, session deletion or audit'; end if;
end $$;
select pg_temp.al_claims('student','old_session');
set local role authenticated;
select pg_temp.al_expect_error('select public.dormfix_verify_session()','28000','ACCOUNT_SESSION_REVOKED');
reset role;

-- A locked Student can still be revoked with unfinished work. Their room
-- remains in history until an active destination is chosen at restoration.
select pg_temp.al_claims('admin');
set local role authenticated;
do $$ declare v_receipt jsonb; begin
  v_receipt:=public.admin_change_account_status(pg_temp.al_id('student'),'locked','revoke','Fixture revoke reason');
  if v_receipt->>'status' is distinct from 'revoked'
    or v_receipt->>'room_id' is distinct from pg_temp.al_id('old_room')::text then
    raise exception 'FAIL: student revoke with unresolved request'; end if;
end $$;
select pg_temp.al_expect_error('select public.admin_prepare_password_reset(pg_temp.al_id(''student''),''revoked'')',
 'P0001','ACCOUNT_STATUS_CHANGED');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''student''),''revoked'',''restore'')',
 '22023','ACTIVE_STUDENT_ROOM_REQUIRED');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''student''),''revoked'',''restore'',null,pg_temp.al_id(''inactive_room''))',
 '22023','ACTIVE_STUDENT_ROOM_REQUIRED');
do $$ declare v_receipt jsonb; begin
  v_receipt:=public.admin_change_account_status(pg_temp.al_id('student'),'revoked','restore',null,pg_temp.al_id('new_room'));
  if v_receipt->>'status' is distinct from 'active' or v_receipt->>'changed' is distinct from 'true'
    or v_receipt->>'room_id' is distinct from pg_temp.al_id('new_room')::text then
    raise exception 'FAIL: student restore receipt'; end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from auth.users where id=pg_temp.al_id('student') and banned_until is not null)
    or not exists(select 1 from public.repair_requests where id=pg_temp.al_id('request')
      and student_id=pg_temp.al_id('student') and room_id=pg_temp.al_id('old_room') and status='awaiting_rework') then
    raise exception 'FAIL: restore did not unban or changed unfinished request history'; end if;
end $$;

-- An older session that appears late cannot use the restored account.
insert into auth.sessions(id,user_id,created_at,updated_at)
values(pg_temp.al_id('late_session'),pg_temp.al_id('student'),now()-interval '1 hour',now()),
  (pg_temp.al_id('reset_session'),pg_temp.al_id('student'),clock_timestamp(),clock_timestamp());
select pg_temp.al_claims('student','old_session');
set local role authenticated;
select pg_temp.al_expect_error('select public.dormfix_verify_session()','28000','ACCOUNT_SESSION_REVOKED');
select pg_temp.al_claims('student','late_session');
select pg_temp.al_expect_error('select public.dormfix_verify_session()','28000','ACCOUNT_SESSION_REVOKED');
select pg_temp.al_claims('student','reset_session');
select public.dormfix_verify_session();
reset role;

-- With terminal work, a Technician can be locked and unlocked. The
-- independent prior Auth ban must survive the unlock.
update public.repair_requests set status='completed',completed_at=clock_timestamp()
where id=pg_temp.al_id('request');
select pg_temp.al_claims('admin');
set local role authenticated;
select public.admin_change_account_status(pg_temp.al_id('technician'),'active','lock','Fixture tech lock');
select public.admin_change_account_status(pg_temp.al_id('technician'),'locked','unlock');
select set_config('dormfix.test.reset_nonce',
  public.admin_prepare_password_reset(pg_temp.al_id('student'),'active')->>'reset_id',true);
select pg_temp.al_expect_error('select public.admin_prepare_password_reset(pg_temp.al_id(''student''),''active'')',
 'P0001','ACCOUNT_RESET_IN_PROGRESS');
select pg_temp.al_expect_error('select public.admin_change_account_status(pg_temp.al_id(''student''),''active'',''lock'',''reason'')',
 'P0001','ACCOUNT_RESET_IN_PROGRESS');
select pg_temp.al_claims('other_admin');
do $$ begin
  if public.admin_cancel_password_reset(current_setting('dormfix.test.reset_nonce')::uuid) then
    raise exception 'FAIL: wrong Admin can cancel a password reset'; end if;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from auth.users where id=pg_temp.al_id('technician')
    and banned_until=now()+interval '4 days') then
    raise exception 'FAIL: independent Auth ban was lost'; end if;
end $$;

-- GoTrue writes the changed hash and server-owned metadata in one transaction.
-- User metadata and unchanged hash both fail to arm the gate.
update auth.users set raw_user_meta_data=jsonb_build_object(
  'dormfix_password_reset_id',current_setting('dormfix.test.reset_nonce')) where id=pg_temp.al_id('student');
select pg_temp.al_expect_error('update auth.users set raw_app_meta_data=jsonb_build_object(
  ''dormfix_password_reset_id'',current_setting(''dormfix.test.reset_nonce'')) where id=pg_temp.al_id(''student'')',
 '22023','INVALID_PASSWORD_RESET');
do $$ begin
  if not exists(select 1 from public.profiles where id=pg_temp.al_id('student') and not must_change_password)
    or not exists(select 1 from dormfix_private.password_reset_requests where account_id=pg_temp.al_id('student')) then
    raise exception 'FAIL: forged or rejected metadata applied password reset'; end if;
end $$;
update auth.users set encrypted_password='fixture-temporary-hash' where id=pg_temp.al_id('student');
update auth.users set raw_app_meta_data=jsonb_build_object('provider','email',
  'dormfix_password_reset_id',current_setting('dormfix.test.reset_nonce')) where id=pg_temp.al_id('student');
do $$ begin
  if not exists(select 1 from public.profiles where id=pg_temp.al_id('student') and must_change_password)
    or exists(select 1 from dormfix_private.password_reset_requests where account_id=pg_temp.al_id('student'))
    or exists(select 1 from auth.users where id=pg_temp.al_id('student') and raw_app_meta_data ? 'dormfix_password_reset_id')
    or not exists(select 1 from public.request_history where entity_type='profile' and entity_id=pg_temp.al_id('student')
      and actor_id=pg_temp.al_id('admin') and action='admin_account_password_reset' and note is null) then
    raise exception 'FAIL: reset gate, consumed metadata or audit'; end if;
end $$;
select pg_temp.al_claims('student','reset_session');
set local role authenticated;
select pg_temp.al_expect_error('select public.dormfix_verify_session()','28000','ACCOUNT_SESSION_REVOKED');
select pg_temp.al_expect_error('select public.complete_change_password()','28000','ACCOUNT_SESSION_REVOKED');
reset role;

insert into auth.sessions(id,user_id,created_at,updated_at)
values(pg_temp.al_id('new_session'),pg_temp.al_id('student'),clock_timestamp(),clock_timestamp());
select pg_temp.al_claims('student','new_session');
set local role authenticated;
select public.dormfix_verify_session();
select pg_temp.al_expect_error('select public.complete_change_password()','P0001','PASSWORD_CHANGE_NOT_VERIFIED');
reset role;
update auth.users set encrypted_password='fixture-chosen-hash' where id=pg_temp.al_id('student');
set local role authenticated;
do $$ declare v_profile jsonb; begin
  v_profile:=public.complete_change_password();
  if v_profile->>'can_access' is distinct from 'true' or v_profile->>'must_change_password' is distinct from 'false'
    or v_profile->'room'->>'id' is distinct from pg_temp.al_id('new_room')::text then
    raise exception 'FAIL: verified password change did not unlock business access'; end if;
end $$;
reset role;

do $$ begin
  if exists(select 1 from dormfix_private.initial_password_gates where account_id=pg_temp.al_id('student'))
    or (select count(*) from public.request_history where entity_type='profile'
      and entity_id in (pg_temp.al_id('student'),pg_temp.al_id('technician'))
      and actor_id=pg_temp.al_id('admin') and action like 'admin_account_%')<>6 then
    raise exception 'FAIL: unconsumed gate or extra audit entries'; end if;
end $$;

rollback;
select 'PASS: account lifecycle, Auth session fencing and verified password reset' as result;
