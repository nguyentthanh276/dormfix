-- DF-039–042 / DF-049–050. All users and catalog fixtures are synthetic.
begin;

create temporary table admin_catalog_fixture (
  key text primary key, id uuid not null default gen_random_uuid()
) on commit drop;
insert into admin_catalog_fixture(key) values
 ('admin'),('student'),('locked_student'),('revoked_student'),
 ('occupied'),('locked_room'),('revoked_room'),('new_room'),
 ('category'),('request'),('inactive_attempt'),('missing');
grant select, update on admin_catalog_fixture to authenticated;
do $$ begin
  execute format('grant usage on schema %I to authenticated',
    (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;

create function pg_temp.ac_id(p_key text) returns uuid language sql stable as $$
  select id from admin_catalog_fixture where key=p_key;
$$;
create function pg_temp.ac_expect_error(p_sql text,p_state text,p_message text default null)
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
grant execute on function pg_temp.ac_id(text),pg_temp.ac_expect_error(text,text,text) to authenticated;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text||'@admin-catalog.invalid',now(),now(),now()
from admin_catalog_fixture where key in ('admin','student','locked_student','revoked_student');
insert into public.rooms(id,code,building)
select id,'CAT-'||id::text,'Fixture building' from admin_catalog_fixture
where key in ('occupied','locked_room','revoked_room');
insert into public.profiles(id,identity_code,full_name,email,phone,role,status,room_id,must_change_password)
select id,'CAT-'||id::text,key,id::text||'@admin-catalog.invalid','0900000000',
  (case when key='admin' then 'admin' else 'student' end)::public.app_role,
  (case key when 'locked_student' then 'locked' when 'revoked_student' then 'revoked' else 'active' end)::public.account_status,
  case key when 'student' then pg_temp.ac_id('occupied')
    when 'locked_student' then pg_temp.ac_id('locked_room')
    when 'revoked_student' then pg_temp.ac_id('revoked_room') end,false
from admin_catalog_fixture where key in ('admin','student','locked_student','revoked_student');

do $$ begin
  if has_function_privilege('anon','public.admin_list_rooms()','EXECUTE')
     or has_function_privilege('authenticated','public._admin_room_summary(public.rooms)','EXECUTE')
     or has_function_privilege('authenticated','public._admin_write_room(text,uuid,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public._admin_incident_category_summary(public.incident_categories)','EXECUTE')
     or has_function_privilege('authenticated','public._admin_write_incident_category(text,uuid,text,boolean)','EXECUTE')
     or has_table_privilege('authenticated','public.rooms','INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','public.incident_categories','INSERT,UPDATE,DELETE') then
    raise exception 'FAIL: catalog helper exposure or direct table writes';
  end if;
end $$;

select set_config('request.jwt.claim.sub',pg_temp.ac_id('admin')::text,true);
set local role authenticated;
do $$ declare v_list jsonb; v_row jsonb; v_code text:='NEW-'||pg_temp.ac_id('occupied')::text;
  v_name text:='Category '||pg_temp.ac_id('occupied')::text; v_id uuid;
begin
  v_list:=public.admin_list_rooms();
  if not exists(select 1 from jsonb_array_elements(v_list) as row
      where row->>'id'=pg_temp.ac_id('occupied')::text and row->>'student_count'='1'
        and row->'profiles'='[{"full_name":"student"}]'::jsonb)
    or not exists(select 1 from jsonb_array_elements(v_list) as row
      where row->>'id'=pg_temp.ac_id('locked_room')::text and row->>'student_count'='1'
        and row->'profiles'='[{"full_name":"locked_student"}]'::jsonb)
    or not exists(select 1 from jsonb_array_elements(v_list) as row
      where row->>'id'=pg_temp.ac_id('revoked_room')::text and row->>'student_count'='0'
        and row->'profiles'='[]'::jsonb) then
    raise exception 'FAIL: room list occupancy contract';
  end if;
  perform pg_temp.ac_expect_error('select public.admin_create_room(E''\t\n'', ''A'')','22023','INVALID_ROOM_INPUT');
  perform pg_temp.ac_expect_error('select public.admin_create_incident_category(E''\t\n'')','22023','INVALID_CATEGORY_INPUT');
  perform pg_temp.ac_expect_error('select public.admin_deactivate_room(pg_temp.ac_id(''occupied''))','P0001','ROOM_HAS_STUDENTS');
  perform pg_temp.ac_expect_error('select public.admin_deactivate_room(pg_temp.ac_id(''locked_room''))','P0001','ROOM_HAS_STUDENTS');
  perform pg_temp.ac_expect_error('select public.admin_update_room(pg_temp.ac_id(''missing''),''B'',''A'')','P0002','ROOM_NOT_FOUND');
  perform pg_temp.ac_expect_error('select public.admin_rename_incident_category(pg_temp.ac_id(''missing''),''X'')','P0002','CATEGORY_NOT_FOUND');

  v_row:=public.admin_deactivate_room(pg_temp.ac_id('revoked_room'));
  if v_row->>'changed' is distinct from 'true' or v_row->>'is_active' is distinct from 'false' then
    raise exception 'FAIL: revoked occupant should not block deactivation';
  end if;
  v_row:=public.admin_create_room('  '||v_code||'  ','  Tòa A  ');
  v_id:=(v_row->>'id')::uuid;
  update admin_catalog_fixture set id=v_id where key='new_room';
  if v_row->>'code' is distinct from v_code or v_row->>'building' is distinct from 'Tòa A'
     or v_row->>'changed' is distinct from 'true' or v_row->>'student_count' is distinct from '0' then
    raise exception 'FAIL: room create receipt';
  end if;
  perform pg_temp.ac_expect_error(format('select public.admin_create_room(%L,''B'')',lower(v_code)),
    '23505','ROOM_CODE_ALREADY_EXISTS');
  v_row:=public.admin_update_room(v_id,v_code||'-B','Tòa B');
  if v_row->>'changed' is distinct from 'true' or v_row->>'building' is distinct from 'Tòa B' then
    raise exception 'FAIL: room update receipt';
  end if;
  v_row:=public.admin_update_room(v_id,v_code||'-B','Tòa B');
  if v_row->>'changed' is distinct from 'false' then raise exception 'FAIL: room update replay'; end if;
  v_row:=public.admin_deactivate_room(v_id);
  if v_row->>'changed' is distinct from 'true' or v_row->>'is_active' is distinct from 'false' then
    raise exception 'FAIL: room deactivate receipt';
  end if;
  v_row:=public.admin_deactivate_room(v_id);
  if v_row->>'changed' is distinct from 'false' then raise exception 'FAIL: room deactivation replay'; end if;

  v_row:=public.admin_create_incident_category('  '||v_name||'  ');
  v_id:=(v_row->>'id')::uuid;
  update admin_catalog_fixture set id=v_id where key='category';
  if v_row->>'name' is distinct from v_name or v_row->>'is_active' is distinct from 'true'
     or v_row->>'changed' is distinct from 'true' or v_row->>'created_at' is null then
    raise exception 'FAIL: category create receipt';
  end if;
  perform pg_temp.ac_expect_error(format('select public.admin_create_incident_category(%L)',lower(v_name)),
    '23505','CATEGORY_NAME_ALREADY_EXISTS');
  if not exists(select 1 from jsonb_array_elements(public.admin_list_incident_categories()) as row
    where row->>'id'=v_id::text and row->>'name'=v_name) then raise exception 'FAIL: category list'; end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.ac_id('student')::text,true);
set local role authenticated;
do $$ begin
  perform pg_temp.ac_expect_error('select public.admin_list_rooms()','42501');
  perform pg_temp.ac_expect_error('select public.admin_list_incident_categories()','42501');
  perform pg_temp.ac_expect_error('select public.admin_create_room(''Deny'',''A'')','42501');
  perform pg_temp.ac_expect_error('select public.admin_set_incident_category_active(pg_temp.ac_id(''category''),false)','42501');
  if not exists(select 1 from jsonb_array_elements(public.student_list_categories()) as row
    where row->>'id'=pg_temp.ac_id('category')::text) then raise exception 'FAIL: student cannot select active category'; end if;
  perform public.student_create_request(pg_temp.ac_id('request'),'Catalog test request',
    pg_temp.ac_id('category'),'Catalog snapshot test');
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.ac_id('admin')::text,true);
set local role authenticated;
do $$ declare v_row jsonb; begin
  perform public.admin_update_room(pg_temp.ac_id('occupied'),'RENAMED-'||pg_temp.ac_id('occupied')::text,'Tòa mới');
  perform public.admin_rename_incident_category(pg_temp.ac_id('category'),'Renamed '||pg_temp.ac_id('category')::text);
  v_row:=public.admin_rename_incident_category(pg_temp.ac_id('category'),'Renamed '||pg_temp.ac_id('category')::text);
  if v_row->>'changed' is distinct from 'false' then raise exception 'FAIL: category rename replay'; end if;
  v_row:=public.admin_set_incident_category_active(pg_temp.ac_id('category'),false);
  if v_row->>'changed' is distinct from 'true' or v_row->>'is_active' is distinct from 'false' then
    raise exception 'FAIL: category deactivation receipt';
  end if;
  v_row:=public.admin_set_incident_category_active(pg_temp.ac_id('category'),false);
  if v_row->>'changed' is distinct from 'false' then raise exception 'FAIL: category deactivation replay'; end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.ac_id('student')::text,true);
set local role authenticated;
do $$ declare v_detail jsonb; begin
  if exists(select 1 from jsonb_array_elements(public.student_list_categories()) as row
    where row->>'id'=pg_temp.ac_id('category')::text) then raise exception 'FAIL: inactive category shown'; end if;
  perform pg_temp.ac_expect_error(
    'select public.student_create_request(pg_temp.ac_id(''inactive_attempt''),''Blocked'',pg_temp.ac_id(''category''),''Blocked'')',
    '22023','ACTIVE_CATEGORY_REQUIRED');
  v_detail:=public.student_get_request(pg_temp.ac_id('request'))->'request';
  if v_detail->>'category_name' is distinct from 'Category '||pg_temp.ac_id('occupied')::text
     or v_detail->>'room_code' is distinct from 'CAT-'||pg_temp.ac_id('occupied')::text then
    raise exception 'FAIL: previous request snapshots changed';
  end if;
  if exists(select 1 from public.request_history where entity_type in ('room','category')
    and entity_id in (pg_temp.ac_id('occupied'),pg_temp.ac_id('category'))) then
    raise exception 'FAIL: catalog audit visible to student';
  end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.ac_id('admin')::text,true);
set local role authenticated;
select public.admin_set_incident_category_active(pg_temp.ac_id('category'),true);
reset role;
select set_config('request.jwt.claim.sub',pg_temp.ac_id('student')::text,true);
set local role authenticated;
do $$ begin
  if not exists(select 1 from jsonb_array_elements(public.student_list_categories()) as row
    where row->>'id'=pg_temp.ac_id('category')::text and row->>'name'='Renamed '||pg_temp.ac_id('category')::text) then
    raise exception 'FAIL: reactivated category not selectable with updated name';
  end if;
end $$;
reset role;

do $$ begin
  if (select count(*) from public.request_history where entity_type='room' and entity_id=pg_temp.ac_id('new_room')
       and actor_id=pg_temp.ac_id('admin') and request_id is null)<>3
     or (select count(*) from public.request_history where entity_type='category' and entity_id=pg_temp.ac_id('category')
       and actor_id=pg_temp.ac_id('admin') and request_id is null)<>4
     or not (select is_active from public.rooms where id=pg_temp.ac_id('locked_room'))
     or exists(select 1 from public.repair_requests where id=pg_temp.ac_id('inactive_attempt')) then
    raise exception 'FAIL: catalog audit or forbidden changes';
  end if;
end $$;

rollback;
select 'PASS: Admin catalog, occupancy, authorization, audit, and student picker snapshots' as result;
