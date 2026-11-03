-- Run as database owner after migration 014. Synthetic Auth users have no
-- passwords or sessions. Role/JWT simulation is not an HTTP login test.
-- Every fixture and mutation is rolled back; existing business rows are untouched.
begin;

create temporary table student_notification_context (
  key text primary key, id uuid not null default gen_random_uuid()
) on commit drop;
insert into student_notification_context(key) values
 ('a'),('b'),('empty'),('admin'),('technician'),('missing'),('room'),('category'),
 ('request_a'),('request_b'),('single'),('all_one'),('all_two'),('already_read'),
 ('foreign_student'),('foreign_technician'),('unknown');
grant select on student_notification_context to authenticated, anon;
create function pg_temp.sn_id(p_key text) returns uuid language sql stable as $$
 select id from student_notification_context where key = p_key;
$$;
create function pg_temp.sn_expect_error(p_sql text, p_state text, p_message text default null)
returns void language plpgsql as $$
declare v_state text; v_message text;
begin
 begin execute p_sql;
 exception when others then
   get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
   if v_state <> p_state or (p_message is not null and v_message <> p_message) then
     raise exception 'FAIL: expected % %, got % %', p_state, p_message, v_state, v_message;
   end if;
   return;
 end;
 raise exception 'FAIL: expected error % %', p_state, p_message;
end $$;
do $$ begin
 execute format('grant usage on schema %I to authenticated, anon',
   (select nspname from pg_namespace where oid = pg_my_temp_schema()));
end $$;
grant execute on function pg_temp.sn_id(text), pg_temp.sn_expect_error(text,text,text)
 to authenticated, anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text || '@student-notification-test.invalid',
 now(),now(),now()
from student_notification_context where key in ('a','b','empty','admin','technician');
insert into public.rooms(id,code,building)
values(pg_temp.sn_id('room'),'SN-' || pg_temp.sn_id('room')::text,'Fixture building');
insert into public.incident_categories(id,name)
values(pg_temp.sn_id('category'),'SN-' || pg_temp.sn_id('category')::text);
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'SN-' || id::text,'Notification ' || key,
 id::text || '@student-notification-test.invalid','0900000000',
 case key when 'admin' then 'admin'::public.app_role
   when 'technician' then 'technician'::public.app_role else 'student'::public.app_role end,
 case when key in ('a','b','empty') then pg_temp.sn_id('room') end,false
from student_notification_context where key in ('a','b','empty','admin','technician');
insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description)
select id,pg_temp.sn_id(case key when 'request_a' then 'a' else 'b' end),
 pg_temp.sn_id('room'),'Fixture room','Fixture building',pg_temp.sn_id('category'),
 'Fixture category','Fixture title','Fixture description'
from student_notification_context where key in ('request_a','request_b');
insert into public.notifications(id,recipient_id,request_id,event_type,message,read_at)
select id,
 case key when 'foreign_student' then pg_temp.sn_id('b')
   when 'foreign_technician' then pg_temp.sn_id('technician') else pg_temp.sn_id('a') end,
 pg_temp.sn_id(case key when 'foreign_student' then 'request_b' else 'request_a' end),
 'repair_reported','Generic fixture event',
 case when key = 'already_read' then '2026-01-01T00:00:00Z'::timestamptz end
from student_notification_context
where key in ('single','all_one','all_two','already_read','foreign_student','foreign_technician');
create temporary table student_notification_snapshot on commit drop as
select n.id,to_jsonb(n) - 'read_at' as content,n.read_at
from public.notifications n
where n.id in (select id from student_notification_context);
grant select on student_notification_snapshot to authenticated;

-- Only the public guarded RPCs are exposed; neither helper nor table writes are granted.
do $$ declare v_name text; begin
 foreach v_name in array array[
   'public.student_mark_notification_read(uuid)',
   'public.student_mark_all_notifications_read()'
 ] loop
   if has_function_privilege('anon',v_name,'EXECUTE')
      or not has_function_privilege('authenticated',v_name,'EXECUTE') then
     raise exception 'FAIL: incorrect public RPC ACL';
   end if;
 end loop;
 if has_function_privilege('authenticated','public._student_notification_actor()','EXECUTE')
    or has_function_privilege('anon','public._student_notification_actor()','EXECUTE')
    or has_table_privilege('authenticated','public.notifications','UPDATE')
    or has_column_privilege('authenticated','public.notifications','read_at','UPDATE')
    or exists(select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in (
        '_student_notification_actor','student_mark_notification_read','student_mark_all_notifications_read')
      and (not p.prosecdef or not ('search_path=""' = any(p.proconfig)))) then
   raise exception 'FAIL: helper/table privilege or unpinned search_path';
 end if;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.sn_expect_error('select public.student_mark_notification_read(null)','42501');
select pg_temp.sn_expect_error('select public.student_mark_all_notifications_read()','42501');
reset role;
set local role authenticated;
select pg_temp.sn_expect_error('select public.student_mark_notification_read(null)','28000','AUTH_REQUIRED');
select pg_temp.sn_expect_error('select public.student_mark_all_notifications_read()','28000','AUTH_REQUIRED');
select pg_temp.sn_expect_error('select public._student_notification_actor()','42501');
reset role;

-- Wrong roles, missing profiles, blocked/revoked users and temporary-password users cannot mutate.
do $$ declare v_key text; begin
 foreach v_key in array array['admin','technician','missing'] loop
   perform set_config('request.jwt.claim.sub',pg_temp.sn_id(v_key)::text,true);
   set local role authenticated;
   perform pg_temp.sn_expect_error('select public.student_mark_notification_read(pg_temp.sn_id(''single''))',
     '42501','STUDENT_ACCESS_DENIED');
   perform pg_temp.sn_expect_error('select public.student_mark_all_notifications_read()',
     '42501','STUDENT_ACCESS_DENIED');
   reset role;
 end loop;
end $$;
do $$ declare v_status public.account_status; begin
 foreach v_status in array array['locked'::public.account_status,'revoked'::public.account_status] loop
   update public.profiles set status = v_status where id = pg_temp.sn_id('a');
   perform set_config('request.jwt.claim.sub',pg_temp.sn_id('a')::text,true);
   set local role authenticated;
   perform pg_temp.sn_expect_error('select public.student_mark_notification_read(pg_temp.sn_id(''single''))',
     '42501','STUDENT_ACCESS_DENIED');
   perform pg_temp.sn_expect_error('select public.student_mark_all_notifications_read()',
     '42501','STUDENT_ACCESS_DENIED');
   reset role;
 end loop;
 update public.profiles set status = 'active',must_change_password = true where id = pg_temp.sn_id('a');
 set local role authenticated;
 perform pg_temp.sn_expect_error('select public.student_mark_notification_read(pg_temp.sn_id(''single''))',
   '42501','STUDENT_ACCESS_DENIED');
 perform pg_temp.sn_expect_error('select public.student_mark_all_notifications_read()',
   '42501','STUDENT_ACCESS_DENIED');
 reset role;
 update public.profiles set must_change_password = false where id = pg_temp.sn_id('a');
 if exists(select 1 from public.notifications n join student_notification_snapshot s on s.id = n.id
   where n.read_at is distinct from s.read_at) then
   raise exception 'FAIL: denied operation changed read state';
 end if;
end $$;

select set_config('request.jwt.claim.sub',pg_temp.sn_id('a')::text,true);
set local role authenticated;
do $$ declare v_key text; v_receipt jsonb; v_again jsonb; v_before timestamptz; begin
 if (select count(*) from public.notifications where id in (select id from student_notification_context)) <> 4
   or exists(select 1 from public.notifications where recipient_id <> auth.uid()) then
   raise exception 'FAIL: select/count recipient isolation';
 end if;
 foreach v_key in array array['foreign_student','foreign_technician','unknown'] loop
   perform pg_temp.sn_expect_error(format('select public.student_mark_notification_read(%L)',pg_temp.sn_id(v_key)),
     'P0002','NOTIFICATION_NOT_FOUND');
 end loop;
 perform pg_temp.sn_expect_error('select public.student_mark_notification_read(null)',
   'P0002','NOTIFICATION_NOT_FOUND');
 v_before := clock_timestamp();
 v_receipt := public.student_mark_notification_read(pg_temp.sn_id('single'));
 v_again := public.student_mark_notification_read(pg_temp.sn_id('single'));
 if v_receipt <> v_again or (select count(*) from jsonb_object_keys(v_receipt)) <> 2
   or v_receipt->>'id' <> pg_temp.sn_id('single')::text or v_receipt->>'read_at' is null
   or (v_receipt->>'read_at')::timestamptz < v_before
   or (v_receipt->>'read_at')::timestamptz > clock_timestamp()
   or (select read_at from public.notifications where id = pg_temp.sn_id('single'))
      <> (v_receipt->>'read_at')::timestamptz then
   raise exception 'FAIL: single server timestamp/idempotent receipt';
 end if;
 v_receipt := public.student_mark_all_notifications_read();
 if (select count(*) from jsonb_object_keys(v_receipt)) <> 2
   or (v_receipt->>'updated_count')::bigint <> 2 or v_receipt->>'read_at' is null
   or exists(select 1 from public.notifications
     where id in (pg_temp.sn_id('all_one'),pg_temp.sn_id('all_two'))
       and read_at is distinct from (v_receipt->>'read_at')::timestamptz)
   or (select read_at from public.notifications where id = pg_temp.sn_id('single'))
      <> (v_again->>'read_at')::timestamptz
   or (select read_at from public.notifications where id = pg_temp.sn_id('already_read'))
      <> '2026-01-01T00:00:00Z'::timestamptz then
   raise exception 'FAIL: mark-all count/time or existing read timestamps changed';
 end if;
 if (public.student_mark_all_notifications_read()->>'updated_count')::bigint <> 0
   or exists(select 1 from public.notifications where read_at is null) then
   raise exception 'FAIL: repeat mark-all changed already read notifications';
 end if;
 perform pg_temp.sn_expect_error('update public.notifications set read_at = now()','42501');
 perform pg_temp.sn_expect_error('update public.notifications set message = ''Forged''','42501');
 perform pg_temp.sn_expect_error('delete from public.notifications','42501');
 perform pg_temp.sn_expect_error('insert into public.notifications(recipient_id,request_id,event_type,message) values(auth.uid(),pg_temp.sn_id(''request_a''),''completed'',''Forged'')','42501');
end $$;
reset role;

-- No mutation can change another recipient or any event content.
do $$ begin
 if exists(select 1 from public.notifications n join student_notification_snapshot s on s.id = n.id
   where to_jsonb(n) - 'read_at' <> s.content)
   or exists(select 1 from public.notifications
     where id in (pg_temp.sn_id('foreign_student'),pg_temp.sn_id('foreign_technician'))
       and read_at is not null) then
   raise exception 'FAIL: foreign state or immutable content changed';
 end if;
end $$;

select set_config('request.jwt.claim.sub',pg_temp.sn_id('b')::text,true);
set local role authenticated;
select pg_temp.sn_expect_error('select public.student_mark_notification_read(pg_temp.sn_id(''single''))',
 'P0002','NOTIFICATION_NOT_FOUND');
do $$ begin
 if (public.student_mark_all_notifications_read()->>'updated_count')::bigint <> 1 then
   raise exception 'FAIL: account B could not mark only its own notification';
 end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.sn_id('empty')::text,true);
set local role authenticated;
do $$ declare v_receipt jsonb; begin
 v_receipt := public.student_mark_all_notifications_read();
 if (v_receipt->>'updated_count')::bigint <> 0 or v_receipt->>'read_at' is null then
   raise exception 'FAIL: empty inbox receipt';
 end if;
end $$;
reset role;

rollback;
select 'PASS: DF-017 student notification authorization, isolation, read receipts and idempotency' as result;
