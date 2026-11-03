-- Run as SQL Editor/database owner after migration 013. Synthetic Auth users
-- have no passwords or sessions; all fixture rows and events are rolled back.
-- This checks database authorization, not HTTP login or real Flutter navigation.
begin;

create temporary table technician_tracking_context (
  key text primary key, id uuid not null default gen_random_uuid()
) on commit drop;
insert into technician_tracking_context(key) values
 ('admin'),('student'),('a'),('b'),('missing'),('room'),('category'),
 ('r_transfer'),('r_cancel'),('r_complete'),('r_current_cancelled'),('r_student_complete'),
 ('r_rework'),('r_admin_complete'),('r_other');
grant select on technician_tracking_context to authenticated, anon;
create function pg_temp.tt_id(p_key text) returns uuid language sql stable as $$
 select id from technician_tracking_context where key=p_key;
$$;
create function pg_temp.tt_expect_error(p_sql text,p_state text,p_message text default null)
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
 raise exception 'FAIL: expected error % %',p_state,p_message;
end $$;
do $$ begin
 execute format('grant usage on schema %I to authenticated, anon',
   (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;
grant execute on function pg_temp.tt_id(text),pg_temp.tt_expect_error(text,text,text) to authenticated, anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text || '@technician-tracking-test.invalid',now(),now(),now()
from technician_tracking_context where key in ('admin','student','a','b');
insert into public.rooms(id,code,building)
values(pg_temp.tt_id('room'),'TT-' || pg_temp.tt_id('room')::text,'Fixture building');
insert into public.incident_categories(id,name)
values(pg_temp.tt_id('category'),'TT-' || pg_temp.tt_id('category')::text);
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'TT-' || id::text,'Tracking ' || key,id::text || '@technician-tracking-test.invalid','0900000000',
 case key when 'admin' then 'admin'::public.app_role when 'student' then 'student'::public.app_role
   else 'technician'::public.app_role end,
 case when key='student' then pg_temp.tt_id('room') end,false
from technician_tracking_context where key in ('admin','student','a','b');

select set_config('request.jwt.claim.sub',pg_temp.tt_id('a')::text,true);
set local role authenticated;
do $$ begin
 if public.technician_list_work_history()<>'[]'::jsonb
   or public.technician_list_notifications()<>'[]'::jsonb then raise exception 'FAIL: empty arrays'; end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.tt_expect_error('select public.technician_list_work_history()','42501');
select pg_temp.tt_expect_error('select public.technician_list_notifications()','42501');
select pg_temp.tt_expect_error('select public.technician_mark_notification_read(null)','42501');
reset role;
set local role authenticated;
select pg_temp.tt_expect_error('select public.technician_list_work_history()','28000','AUTH_REQUIRED');
select pg_temp.tt_expect_error('select public.technician_list_notifications()','28000','AUTH_REQUIRED');
select pg_temp.tt_expect_error('select public.technician_mark_notification_read(null)','28000','AUTH_REQUIRED');
reset role;
do $$ declare v_key text; begin
 foreach v_key in array array['admin','student','missing'] loop
   perform set_config('request.jwt.claim.sub',pg_temp.tt_id(v_key)::text,true);
   set local role authenticated;
   perform pg_temp.tt_expect_error('select public.technician_list_work_history()','42501','TECHNICIAN_ACCESS_DENIED');
   perform pg_temp.tt_expect_error('select public.technician_list_notifications()','42501','TECHNICIAN_ACCESS_DENIED');
   perform pg_temp.tt_expect_error('select public.technician_mark_notification_read(null)','42501','TECHNICIAN_ACCESS_DENIED');
   reset role;
 end loop;
end $$;
do $$ declare v_status public.account_status; begin
 foreach v_status in array array['locked'::public.account_status,'revoked'::public.account_status] loop
   update public.profiles set status=v_status where id=pg_temp.tt_id('a');
   perform set_config('request.jwt.claim.sub',pg_temp.tt_id('a')::text,true);
   set local role authenticated;
   perform pg_temp.tt_expect_error('select public.technician_list_work_history()','42501','TECHNICIAN_ACCESS_DENIED');
   perform pg_temp.tt_expect_error('select public.technician_list_notifications()','42501','TECHNICIAN_ACCESS_DENIED');
   perform pg_temp.tt_expect_error('select public.technician_mark_notification_read(null)','42501','TECHNICIAN_ACCESS_DENIED');
   reset role;
 end loop;
 update public.profiles set status='active',must_change_password=true where id=pg_temp.tt_id('a');
 set local role authenticated;
 perform pg_temp.tt_expect_error('select public.technician_list_work_history()','42501','TECHNICIAN_ACCESS_DENIED');
 perform pg_temp.tt_expect_error('select public.technician_list_notifications()','42501','TECHNICIAN_ACCESS_DENIED');
 perform pg_temp.tt_expect_error('select public.technician_mark_notification_read(null)','42501','TECHNICIAN_ACCESS_DENIED');
 reset role;
 update public.profiles set must_change_password=false where id=pg_temp.tt_id('a');
end $$;

insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id)
select id,pg_temp.tt_id('student'),pg_temp.tt_id('room'),'Original room','Original building',
 pg_temp.tt_id('category'),'Original category','Original ' || key,'Private current request details',
 case key when 'r_transfer' then 'pending'::public.repair_status
   when 'r_complete' then 'completed'::public.repair_status
   when 'r_current_cancelled' then 'cancelled'::public.repair_status
   when 'r_cancel' then 'assigned'::public.repair_status
   when 'r_other' then 'assigned'::public.repair_status
   else 'awaiting_confirmation'::public.repair_status end,
 case key when 'r_transfer' then null when 'r_other' then pg_temp.tt_id('b') else pg_temp.tt_id('a') end
from technician_tracking_context where left(key,2)='r_';
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,
 request_code_snapshot,title_snapshot,room_code_snapshot)
select id,assigned_technician_id,pg_temp.tt_id('admin'),now()-interval '1 day',
 request_code,title,room_code_snapshot from public.repair_requests
where id in (select id from technician_tracking_context where left(key,2)='r_' and key<>'r_transfer');

-- Actual Admin RPCs exercise assignment and transfer notifications in the same transaction.
select set_config('request.jwt.claim.sub',pg_temp.tt_id('admin')::text,true);
set local role authenticated;
select public.admin_assign_request(pg_temp.tt_id('r_transfer'),pg_temp.tt_id('a'));
select public.admin_transfer_request(pg_temp.tt_id('r_transfer'),pg_temp.tt_id('b'),'Fixture transfer');
reset role;
insert into technician_tracking_context(key,id)
select 'foreign_notification',id from public.notifications
where recipient_id=pg_temp.tt_id('b') and request_id=pg_temp.tt_id('r_transfer') limit 1;
do $$ begin
 if pg_temp.tt_id('foreign_notification') is null
   or (select count(*) from public.notifications where recipient_id=pg_temp.tt_id('b')
     and request_id=pg_temp.tt_id('r_transfer') and event_type='transferred_in')<>1 then
   raise exception 'FAIL: transfer recipient notification missing';
 end if;
end $$;
update public.repair_requests set title='Later private title',room_code_snapshot='Later private room',
 description='Later private description' where id=pg_temp.tt_id('r_transfer');

select set_config('request.jwt.claim.sub',pg_temp.tt_id('a')::text,true);
set local role authenticated;
do $$ declare v_rows jsonb; v_old jsonb; v_notification jsonb; v_receipt jsonb; v_again jsonb; begin
 v_rows:=public.technician_list_work_history();
 if jsonb_array_length(v_rows)<>7 then raise exception 'FAIL: own assignment history isolation'; end if;
 select value into v_old from jsonb_array_elements(v_rows)
 where value->>'title'='Original r_transfer';
 if v_old is null or v_old->>'room_code'<>'Original room'
   or v_old->'request_id'<>'null'::jsonb or v_old->'status'<>'null'::jsonb
   or v_old->'can_open_detail'<>'false'::jsonb or v_old->'ended_at'='null'::jsonb
   or (select count(*) from jsonb_object_keys(v_old))<>9
   or v_old::text like '%Later private%' or v_old ? 'description' then
   raise exception 'FAIL: former summary leaked current data or detail permission';
 end if;
 if v_rows->0->>'title'<>'Original r_transfer' then raise exception 'FAIL: newest assignment first'; end if;
 perform pg_temp.tt_expect_error('select public.technician_get_job(pg_temp.tt_id(''r_transfer''))','P0002','JOB_NOT_FOUND');
 if (public.technician_get_job(pg_temp.tt_id('r_complete'))->'workflow'->>'blocked_reason') is distinct from 'READ_ONLY'
   or (public.technician_get_job(pg_temp.tt_id('r_current_cancelled'))->'workflow'->>'blocked_reason') is distinct from 'READ_ONLY' then
   raise exception 'FAIL: current completed/cancelled history detail not read-only'; end if;
 v_rows:=public.technician_list_notifications();
 if jsonb_array_length(v_rows)<>2 then raise exception 'FAIL: own assignment/transfer notification count'; end if;
 if exists(select 1 from jsonb_array_elements(v_rows) n
   where n->'request_id'<>'null'::jsonb or n->'can_open_detail'<>'false'::jsonb
     or n::text like '%Later private%') then raise exception 'FAIL: stale notification detail eligibility/data'; end if;
 select value into v_notification from jsonb_array_elements(v_rows) where value->>'event_type'='assigned';
 v_receipt:=public.technician_mark_notification_read((v_notification->>'id')::uuid);
 v_again:=public.technician_mark_notification_read((v_notification->>'id')::uuid);
 if v_receipt<>v_again or v_receipt->>'id'<>v_notification->>'id'
   or v_receipt->'read_at'='null'::jsonb then raise exception 'FAIL: idempotent mark read'; end if;
 perform pg_temp.tt_expect_error('update public.notifications set message=''Forged''','42501');
 perform pg_temp.tt_expect_error('update public.notifications set read_at=now()','42501');
 perform pg_temp.tt_expect_error('insert into public.notifications(recipient_id,request_id,event_type,message) values(auth.uid(),pg_temp.tt_id(''r_cancel''),''completed'',''Forged'')','42501');
end $$;
reset role;

-- A cannot mark B's notification; replaying a no-op request update emits nothing.
set local role authenticated;
do $$ begin
 perform pg_temp.tt_expect_error(format('select public.technician_mark_notification_read(%L)',pg_temp.tt_id('foreign_notification')),
   'P0002','NOTIFICATION_NOT_FOUND');
end $$;
reset role;
do $$ declare v_before bigint; begin
 select count(*) into v_before from public.notifications where request_id=pg_temp.tt_id('r_transfer');
 update public.repair_requests set status=status,assigned_technician_id=assigned_technician_id
   where id=pg_temp.tt_id('r_transfer');
 if (select count(*) from public.notifications where request_id=pg_temp.tt_id('r_transfer'))<>v_before then
   raise exception 'FAIL: duplicate event for no-op update'; end if;
 begin
   update public.repair_requests set assigned_technician_id=pg_temp.tt_id('a') where id=pg_temp.tt_id('r_transfer');
   raise exception using errcode='P0001',message='ROLLBACK_FIXTURE';
 exception when raise_exception then
   if sqlerrm<>'ROLLBACK_FIXTURE' then raise; end if;
 end;
 if (select count(*) from public.notifications where request_id=pg_temp.tt_id('r_transfer'))<>v_before then
   raise exception 'FAIL: event escaped rolled-back source transaction'; end if;
end $$;

-- Owner fixtures simulate Student events whose backend belongs to another role.
-- Clearing assignment during cancellation must produce one cancellation, not transfer-out too.
update public.repair_requests set status='cancelled',assigned_technician_id=null where id=pg_temp.tt_id('r_cancel');
update public.repair_requests set status='awaiting_rework' where id=pg_temp.tt_id('r_rework');
update public.repair_requests set status='completed' where id=pg_temp.tt_id('r_student_complete');
update public.profiles set status='revoked' where id=pg_temp.tt_id('student');
select set_config('request.jwt.claim.sub',pg_temp.tt_id('admin')::text,true);
set local role authenticated;
select public.admin_confirm_revoked_student_request(pg_temp.tt_id('r_admin_complete'),'Fixture Admin confirmation');
reset role;
do $$ begin
 if (select count(*) from public.notifications where request_id=pg_temp.tt_id('r_cancel') and event_type='cancelled')<>1
   or exists(select 1 from public.notifications where request_id=pg_temp.tt_id('r_cancel') and event_type='transferred_out')
   or (select count(*) from public.notifications where request_id=pg_temp.tt_id('r_rework') and event_type='rework_requested')<>1
   or (select count(*) from public.notifications where request_id=pg_temp.tt_id('r_student_complete') and event_type='completed')<>1
   or (select count(*) from public.notifications where request_id=pg_temp.tt_id('r_admin_complete') and event_type='completed')<>1
   or exists(select 1 from public.notifications where recipient_id=pg_temp.tt_id('b') and read_at is not null) then
   raise exception 'FAIL: cancellation/rework/Admin-completion events or foreign read state'; end if;
end $$;

-- Returning to A does not expand the old A assignment; each assignment stays separate.
select set_config('request.jwt.claim.sub',pg_temp.tt_id('admin')::text,true);
set local role authenticated;
select public.admin_transfer_request(pg_temp.tt_id('r_transfer'),pg_temp.tt_id('a'),'Fixture B to A');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.tt_id('a')::text,true);
set local role authenticated;
do $$ declare v_rows jsonb; begin
 v_rows:=public.technician_list_work_history();
 if (select count(*) from jsonb_array_elements(v_rows) h where h->>'title'='Original r_transfer'
   and h->'can_open_detail'='false'::jsonb and h->'request_id'='null'::jsonb)<>1
   or (select count(*) from jsonb_array_elements(v_rows) h where h->>'title'='Later private title'
     and h->'can_open_detail'='true'::jsonb and h->>'request_id'=pg_temp.tt_id('r_transfer')::text)<>1 then
   raise exception 'FAIL: A to B to A reused old assignment access or lost new assignment'; end if;
 if not exists(select 1 from jsonb_array_elements(public.technician_list_notifications()) n
   where n->>'event_type'='transferred_in' and n->'can_open_detail'='true'::jsonb
     and n->>'request_id'=pg_temp.tt_id('r_transfer')::text) then
   raise exception 'FAIL: current notification cannot open authorized detail'; end if;
end $$;
reset role;

rollback;
select 'PASS: own technician history snapshots, A-to-B-to-A permissions, notification events/atomicity/isolation, idempotent read state and account/role/ACL gates; all fixtures rolled back' as result;
