-- Run as SQL Editor/database owner after 008. Disposable Auth users have no
-- passwords. Storage fixtures are metadata only, with no physical uploads or
-- direct SQL DELETE. All fixtures roll back; demo accounts are unchanged.
begin;

create temporary table technician_transfer_context (key text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into technician_transfer_context(key) values
 ('admin'),('student'),('a'),('b'),('missing'),('room'),('category'),
 ('r_main'),('r_started'),('r_null'),('r_foreign'),('r_former'),('r_missing_assignment'),('r_wrong_assignment'),
 ('r_assigned'),('r_rework'),('r_rework_pending'),('r_confirmation'),('r_completed'),('r_cancelled'),('r_pending'),('r_rejected'),('r_legacy'),('r_future'),
 ('assignment_b'),('assignment_a_again'),('old_result'),('old_feedback'),('old_photo'),('feedback_photo'),
 ('new_result'),('new_photo'),('null_result');
grant select on technician_transfer_context to authenticated, anon;
create function pg_temp.tf_id(p_key text) returns uuid language sql stable as $$
 select id from technician_transfer_context where key=p_key;
$$;
create function pg_temp.tf_photo(p_user text,p_version integer,p_result text,p_photo text) returns jsonb language sql stable as $$
 select jsonb_build_object('id',pg_temp.tf_id(p_photo)::text,
   'storage_path','technician-results/' || pg_temp.tf_id(p_user)::text || '/' || pg_temp.tf_id('r_main')::text
     || '/' || p_version::text || '/' || pg_temp.tf_id(p_result)::text || '/' || pg_temp.tf_id(p_photo)::text || '.png',
   'mime_type','image/png','size_bytes',128);
$$;
create function pg_temp.tf_expect_error(p_sql text,p_state text,p_message text default null)
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
grant execute on function pg_temp.tf_id(text),pg_temp.tf_photo(text,integer,text,text),
 pg_temp.tf_expect_error(text,text,text) to authenticated, anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text || '@technician-transfer-test.invalid',now(),now(),now()
from technician_transfer_context where key in ('admin','student','a','b');
insert into public.rooms(id,code,building) values(pg_temp.tf_id('room'),'TF-' || pg_temp.tf_id('room')::text,'Test building');
insert into public.incident_categories(id,name) values(pg_temp.tf_id('category'),'TF-' || pg_temp.tf_id('category')::text);
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'TF-' || id::text,'Test ' || key,id::text || '@technician-transfer-test.invalid','0900000000',
 case key when 'admin' then 'admin'::public.app_role when 'student' then 'student'::public.app_role else 'technician'::public.app_role end,
 case when key='student' then pg_temp.tf_id('room') end,false
from technician_transfer_context where key in ('admin','student','a','b');
insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id,version,updated_at)
select id,pg_temp.tf_id('student'),pg_temp.tf_id('room'),'Room snapshot','Building snapshot',pg_temp.tf_id('category'),
 'Category snapshot',key,'Synthetic transfer confirmation regression',
 case key when 'r_assigned' then 'assigned'::public.repair_status
   when 'r_rework' then 'awaiting_rework'::public.repair_status
   when 'r_rework_pending' then 'awaiting_rework'::public.repair_status
   when 'r_confirmation' then 'awaiting_confirmation'::public.repair_status
   when 'r_completed' then 'completed'::public.repair_status
   when 'r_cancelled' then 'cancelled'::public.repair_status
   when 'r_pending' then 'pending'::public.repair_status
   when 'r_rejected' then 'rejected'::public.repair_status else 'in_progress'::public.repair_status end,
 case when key in ('r_foreign','r_former') then pg_temp.tf_id('b') else pg_temp.tf_id('a') end,5,now()-interval '1 day'
from technician_transfer_context where left(key,2)='r_';
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,started_at,
 needs_transfer_confirmation,transfer_confirmed_at,request_code_snapshot,title_snapshot,room_code_snapshot)
select r.id,case when c.key='r_wrong_assignment' then pg_temp.tf_id('b') else r.assigned_technician_id end,pg_temp.tf_id('admin'),
 case when c.key='r_future' then now()+interval '1 day' else now()-interval '2 days' end,
 case when c.key='r_started' then now()-interval '47 hours' end,
 c.key not in ('r_main','r_legacy','r_assigned','r_rework'),
 case when c.key='r_main' then now()-interval '47 hours' end,
 r.request_code,r.title,r.room_code_snapshot
from public.repair_requests r join technician_transfer_context c on c.id=r.id
where left(c.key,2)='r_' and c.key<>'r_missing_assignment';
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,ended_at,end_reason,
 needs_transfer_confirmation,transfer_confirmed_at,request_code_snapshot,title_snapshot,room_code_snapshot)
select r.id,pg_temp.tf_id('a'),pg_temp.tf_id('admin'),now()-interval '4 days',now()-interval '3 days','transferred',false,
 now()-interval '95 hours',r.request_code,r.title,r.room_code_snapshot
from public.repair_requests r where r.id=pg_temp.tf_id('r_former');
insert into public.repair_results(id,request_id,assignment_id,submitted_by,content,submitted_at,request_version)
select pg_temp.tf_id('old_result'),a.request_id,a.id,a.technician_id,'Original immutable result',now()-interval '36 hours',3
from public.request_assignments a where a.request_id=pg_temp.tf_id('r_main') and a.ended_at is null;
insert into public.request_feedback(id,request_id,kind,reason,submitted_by,created_at)
values(pg_temp.tf_id('old_feedback'),pg_temp.tf_id('r_main'),'rework','Original immutable feedback',pg_temp.tf_id('student'),now()-interval '1 day');
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.tf_photo('a',3,'old_result','old_photo')->>'storage_path',pg_temp.tf_id('a')::text,'{"size":128,"mimetype":"image/png"}'),
 ('repair-images','transfer-test-feedback/' || pg_temp.tf_id('feedback_photo')::text || '.png',pg_temp.tf_id('student')::text,'{"size":128,"mimetype":"image/png"}');
insert into public.request_attachments(id,request_id,result_id,feedback_id,storage_path,mime_type,size_bytes,uploaded_by)
values(pg_temp.tf_id('old_photo'),pg_temp.tf_id('r_main'),pg_temp.tf_id('old_result'),null,
 pg_temp.tf_photo('a',3,'old_result','old_photo')->>'storage_path','image/png',128,pg_temp.tf_id('a')),
 (pg_temp.tf_id('feedback_photo'),pg_temp.tf_id('r_main'),null,pg_temp.tf_id('old_feedback'),
 'transfer-test-feedback/' || pg_temp.tf_id('feedback_photo')::text || '.png','image/png',128,pg_temp.tf_id('student'));
create temporary table technician_transfer_before on commit drop as
select 'request'::text as kind,r.id,to_jsonb(r) as data from public.repair_requests r join technician_transfer_context c on c.id=r.id
union all select 'assignment',a.id,to_jsonb(a) from public.request_assignments a join technician_transfer_context c on c.id=a.request_id
union all select 'result',r.id,to_jsonb(r) from public.repair_results r where r.id=pg_temp.tf_id('old_result')
union all select 'feedback',f.id,to_jsonb(f) from public.request_feedback f where f.id=pg_temp.tf_id('old_feedback')
union all select 'attachment',a.id,to_jsonb(a) from public.request_attachments a where a.request_id=pg_temp.tf_id('r_main')
union all select 'object',o.id,to_jsonb(o) from storage.objects o where o.name in
 (pg_temp.tf_photo('a',3,'old_result','old_photo')->>'storage_path','transfer-test-feedback/' || pg_temp.tf_id('feedback_photo')::text || '.png');

-- Auth/ACL gates, including the private capability helper.
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.tf_expect_error('select public.technician_confirm_transfer(null,1)','42501');
reset role;
set local role authenticated;
select pg_temp.tf_expect_error('select public.technician_confirm_transfer(null,1)','28000','AUTH_REQUIRED');
select pg_temp.tf_expect_error('select public._technician_workflow_capabilities(null)','42501');
reset role;
do $$ declare v_key text; begin
 foreach v_key in array array['admin','student','missing'] loop
   perform set_config('request.jwt.claim.sub',pg_temp.tf_id(v_key)::text,true);
   if public._technician_workflow_capabilities(pg_temp.tf_id('r_null')) is distinct from
     '{"can_start":false,"can_continue":false,"can_confirm_transfer":false,"can_submit_result":false,"blocked_reason":"READ_ONLY"}'::jsonb then
     raise exception 'FAIL: unauthorized capability %',v_key;
   end if;
   set local role authenticated;
   perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_null''),5)','42501','TECHNICIAN_ACCESS_DENIED');
   reset role;
 end loop;
end $$;
select set_config('request.jwt.claim.sub',pg_temp.tf_id('a')::text,true);
do $$ declare v_state text; begin
 foreach v_state in array array['locked','revoked','password'] loop
   update public.profiles set status=case when v_state='password' then 'active'::public.account_status else v_state::public.account_status end,
     must_change_password=(v_state='password') where id=pg_temp.tf_id('a');
   if public._technician_workflow_capabilities(pg_temp.tf_id('r_null'))->>'can_confirm_transfer'<>'false' then
     raise exception 'FAIL: blocked account capability %',v_state;
   end if;
   set local role authenticated;
   perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_null''),5)','42501','TECHNICIAN_ACCESS_DENIED');
   reset role;
 end loop;
end $$;
update public.profiles set status='active',must_change_password=false where id=pg_temp.tf_id('a');

set local role authenticated;
do $$ declare v_key text; v_workflow jsonb; begin
 foreach v_key in array array['r_started','r_null'] loop
   if public.technician_get_job(pg_temp.tf_id(v_key))->'workflow' is distinct from
     '{"can_start":false,"can_continue":false,"can_confirm_transfer":true,"can_submit_result":false,"blocked_reason":"TRANSFER_CONFIRMATION_REQUIRED"}'::jsonb then
     raise exception 'FAIL: eligible capability %',v_key;
   end if;
 end loop;
 foreach v_key in array array['r_main','r_legacy','r_assigned','r_rework','r_rework_pending','r_confirmation','r_completed','r_cancelled','r_pending','r_rejected','r_missing_assignment','r_wrong_assignment'] loop
   v_workflow:=public.technician_get_job(pg_temp.tf_id(v_key))->'workflow';
   if v_workflow->>'can_confirm_transfer'<>'false' then raise exception 'FAIL: ineligible capability %',v_key; end if;
 end loop;
 if public.technician_get_job(pg_temp.tf_id('r_assigned'))->'workflow'->>'can_start'<>'true'
   or public.technician_get_job(pg_temp.tf_id('r_rework'))->'workflow'->>'can_continue'<>'true'
   or public.technician_get_job(pg_temp.tf_id('r_legacy'))->'workflow'->>'blocked_reason'<>'START_REQUIRED' then
   raise exception 'FAIL: existing start/continue/proof capabilities changed';
 end if;
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(null,5)','P0002','JOB_NOT_FOUND');
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''missing''),5)','P0002','JOB_NOT_FOUND');
 foreach v_key in array array['r_foreign','r_former'] loop
   perform pg_temp.tf_expect_error(format('select public.technician_confirm_transfer(%L,5)',pg_temp.tf_id(v_key)),'P0002','JOB_NOT_FOUND');
 end loop;
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_null''),null)','22023','JOB_VERSION_REQUIRED');
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_null''),0)','22023','JOB_VERSION_REQUIRED');
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_null''),-1)','22023','JOB_VERSION_REQUIRED');
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_null''),4)','P0001','JOB_STATE_CONFLICT');
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_null''),6)','P0001','JOB_STATE_CONFLICT');
 foreach v_key in array array['r_main','r_legacy','r_assigned','r_rework','r_rework_pending','r_confirmation','r_completed','r_cancelled','r_pending','r_rejected','r_future'] loop
   perform pg_temp.tf_expect_error(format('select public.technician_confirm_transfer(%L,5)',pg_temp.tf_id(v_key)),'P0001','JOB_STATE_CONFLICT');
 end loop;
 foreach v_key in array array['r_missing_assignment','r_wrong_assignment'] loop
   perform pg_temp.tf_expect_error(format('select public.technician_confirm_transfer(%L,5)',pg_temp.tf_id(v_key)),'P0001','ASSIGNMENT_NOT_READY');
 end loop;
 perform pg_temp.tf_expect_error('select public.technician_submit_result(pg_temp.tf_id(''r_null''),5,pg_temp.tf_id(''null_result''),''Before confirm'')','P0001','TRANSFER_CONFIRMATION_REQUIRED');
 perform pg_temp.tf_expect_error('update public.repair_requests set version=version+1 where id=pg_temp.tf_id(''r_null'')','42501');
 perform pg_temp.tf_expect_error('update public.request_assignments set needs_transfer_confirmation=false where request_id=pg_temp.tf_id(''r_null'')','42501');
 perform pg_temp.tf_expect_error('update public.repair_results set content=''Edited'' where id=pg_temp.tf_id(''old_result'')','42501');
 perform pg_temp.tf_expect_error('update public.request_feedback set reason=''Edited'' where id=pg_temp.tf_id(''old_feedback'')','42501');
 perform pg_temp.tf_expect_error('delete from public.request_attachments where id=pg_temp.tf_id(''old_photo'')','42501');
 perform pg_temp.tf_expect_error('insert into public.request_history(request_id,entity_type,entity_id,action,actor_id) values(pg_temp.tf_id(''r_null''),''request'',pg_temp.tf_id(''r_null''),''transfer_confirmed'',auth.uid())','42501');
end $$;
reset role;
do $$ begin
 if exists(select 1 from technician_transfer_before b join public.repair_requests r on r.id=b.id where b.kind='request' and b.data<>to_jsonb(r))
   or exists(select 1 from technician_transfer_before b join public.request_assignments a on a.id=b.id where b.kind='assignment' and b.data<>to_jsonb(a))
   or exists(select 1 from public.request_history h join technician_transfer_context c on c.id=h.request_id)
   or exists(select 1 from public.notifications n join technician_transfer_context c on c.id=n.request_id) then
   raise exception 'FAIL: denied confirm mutated data';
 end if;
end $$;

-- Confirm leaves existing started_at intact and does not invent one for NULL.
set local role authenticated;
do $$ declare v_key text; v_receipt jsonb; begin
 foreach v_key in array array['r_started','r_null'] loop
   v_receipt:=public.technician_confirm_transfer(pg_temp.tf_id(v_key),5);
   if v_receipt is distinct from jsonb_build_object('request_id',pg_temp.tf_id(v_key),'status','in_progress','version',6) then
     raise exception 'FAIL: exact confirm receipt %',v_key;
   end if;
   if public.technician_get_job(pg_temp.tf_id(v_key))->'workflow' is distinct from
     '{"can_start":false,"can_continue":false,"can_confirm_transfer":false,"can_submit_result":true,"blocked_reason":null}'::jsonb then
     raise exception 'FAIL: post-confirm capability %',v_key;
   end if;
   perform pg_temp.tf_expect_error(format('select public.technician_confirm_transfer(%L,5)',pg_temp.tf_id(v_key)),'P0001','JOB_STATE_CONFLICT');
   perform pg_temp.tf_expect_error(format('select public.technician_confirm_transfer(%L,6)',pg_temp.tf_id(v_key)),'P0001','JOB_STATE_CONFLICT');
 end loop;
end $$;
reset role;
do $$ declare v_key text; begin
 foreach v_key in array array['r_started','r_null'] loop
   if not exists(select 1 from public.repair_requests r join public.request_assignments a on a.request_id=r.id and a.ended_at is null
     join public.request_history h on h.request_id=r.id and h.action='transfer_confirmed'
     where r.id=pg_temp.tf_id(v_key) and r.status='in_progress' and r.version=6 and not a.needs_transfer_confirmation
       and a.transfer_confirmed_at>=a.assigned_at and a.transfer_confirmed_at=r.updated_at
       and h.entity_type='request' and h.entity_id=r.id and h.actor_id=pg_temp.tf_id('a')
       and h.old_status='in_progress' and h.new_status='in_progress' and h.occurred_at=r.updated_at)
     or (select count(*) from public.request_history where request_id=pg_temp.tf_id(v_key) and action='transfer_confirmed')<>1 then
     raise exception 'FAIL: atomic confirmation/proof/history %',v_key;
   end if;
 end loop;
 if exists(select 1 from technician_transfer_before b join public.request_assignments a on a.id=b.id
   where b.kind='assignment' and ((b.data-'needs_transfer_confirmation'-'transfer_confirmed_at')<>(to_jsonb(a)-'needs_transfer_confirmation'-'transfer_confirmed_at')))
   or exists(select 1 from public.notifications n join technician_transfer_context c on c.id=n.request_id) then
   raise exception 'FAIL: confirm changed start/other assignment data or added notification';
 end if;
end $$;
set local role authenticated;
select public.technician_submit_result(pg_temp.tf_id('r_null'),6,pg_temp.tf_id('null_result'),'Confirmed with NULL start proof');
reset role;

-- TEST OWNER simulates the required future Admin transaction A -> B. No Admin
-- transfer backend is implemented here: close old, insert fresh, preserve state,
-- increment request version, and never inherit the previous proof.
do $$ declare v_now timestamptz:=clock_timestamp(); begin
 update public.request_assignments set ended_at=v_now,end_reason='transferred' where request_id=pg_temp.tf_id('r_main') and ended_at is null;
 insert into public.request_assignments(id,request_id,technician_id,assigned_by,assigned_at,needs_transfer_confirmation,
   request_code_snapshot,title_snapshot,room_code_snapshot,transfer_reason)
 select pg_temp.tf_id('assignment_b'),r.id,pg_temp.tf_id('b'),pg_temp.tf_id('admin'),v_now,true,
   r.request_code,r.title,r.room_code_snapshot,'Synthetic A to B' from public.repair_requests r where r.id=pg_temp.tf_id('r_main');
 update public.repair_requests set assigned_technician_id=pg_temp.tf_id('b'),version=version+1,updated_at=v_now where id=pg_temp.tf_id('r_main');
end $$;
set local role authenticated;
select pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_main''),5)','P0002','JOB_NOT_FOUND');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.tf_id('b')::text,true);
set local role authenticated;
do $$ declare v_photo jsonb:=pg_temp.tf_photo('b',6,'new_result','new_photo'); v_receipt jsonb; begin
 if public._can_upload_technician_result(v_photo->>'storage_path') then raise exception 'FAIL: B upload before confirm'; end if;
 perform pg_temp.tf_expect_error(format('insert into storage.objects(bucket_id,name,owner_id,metadata) values(''repair-images'',%L,%L,''{"size":128,"mimetype":"image/png"}'')',v_photo->>'storage_path',auth.uid()::text),'42501');
 perform pg_temp.tf_expect_error('select public.technician_submit_result(pg_temp.tf_id(''r_main''),6,pg_temp.tf_id(''new_result''),''Before B confirm'')','P0001','TRANSFER_CONFIRMATION_REQUIRED');
 v_receipt:=public.technician_confirm_transfer(pg_temp.tf_id('r_main'),6);
 if v_receipt is distinct from jsonb_build_object('request_id',pg_temp.tf_id('r_main'),'status','in_progress','version',7)
   or not public._can_upload_technician_result(pg_temp.tf_photo('b',7,'new_result','new_photo')->>'storage_path') then
   raise exception 'FAIL: B confirmation receipt/upload proof';
 end if;
end $$;
reset role;
-- Preserve completed confirmation rows exactly while the next transfer occurs.
create temporary table technician_transfer_confirmed_b on commit drop as
 select to_jsonb(a) as data from public.request_assignments a where a.id=pg_temp.tf_id('assignment_b');
do $$ declare v_now timestamptz:=clock_timestamp(); begin
 update public.request_assignments set ended_at=v_now,end_reason='transferred' where id=pg_temp.tf_id('assignment_b');
 insert into public.request_assignments(id,request_id,technician_id,assigned_by,assigned_at,needs_transfer_confirmation,
   request_code_snapshot,title_snapshot,room_code_snapshot,transfer_reason)
 select pg_temp.tf_id('assignment_a_again'),r.id,pg_temp.tf_id('a'),pg_temp.tf_id('admin'),v_now,true,
   r.request_code,r.title,r.room_code_snapshot,'Synthetic B to A' from public.repair_requests r where r.id=pg_temp.tf_id('r_main');
 update public.repair_requests set assigned_technician_id=pg_temp.tf_id('a'),version=version+1,updated_at=v_now where id=pg_temp.tf_id('r_main');
end $$;
set local role authenticated;
select pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_main''),7)','P0002','JOB_NOT_FOUND');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.tf_id('a')::text,true);
set local role authenticated;
do $$ declare v_photo jsonb:=pg_temp.tf_photo('a',8,'new_result','new_photo'); v_receipt jsonb; begin
 -- Same UID as the first assignment is insufficient: old version/proof cannot authorize this one.
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_main''),5)','P0001','JOB_STATE_CONFLICT');
 if public.technician_get_job(pg_temp.tf_id('r_main'))->'workflow' is distinct from
   '{"can_start":false,"can_continue":false,"can_confirm_transfer":true,"can_submit_result":false,"blocked_reason":"TRANSFER_CONFIRMATION_REQUIRED"}'::jsonb
   or public._can_upload_technician_result(v_photo->>'storage_path') then raise exception 'FAIL: A inherited prior proof'; end if;
 perform pg_temp.tf_expect_error('select public.technician_submit_result(pg_temp.tf_id(''r_main''),8,pg_temp.tf_id(''new_result''),''Before A reconfirm'')','P0001','TRANSFER_CONFIRMATION_REQUIRED');
 v_receipt:=public.technician_confirm_transfer(pg_temp.tf_id('r_main'),8);
 if v_receipt is distinct from jsonb_build_object('request_id',pg_temp.tf_id('r_main'),'status','in_progress','version',9) then
   raise exception 'FAIL: A reconfirm exact receipt'; end if;
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_main''),8)','P0001','JOB_STATE_CONFLICT');
 perform pg_temp.tf_expect_error('select public.technician_confirm_transfer(pg_temp.tf_id(''r_main''),9)','P0001','JOB_STATE_CONFLICT');
end $$;
reset role;
do $$ begin
 if (select count(*) from public.request_assignments where request_id=pg_temp.tf_id('r_main'))<>3
   or not exists(select 1 from public.request_assignments where id=pg_temp.tf_id('assignment_a_again') and started_at is null
     and not needs_transfer_confirmation and transfer_confirmed_at>=assigned_at and ended_at is null)
   or (select count(*) from public.request_history where request_id=pg_temp.tf_id('r_main') and action='transfer_confirmed')<>2
   or not exists(select 1 from public.request_assignments a join public.repair_requests r on r.id=a.request_id
     join public.request_history h on h.request_id=r.id and h.action='transfer_confirmed' and h.actor_id=a.technician_id
     where a.id=pg_temp.tf_id('assignment_a_again') and r.status='in_progress' and r.version=9
       and h.old_status='in_progress' and h.new_status='in_progress' and h.entity_type='request' and h.entity_id=r.id
       and h.occurred_at=a.transfer_confirmed_at and h.occurred_at=r.updated_at)
   or not exists(select 1 from public.request_assignments a join public.request_history h on h.request_id=a.request_id
     where a.id=pg_temp.tf_id('assignment_b') and h.action='transfer_confirmed' and h.actor_id=pg_temp.tf_id('b')
       and h.occurred_at=a.transfer_confirmed_at and h.old_status='in_progress' and h.new_status='in_progress')
   or exists(select 1 from technician_transfer_confirmed_b b join public.request_assignments a on a.id=pg_temp.tf_id('assignment_b')
     where (b.data-'ended_at'-'end_reason')<>(to_jsonb(a)-'ended_at'-'end_reason'))
   or exists(select 1 from public.notifications n where n.request_id=pg_temp.tf_id('r_main')) then
   raise exception 'FAIL: fresh assignment per transfer, confirmation audit, old proof, or no-notification contract';
 end if;
end $$;
-- Existing Storage policy and DF-026 finalize a new result with the newly confirmed version.
set local role authenticated;
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.tf_photo('a',9,'new_result','new_photo')->>'storage_path',auth.uid()::text,'{"size":128,"mimetype":"image/png"}');
select public.technician_submit_result(pg_temp.tf_id('r_main'),9,pg_temp.tf_id('new_result'),'New technician result',
 jsonb_build_array(pg_temp.tf_photo('a',9,'new_result','new_photo')));
reset role;
do $$ begin
 if (select count(*) from public.repair_results where request_id=pg_temp.tf_id('r_main'))<>2
   or (select count(*) from public.request_attachments where request_id=pg_temp.tf_id('r_main'))<>3
   or (select count(*) from public.request_history where request_id=pg_temp.tf_id('r_main') and action='repair_reported')<>1
   or (select count(*) from public.notifications where request_id=pg_temp.tf_id('r_main'))<>1
   or not exists(select 1 from public.repair_requests where id=pg_temp.tf_id('r_main') and status='awaiting_confirmation' and version=10)
   or not exists(select 1 from public.repair_results where id=pg_temp.tf_id('new_result') and assignment_id=pg_temp.tf_id('assignment_a_again') and request_version=9)
   or exists(select 1 from technician_transfer_before b join public.repair_results r on r.id=b.id where b.kind='result' and b.data<>to_jsonb(r))
   or exists(select 1 from technician_transfer_before b join public.request_feedback f on f.id=b.id where b.kind='feedback' and b.data<>to_jsonb(f))
   or exists(select 1 from technician_transfer_before b join public.request_attachments a on a.id=b.id where b.kind='attachment' and b.data<>to_jsonb(a))
   or exists(select 1 from technician_transfer_before b join storage.objects o on o.id=b.id where b.kind='object' and b.data<>to_jsonb(o))
   or exists(select 1 from technician_transfer_before b join public.request_assignments a on a.id=b.id
     where b.kind='assignment' and a.request_id=pg_temp.tf_id('r_main')
       and (b.data-'ended_at'-'end_reason')<>(to_jsonb(a)-'ended_at'-'end_reason'))
   or exists(select 1 from technician_transfer_before b join public.request_assignments a on a.id=b.id
     where b.kind='assignment' and (b.data-'ended_at'-'end_reason'-'needs_transfer_confirmation'-'transfer_confirmed_at')<>
       (to_jsonb(a)-'ended_at'-'end_reason'-'needs_transfer_confirmation'-'transfer_confirmed_at')) then
   raise exception 'FAIL: existing submission or immutable result/feedback/photos/start data';
 end if;
end $$;

rollback;
select 'PASS: transfer confirmation gates, atomic proof/audit, A-to-B-to-A fresh assignments and version checks, and existing DF-026 upload/submit; all fixtures rolled back (Storage metadata only; Admin transfer simulated)' as result;
