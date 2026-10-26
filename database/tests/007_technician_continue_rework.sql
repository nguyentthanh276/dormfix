-- Run as SQL Editor/database owner after 007. Auth users are disposable and
-- passwordless. Storage fixtures are metadata only; no files are uploaded or
-- deleted, and every fixture is rolled back. Do not change demo credentials.
begin;

create temporary table technician_continue_context (key text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into technician_continue_context(key) values
 ('admin'),('student'),('technician'),('other'),('room'),('category'),('missing'),
 ('r_main'),('r_null'),('r_new_assignment'),('r_transfer'),('r_foreign'),
 ('r_transferred'),('r_missing_assignment'),('r_wrong_assignment'),
 ('r_assigned'),('r_progress'),('r_confirmation'),('r_completed'),('r_cancelled'),
 ('old_result'),('old_feedback'),('old_photo'),('feedback_photo'),
 ('result_first'),('result_second'),('photo_first'),('photo_second'),('result_null'),('result_new_assignment');
grant select on technician_continue_context to authenticated, anon;

create function pg_temp.tc_id(p_key text) returns uuid language sql stable as $$
 select id from technician_continue_context where key=p_key;
$$;
create function pg_temp.tc_photo(p_version integer, p_result text, p_photo text) returns jsonb language sql stable as $$
 select jsonb_build_object('id',pg_temp.tc_id(p_photo)::text,
   'storage_path','technician-results/' || pg_temp.tc_id('technician')::text || '/'
     || pg_temp.tc_id('r_main')::text || '/' || p_version::text || '/'
     || pg_temp.tc_id(p_result)::text || '/' || pg_temp.tc_id(p_photo)::text || '.png',
   'mime_type','image/png','size_bytes',128);
$$;
create function pg_temp.tc_expect_error(p_sql text,p_state text,p_message text default null)
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
grant execute on function pg_temp.tc_id(text),pg_temp.tc_photo(integer,text,text),
 pg_temp.tc_expect_error(text,text,text) to authenticated,anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text || '@technician-continue-test.invalid',now(),now(),now()
from technician_continue_context where key in ('admin','student','technician','other');
insert into public.rooms(id,code,building)
 values(pg_temp.tc_id('room'),'TC-' || pg_temp.tc_id('room')::text,'Test building');
insert into public.incident_categories(id,name)
 values(pg_temp.tc_id('category'),'TC-' || pg_temp.tc_id('category')::text);
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'TC-' || id::text,'Test ' || key,id::text || '@technician-continue-test.invalid','0900000000',
 case key when 'admin' then 'admin'::public.app_role when 'student' then 'student'::public.app_role else 'technician'::public.app_role end,
 case when key='student' then pg_temp.tc_id('room') end,false
from technician_continue_context where key in ('admin','student','technician','other');
insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id,version,updated_at)
select id,pg_temp.tc_id('student'),pg_temp.tc_id('room'),'Room snapshot','Building snapshot',
 pg_temp.tc_id('category'),'Category snapshot',key,'Synthetic continuation regression',
 case key when 'r_assigned' then 'assigned'::public.repair_status
   when 'r_progress' then 'in_progress'::public.repair_status
   when 'r_confirmation' then 'awaiting_confirmation'::public.repair_status
   when 'r_completed' then 'completed'::public.repair_status
   when 'r_cancelled' then 'cancelled'::public.repair_status else 'awaiting_rework'::public.repair_status end,
 case when key in ('r_foreign','r_transferred') then pg_temp.tc_id('other') else pg_temp.tc_id('technician') end,
 5,now()-interval '1 day'
from technician_continue_context where left(key,2)='r_';
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,
 started_at,needs_transfer_confirmation,transfer_confirmed_at,request_code_snapshot,title_snapshot,room_code_snapshot)
select r.id,case when c.key='r_wrong_assignment' then pg_temp.tc_id('other') else r.assigned_technician_id end,
 pg_temp.tc_id('admin'),now()-interval '2 days',
 case when c.key not in ('r_null','r_new_assignment','r_transfer') then now()-interval '47 hours' end,
 c.key='r_transfer',case when c.key='r_main' then now()-interval '46 hours' end,
 r.request_code,r.title,r.room_code_snapshot
from public.repair_requests r join technician_continue_context c on c.id=r.id
where left(c.key,2)='r_' and c.key<>'r_missing_assignment';
-- Historical assignment does not authorize the former technician. A newly
-- assigned technician may continue rework only when no transfer confirmation is pending.
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,started_at,
 ended_at,end_reason,request_code_snapshot,title_snapshot,room_code_snapshot)
select r.id,case when c.key='r_transferred' then pg_temp.tc_id('technician') else pg_temp.tc_id('other') end,
 pg_temp.tc_id('admin'),now()-interval '4 days',now()-interval '95 hours',now()-interval '3 days','transferred',
 r.request_code,r.title,r.room_code_snapshot
from public.repair_requests r join technician_continue_context c on c.id=r.id
where c.key in ('r_transferred','r_new_assignment');
insert into public.repair_results(id,request_id,assignment_id,submitted_by,content,submitted_at,request_version)
select pg_temp.tc_id('old_result'),a.request_id,a.id,a.technician_id,'Original immutable repair result',now()-interval '36 hours',3
from public.request_assignments a where a.request_id=pg_temp.tc_id('r_main') and a.ended_at is null;
insert into public.request_feedback(id,request_id,kind,reason,submitted_by,created_at)
values(pg_temp.tc_id('old_feedback'),pg_temp.tc_id('r_main'),'rework','Original rework reason',pg_temp.tc_id('student'),now()-interval '1 day');
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.tc_photo(3,'old_result','old_photo')->>'storage_path',pg_temp.tc_id('technician')::text,'{"size":128,"mimetype":"image/png"}'),
 ('repair-images','continue-test-feedback/' || pg_temp.tc_id('feedback_photo')::text || '.png',pg_temp.tc_id('student')::text,'{"size":128,"mimetype":"image/png"}');
insert into public.request_attachments(id,request_id,result_id,feedback_id,storage_path,mime_type,size_bytes,uploaded_by)
values(pg_temp.tc_id('old_photo'),pg_temp.tc_id('r_main'),pg_temp.tc_id('old_result'),null,
 pg_temp.tc_photo(3,'old_result','old_photo')->>'storage_path','image/png',128,pg_temp.tc_id('technician')),
 (pg_temp.tc_id('feedback_photo'),pg_temp.tc_id('r_main'),null,pg_temp.tc_id('old_feedback'),
 'continue-test-feedback/' || pg_temp.tc_id('feedback_photo')::text || '.png','image/png',128,pg_temp.tc_id('student'));

-- Snapshot exact immutable rows and denied-operation targets as TEST OWNER.
create temporary table technician_continue_before on commit drop as
select 'request'::text as kind,r.id,to_jsonb(r) as data from public.repair_requests r join technician_continue_context c on c.id=r.id
union all select 'assignment',a.id,to_jsonb(a) from public.request_assignments a join technician_continue_context c on c.id=a.request_id
union all select 'result',r.id,to_jsonb(r) from public.repair_results r where r.id=pg_temp.tc_id('old_result')
union all select 'feedback',f.id,to_jsonb(f) from public.request_feedback f where f.id=pg_temp.tc_id('old_feedback')
union all select 'attachment',a.id,to_jsonb(a) from public.request_attachments a where a.request_id=pg_temp.tc_id('r_main')
union all select 'object',o.id,to_jsonb(o) from storage.objects o where o.name in
 (pg_temp.tc_photo(3,'old_result','old_photo')->>'storage_path','continue-test-feedback/' || pg_temp.tc_id('feedback_photo')::text || '.png');

-- RPC/helper ACLs and account gates cannot be bypassed by supplying a request ID.
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.tc_expect_error('select public.technician_continue_job(null,1)','42501');
reset role;
set local role authenticated;
select pg_temp.tc_expect_error('select public.technician_continue_job(null,1)','28000','AUTH_REQUIRED');
select pg_temp.tc_expect_error('select public._technician_workflow_capabilities(null)','42501');
reset role;
do $$ declare v_key text; begin
 foreach v_key in array array['admin','student','missing'] loop
   perform set_config('request.jwt.claim.sub',pg_temp.tc_id(v_key)::text,true);
   if public._technician_workflow_capabilities(pg_temp.tc_id('r_main')) is distinct from
      '{"can_start":false,"can_continue":false,"can_submit_result":false,"blocked_reason":"READ_ONLY"}'::jsonb then
     raise exception 'FAIL: unauthorized capability %',v_key;
   end if;
   set local role authenticated;
   perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_main''),5)','42501','TECHNICIAN_ACCESS_DENIED');
   reset role;
 end loop;
end $$;
select set_config('request.jwt.claim.sub',pg_temp.tc_id('technician')::text,true);
do $$ declare v_state text; begin
 foreach v_state in array array['locked','revoked','password'] loop
   update public.profiles set status=case when v_state='password' then 'active'::public.account_status else v_state::public.account_status end,
    must_change_password=(v_state='password') where id=pg_temp.tc_id('technician');
   if public._technician_workflow_capabilities(pg_temp.tc_id('r_main'))->>'can_continue'<>'false' then
     raise exception 'FAIL: blocked account capability %',v_state;
   end if;
   set local role authenticated;
   perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_main''),5)','42501','TECHNICIAN_ACCESS_DENIED');
   reset role;
 end loop;
end $$;
update public.profiles set status='active',must_change_password=false where id=pg_temp.tc_id('technician');

set local role authenticated;
do $$ declare v_key text; v_workflow jsonb; begin
 foreach v_key in array array['r_main','r_null','r_new_assignment'] loop
   v_workflow:=public.technician_get_job(pg_temp.tc_id(v_key))->'workflow';
   if v_workflow is distinct from '{"can_start":false,"can_continue":true,"can_submit_result":false,"blocked_reason":"CONTINUE_REQUIRED"}'::jsonb then
     raise exception 'FAIL: rework capability %',v_key;
   end if;
 end loop;
 if public.technician_get_job(pg_temp.tc_id('r_transfer'))->'workflow' is distinct from
   '{"can_start":false,"can_continue":false,"can_submit_result":false,"blocked_reason":"TRANSFER_CONFIRMATION_REQUIRED"}'::jsonb
   or public.technician_get_job(pg_temp.tc_id('r_missing_assignment'))->'workflow' is distinct from
   '{"can_start":false,"can_continue":false,"can_submit_result":false,"blocked_reason":"ASSIGNMENT_NOT_READY"}'::jsonb then
   raise exception 'FAIL: transfer/missing-assignment capabilities';
 end if;
 foreach v_key in array array['r_assigned','r_progress','r_confirmation','r_completed','r_cancelled','r_wrong_assignment'] loop
   v_workflow:=public.technician_get_job(pg_temp.tc_id(v_key))->'workflow';
   if v_workflow->>'can_continue'<>'false' then raise exception 'FAIL: wrong-status capability %',v_key; end if;
 end loop;
 perform pg_temp.tc_expect_error('select public.technician_continue_job(null,5)','P0002','JOB_NOT_FOUND');
 perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''missing''),5)','P0002','JOB_NOT_FOUND');
 foreach v_key in array array['r_foreign','r_transferred'] loop
   perform pg_temp.tc_expect_error(format('select public.technician_continue_job(%L,5)',pg_temp.tc_id(v_key)),'P0002','JOB_NOT_FOUND');
 end loop;
 perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_main''),null)','22023','JOB_VERSION_REQUIRED');
 perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_main''),0)','22023','JOB_VERSION_REQUIRED');
 perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_main''),-1)','22023','JOB_VERSION_REQUIRED');
 perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_main''),4)','P0001','JOB_STATE_CONFLICT');
 perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_main''),6)','P0001','JOB_STATE_CONFLICT');
 foreach v_key in array array['r_assigned','r_progress','r_confirmation','r_completed','r_cancelled'] loop
   perform pg_temp.tc_expect_error(format('select public.technician_continue_job(%L,5)',pg_temp.tc_id(v_key)),'P0001','JOB_STATE_CONFLICT');
 end loop;
 foreach v_key in array array['r_missing_assignment','r_wrong_assignment'] loop
   perform pg_temp.tc_expect_error(format('select public.technician_continue_job(%L,5)',pg_temp.tc_id(v_key)),'P0001','ASSIGNMENT_NOT_READY');
 end loop;
 perform pg_temp.tc_expect_error('select public.technician_continue_job(pg_temp.tc_id(''r_transfer''),5)','P0001','TRANSFER_CONFIRMATION_REQUIRED');
 -- DF-026 and Storage still require continuation before a new repair round.
 perform pg_temp.tc_expect_error('select public.technician_submit_result(pg_temp.tc_id(''r_main''),5,pg_temp.tc_id(''result_first''),''Premature result'')','P0001','JOB_STATE_CONFLICT');
 if public._can_upload_technician_result(pg_temp.tc_photo(5,'result_first','photo_first')->>'storage_path') then
   raise exception 'FAIL: upload before continue';
 end if;
 -- Continuation grants no raw business-table writes.
 perform pg_temp.tc_expect_error('update public.repair_requests set status=''in_progress'' where id=pg_temp.tc_id(''r_main'')','42501');
 perform pg_temp.tc_expect_error('update public.request_assignments set started_at=clock_timestamp() where request_id=pg_temp.tc_id(''r_main'')','42501');
 perform pg_temp.tc_expect_error('update public.repair_results set content=''Edited'' where id=pg_temp.tc_id(''old_result'')','42501');
 perform pg_temp.tc_expect_error('update public.request_feedback set reason=''Edited'' where id=pg_temp.tc_id(''old_feedback'')','42501');
 perform pg_temp.tc_expect_error('delete from public.request_attachments where id=pg_temp.tc_id(''old_photo'')','42501');
 perform pg_temp.tc_expect_error('insert into public.request_history(request_id,entity_type,entity_id,action,actor_id) values(pg_temp.tc_id(''r_main''),''request'',pg_temp.tc_id(''r_main''),''continued'',auth.uid())','42501');
 perform pg_temp.tc_expect_error('delete from public.notifications where request_id=pg_temp.tc_id(''r_main'')','42501');
end $$;
reset role;

do $$ begin
 if exists(select 1 from technician_continue_before b join public.repair_requests r on r.id=b.id where b.kind='request' and b.data<>to_jsonb(r))
 or exists(select 1 from technician_continue_before b join public.request_assignments a on a.id=b.id where b.kind='assignment' and b.data<>to_jsonb(a))
 or exists(select 1 from public.request_history h join technician_continue_context c on c.id=h.request_id)
 or exists(select 1 from public.notifications n join technician_continue_context c on c.id=n.request_id) then
   raise exception 'FAIL: denied continue mutated request/assignment/history/notifications';
 end if;
end $$;

set local role authenticated;
do $$ declare v_key text; v_receipt jsonb; begin
 foreach v_key in array array['r_main','r_null','r_new_assignment'] loop
   v_receipt:=public.technician_continue_job(pg_temp.tc_id(v_key),5);
   if v_receipt is distinct from jsonb_build_object('request_id',pg_temp.tc_id(v_key),'status','in_progress','version',6) then
     raise exception 'FAIL: exact continue receipt %',v_key;
   end if;
   if public.technician_get_job(pg_temp.tc_id(v_key))->'workflow' is distinct from
     '{"can_start":false,"can_continue":false,"can_submit_result":true,"blocked_reason":null}'::jsonb then
     raise exception 'FAIL: post-continue capability %',v_key;
   end if;
   perform pg_temp.tc_expect_error(format('select public.technician_continue_job(%L,5)',pg_temp.tc_id(v_key)),'P0001','JOB_STATE_CONFLICT');
   perform pg_temp.tc_expect_error(format('select public.technician_continue_job(%L,6)',pg_temp.tc_id(v_key)),'P0001','JOB_STATE_CONFLICT');
 end loop;
end $$;
reset role;

do $$ declare v_key text; begin
 foreach v_key in array array['r_main','r_null','r_new_assignment'] loop
   if not exists(select 1 from public.repair_requests r join public.request_assignments a on a.request_id=r.id and a.ended_at is null
     join public.request_history h on h.request_id=r.id and h.action='continued'
     where r.id=pg_temp.tc_id(v_key) and r.status='in_progress' and r.version=6
       and a.started_at>=a.assigned_at and h.actor_id=pg_temp.tc_id('technician')
       and h.entity_type='request' and h.entity_id=r.id and h.old_status='awaiting_rework'
       and h.new_status='in_progress' and h.occurred_at=r.updated_at
       and h.occurred_at>=(select (data->>'updated_at')::timestamptz from technician_continue_before where kind='request' and id=r.id))
     or (select count(*) from public.request_history where request_id=pg_temp.tc_id(v_key) and action='continued')<>1 then
     raise exception 'FAIL: atomic continue state/version/proof/history %',v_key;
   end if;
 end loop;
 if exists(select 1 from technician_continue_before b join public.request_assignments a on a.id=b.id
   where b.kind='assignment' and (b.data-'started_at')<>(to_jsonb(a)-'started_at'))
   or exists(select 1 from technician_continue_before b join public.request_assignments a on a.id=b.id
     where b.kind='assignment' and b.data->>'started_at' is not null and b.data->>'started_at' is distinct from to_jsonb(a)->>'started_at')
   or exists(select 1 from public.notifications n join technician_continue_context c on c.id=n.request_id) then
   raise exception 'FAIL: original start/transfer state changed or unexpected notification';
 end if;
 -- Missing first proof is created at the same trusted server time as continuation.
 if exists(select 1 from public.request_assignments a join public.repair_requests r on r.id=a.request_id
   where r.id in (pg_temp.tc_id('r_null'),pg_temp.tc_id('r_new_assignment')) and a.ended_at is null and a.started_at is distinct from r.updated_at) then
   raise exception 'FAIL: missing proof not created by continuation';
 end if;
end $$;

-- Existing DF-026 paths work after continue without changing submit or Storage functions.
set local role authenticated;
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.tc_photo(6,'result_first','photo_first')->>'storage_path',auth.uid()::text,'{"size":128,"mimetype":"image/png"}');
select public.technician_submit_result(pg_temp.tc_id('r_main'),6,pg_temp.tc_id('result_first'),'First rework result',
 jsonb_build_array(pg_temp.tc_photo(6,'result_first','photo_first')));
select public.technician_submit_result(pg_temp.tc_id('r_null'),6,pg_temp.tc_id('result_null'),'Legacy rework result');
select public.technician_submit_result(pg_temp.tc_id('r_new_assignment'),6,pg_temp.tc_id('result_new_assignment'),'New assignee rework result');
reset role;

-- TEST OWNER simulates the student's next rework decision; this is not a client write.
update public.repair_requests set status='awaiting_rework',version=version+1 where id=pg_temp.tc_id('r_main');
set local role authenticated;
select public.technician_continue_job(pg_temp.tc_id('r_main'),8);
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.tc_photo(9,'result_second','photo_second')->>'storage_path',auth.uid()::text,'{"size":128,"mimetype":"image/png"}');
select public.technician_submit_result(pg_temp.tc_id('r_main'),9,pg_temp.tc_id('result_second'),'Second rework result',
 jsonb_build_array(pg_temp.tc_photo(9,'result_second','photo_second')));
select pg_temp.tc_expect_error('update public.repair_results set content=''Edited'' where id=pg_temp.tc_id(''result_first'')','42501');
select pg_temp.tc_expect_error('delete from public.request_attachments where id=pg_temp.tc_id(''photo_first'')','42501');
reset role;

do $$ begin
 if (select count(*) from public.repair_results where request_id=pg_temp.tc_id('r_main'))<>3
   or (select count(*) from public.request_attachments where request_id=pg_temp.tc_id('r_main'))<>4
   or (select count(*) from public.request_feedback where request_id=pg_temp.tc_id('r_main'))<>1
   or (select count(*) from public.request_history where request_id=pg_temp.tc_id('r_main') and action='continued')<>2
   or (select count(*) from public.request_history where request_id=pg_temp.tc_id('r_main') and action='repair_reported')<>2
   or (select count(*) from public.notifications where request_id=pg_temp.tc_id('r_main'))<>2
   or not exists(select 1 from public.repair_requests where id=pg_temp.tc_id('r_main') and status='awaiting_confirmation' and version=10)
   or not exists(select 1 from public.repair_results where id=pg_temp.tc_id('result_first') and content='First rework result' and request_version=6)
   or not exists(select 1 from public.repair_results where id=pg_temp.tc_id('result_second') and content='Second rework result' and request_version=9)
   or exists(select 1 from technician_continue_before b join public.repair_results r on r.id=b.id where b.kind='result' and b.data<>to_jsonb(r))
   or exists(select 1 from technician_continue_before b join public.request_feedback f on f.id=b.id where b.kind='feedback' and b.data<>to_jsonb(f))
   or exists(select 1 from technician_continue_before b join public.request_attachments a on a.id=b.id where b.kind='attachment' and b.data<>to_jsonb(a))
   or exists(select 1 from technician_continue_before b join storage.objects o on o.id=b.id where b.kind='object' and b.data<>to_jsonb(o))
   or exists(select 1 from technician_continue_before b join public.request_assignments a on a.id=b.id
     where b.kind='assignment' and b.data->>'started_at' is not null and b.data->>'started_at' is distinct from to_jsonb(a)->>'started_at') then
   raise exception 'FAIL: repeated repair round changed prior result/feedback/photos/start or failed to append atomically';
 end if;
end $$;

rollback;
select 'PASS: technician continuation account/assignment/state/version/transfer gates, trusted proof, one audit per continue, immutable prior rounds, and existing DF-026 submission; all fixtures rolled back (Storage metadata only)' as result;
