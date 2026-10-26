-- Run as SQL Editor/database owner after 005 (or in a transaction with 005).
-- Synthetic Auth users have no passwords. Storage rows here are TEST METADATA
-- only, not physical uploads. Every fixture is rolled back. No demo gate changes.
begin;

create temporary table technician_workflow_context (key text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into technician_workflow_context(key) values
 ('admin'),('student'),('technician'),('other'),('room'),('category'),
 ('r_main'),('r_text'),('r_legacy'),('r_transfer'),('r_rework'),('r_completed'),
 ('r_foreign'),('r_missing_assignment'),('r_bad_photos'),('r_cancelled'),
 ('result_main'),('result_text'),('result_bad'),('result_other'),('result_second'),
 ('photo1'),('photo2'),('photo3'),('photo4'),('photo5'),('photo6'),('badphoto'),('cleanup_photo');
grant select on technician_workflow_context to authenticated, anon;

create function pg_temp.tw_id(p_key text) returns uuid language sql stable as $$
  select id from technician_workflow_context where key = p_key;
$$;
create function pg_temp.tw_photo(p_request text, p_version integer, p_result text, p_photo text,
  p_mime text default 'image/png', p_size integer default 128) returns jsonb language sql stable as $$
  select jsonb_build_object('id', pg_temp.tw_id(p_photo)::text,
    'storage_path', 'technician-results/' || pg_temp.tw_id('technician')::text || '/'
      || pg_temp.tw_id(p_request)::text || '/' || p_version::text || '/'
      || pg_temp.tw_id(p_result)::text || '/' || pg_temp.tw_id(p_photo)::text
      || case p_mime when 'image/jpeg' then '.jpg' when 'image/webp' then '.webp' else '.png' end,
    'mime_type', p_mime, 'size_bytes', p_size);
$$;
create function pg_temp.tw_expect_error(p_sql text, p_state text, p_message text default null)
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
    (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;
grant execute on function pg_temp.tw_id(text), pg_temp.tw_photo(text,integer,text,text,text,integer),
  pg_temp.tw_expect_error(text,text,text) to authenticated, anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text || '@technician-workflow-test.invalid',now(),now(),now()
from technician_workflow_context where key in ('admin','student','technician','other');
insert into public.rooms(id,code,building) values(pg_temp.tw_id('room'),'TW-' || pg_temp.tw_id('room')::text,'Test building');
insert into public.incident_categories(id,name) values(pg_temp.tw_id('category'),'TW-' || pg_temp.tw_id('category')::text);
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'TW-' || id::text,'Test ' || key,id::text || '@technician-workflow-test.invalid','0900000000',
 case key when 'admin' then 'admin'::public.app_role when 'student' then 'student'::public.app_role else 'technician'::public.app_role end,
 case when key = 'student' then pg_temp.tw_id('room') end,false
from technician_workflow_context where key in ('admin','student','technician','other');
insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id)
select id,pg_temp.tw_id('student'),pg_temp.tw_id('room'),'Room snapshot','Building snapshot',
 pg_temp.tw_id('category'),'Category snapshot',key,'Synthetic regression request',
 case when key in ('r_legacy','r_transfer') then 'in_progress'::public.repair_status
   when key = 'r_rework' then 'awaiting_rework'::public.repair_status
   when key = 'r_completed' then 'completed'::public.repair_status
   when key = 'r_cancelled' then 'cancelled'::public.repair_status else 'assigned'::public.repair_status end,
 case when key = 'r_foreign' then pg_temp.tw_id('other') else pg_temp.tw_id('technician') end
from technician_workflow_context where left(key,2) = 'r_';
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,
 needs_transfer_confirmation,request_code_snapshot,title_snapshot,room_code_snapshot)
select r.id,r.assigned_technician_id,pg_temp.tw_id('admin'),now()-interval '1 day',r.id=pg_temp.tw_id('r_transfer'),
 r.request_code,r.title,r.room_code_snapshot
from public.repair_requests r join technician_workflow_context c on c.id = r.id
where left(c.key,2) = 'r_' and c.key <> 'r_missing_assignment';

-- Execute grants and role/account gates are server-side, not just UI checks.
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.tw_expect_error('select public.technician_start_job(null,1)','42501');
select pg_temp.tw_expect_error('select public.technician_submit_result(null,1,null,''x'')','42501');
reset role;
set local role authenticated;
select pg_temp.tw_expect_error('select public.technician_start_job(null,1)','28000','AUTH_REQUIRED');
select pg_temp.tw_expect_error('select public.technician_submit_result(null,1,null,''x'')','28000','AUTH_REQUIRED');
select pg_temp.tw_expect_error('select public._technician_workflow_actor()','42501');
reset role;
do $$ declare v_key text; begin
 foreach v_key in array array['admin','student','other_missing_profile'] loop
   perform set_config('request.jwt.claim.sub',coalesce(pg_temp.tw_id(v_key),gen_random_uuid())::text,true);
   set local role authenticated;
   perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_main''),1)','42501','TECHNICIAN_ACCESS_DENIED');
   perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_main''),1,pg_temp.tw_id(''result_main''),''x'')','42501','TECHNICIAN_ACCESS_DENIED');
   reset role;
 end loop;
end $$;
select set_config('request.jwt.claim.sub',pg_temp.tw_id('technician')::text,true);
do $$ declare v_state text; begin
 foreach v_state in array array['locked','revoked','password'] loop
   update public.profiles set status=case when v_state='password' then 'active'::public.account_status else v_state::public.account_status end,
     must_change_password=(v_state='password') where id=pg_temp.tw_id('technician');
   set local role authenticated;
   perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_main''),1)','42501','TECHNICIAN_ACCESS_DENIED');
   perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_main''),1,pg_temp.tw_id(''result_main''),''x'')','42501','TECHNICIAN_ACCESS_DENIED');
   if public._can_upload_technician_result(pg_temp.tw_photo('r_main',1,'result_main','photo1')->>'storage_path') then
     raise exception 'FAIL: blocked account upload %',v_state;
   end if;
   reset role;
 end loop;
end $$;
update public.profiles set status='active',must_change_password=false where id=pg_temp.tw_id('technician');

set local role authenticated;
do $$ declare v_detail jsonb; v_receipt jsonb; begin
 v_detail := public.technician_get_job(pg_temp.tw_id('r_main'));
 if ((v_detail->'workflow') - 'can_continue') is distinct from '{"can_start":true,"can_submit_result":false,"blocked_reason":null}'::jsonb then
   raise exception 'FAIL: initial workflow capability'; end if;
 if public.technician_get_job(pg_temp.tw_id('r_missing_assignment'))->'workflow'->>'blocked_reason' <> 'ASSIGNMENT_NOT_READY'
   or public.technician_get_job(pg_temp.tw_id('r_legacy'))->'workflow'->>'blocked_reason' <> 'START_REQUIRED'
   or public.technician_get_job(pg_temp.tw_id('r_transfer'))->'workflow'->>'blocked_reason' <> 'TRANSFER_CONFIRMATION_REQUIRED'
   or public.technician_get_job(pg_temp.tw_id('r_rework'))->'workflow'->>'blocked_reason' <> 'CONTINUE_REQUIRED'
   or public.technician_get_job(pg_temp.tw_id('r_completed'))->'workflow'->>'blocked_reason' <> 'READ_ONLY' then
   raise exception 'FAIL: legacy/transfer/rework/read-only capabilities'; end if;
 perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_foreign''),1)','P0002','JOB_NOT_FOUND');
 perform pg_temp.tw_expect_error('select public.technician_start_job(null,1)','P0002','JOB_NOT_FOUND');
 perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_missing_assignment''),1)','P0001','ASSIGNMENT_NOT_READY');
 perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_main''),null)','22023','JOB_VERSION_REQUIRED');
 perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_main''),2)','P0001','JOB_STATE_CONFLICT');
 perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_cancelled''),1)','P0001','JOB_STATE_CONFLICT');
 v_receipt := public.technician_start_job(pg_temp.tw_id('r_main'),1);
 if v_receipt->>'status' <> 'in_progress' or (v_receipt->>'version')::integer <> 2 then raise exception 'FAIL: start receipt'; end if;
 if public.technician_get_job(pg_temp.tw_id('r_main'))->'workflow'->>'can_submit_result' <> 'true' then raise exception 'FAIL: post-start capability'; end if;
 perform pg_temp.tw_expect_error('select public.technician_start_job(pg_temp.tw_id(''r_main''),1)','P0001','JOB_STATE_CONFLICT');
 perform public.technician_start_job(pg_temp.tw_id('r_text'),1);
 perform public.technician_start_job(pg_temp.tw_id('r_bad_photos'),1);
end $$;
reset role;
do $$ begin
 if (select count(*) from public.request_history where request_id=pg_temp.tw_id('r_main') and action='started') <> 1
   or not exists(select 1 from public.request_assignments where request_id=pg_temp.tw_id('r_main') and started_at >= assigned_at)
   or (select version from public.repair_requests where id=pg_temp.tw_id('r_main')) <> 2 then
   raise exception 'FAIL: one start/audit/server proof'; end if;
end $$;

-- Staging policies: correct owner/path/start/version; no arbitrary or sixth file.
set local role authenticated;
do $$ declare v_photo jsonb; v_key text; begin
 foreach v_key in array array['photo1','photo2','photo3','photo4','photo5'] loop
   v_photo := pg_temp.tw_photo('r_main',2,'result_main',v_key);
   insert into storage.objects(bucket_id,name,owner_id,metadata)
   values('repair-images',v_photo->>'storage_path',auth.uid()::text,jsonb_build_object('size',128,'mimetype','image/png'));
 end loop;
 v_photo := pg_temp.tw_photo('r_main',2,'result_main','photo6');
 perform pg_temp.tw_expect_error(format('insert into storage.objects(bucket_id,name,owner_id,metadata) values(''repair-images'',%L,%L,''{"size":128,"mimetype":"image/png"}'')',
   v_photo->>'storage_path',auth.uid()::text),'42501');
 perform pg_temp.tw_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',''arbitrary/path.png'',%L)',auth.uid()::text),'42501');
 v_photo := pg_temp.tw_photo('r_main',2,'result_other','photo6');
 perform pg_temp.tw_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',%L,%L)',
   replace(v_photo->>'storage_path',auth.uid()::text,pg_temp.tw_id('other')::text),auth.uid()::text),'42501');
 v_photo := pg_temp.tw_photo('r_main',1,'result_other','photo6');
 perform pg_temp.tw_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',%L,%L)',
   v_photo->>'storage_path',auth.uid()::text),'42501');
 v_photo := pg_temp.tw_photo('r_legacy',1,'result_other','photo6');
 perform pg_temp.tw_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',%L,%L)',v_photo->>'storage_path',auth.uid()::text),'42501');
 v_photo := pg_temp.tw_photo('r_transfer',1,'result_other','photo6');
 perform pg_temp.tw_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',%L,%L)',v_photo->>'storage_path',auth.uid()::text),'42501');
 v_photo := pg_temp.tw_photo('r_main',2,'result_other','cleanup_photo');
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-images',v_photo->>'storage_path',auth.uid()::text,'{"size":128,"mimetype":"image/png"}');
 if not public._can_delete_technician_result(v_photo->>'storage_path') then raise exception 'FAIL: own staging cleanup denied'; end if;
 -- Live Storage protects direct SQL DELETE, including owner SQL fixtures.
 -- Exercise delete eligibility here; real removal must use the Storage API.
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
   and policyname='technician_result_staged_delete' and cmd='DELETE'
   and qual like '%_can_delete_technician_result%' and qual like '%owner_id%') then
   raise exception 'FAIL: staging delete policy missing eligibility/owner checks'; end if;
end $$;
reset role;

-- Invalid metadata is introduced by the TEST OWNER only, never by migration/API.
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.tw_photo('r_bad_photos',2,'result_bad','badphoto')->>'storage_path',pg_temp.tw_id('other')::text,
 '{"size":128,"mimetype":"image/png"}');
set local role authenticated;
do $$ declare v_photos jsonb; begin
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_text''),2,pg_temp.tw_id(''result_text''),E'' \t\n '')','22023','RESULT_CONTENT_REQUIRED');
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_text''),2,pg_temp.tw_id(''result_text''),''x'',null)','22023','INVALID_RESULT_PHOTOS');
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_legacy''),1,pg_temp.tw_id(''result_other''),''x'')','P0001','START_REQUIRED');
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_transfer''),1,pg_temp.tw_id(''result_other''),''x'')','P0001','TRANSFER_CONFIRMATION_REQUIRED');
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_rework''),1,pg_temp.tw_id(''result_other''),''x'')','P0001','JOB_STATE_CONFLICT');
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_completed''),1,pg_temp.tw_id(''result_other''),''x'')','P0001','JOB_STATE_CONFLICT');
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_foreign''),1,pg_temp.tw_id(''result_other''),''x'')','P0002','JOB_NOT_FOUND');
 v_photos := jsonb_build_array(pg_temp.tw_photo('r_bad_photos',2,'result_bad','badphoto'));
 perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Wrong owner'',%L)',pg_temp.tw_id('r_bad_photos'),pg_temp.tw_id('result_bad'),v_photos),'22023','INVALID_RESULT_PHOTOS');
 v_photos := jsonb_build_array(pg_temp.tw_photo('r_text',2,'result_text','photo6'));
 perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Missing object'',%L)',pg_temp.tw_id('r_text'),pg_temp.tw_id('result_text'),v_photos),'22023','INVALID_RESULT_PHOTOS');
 v_photos := jsonb_build_array(pg_temp.tw_photo('r_main',2,'result_main','photo1'));
 perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Foreign path'',%L)',pg_temp.tw_id('r_text'),pg_temp.tw_id('result_text'),v_photos),'22023','INVALID_RESULT_PHOTOS');
 v_photos := jsonb_build_array(pg_temp.tw_photo('r_main',2,'result_main','photo1'),pg_temp.tw_photo('r_main',2,'result_main','photo1'));
 perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Duplicate photo'',%L)',pg_temp.tw_id('r_main'),pg_temp.tw_id('result_main'),v_photos),'22023','INVALID_RESULT_PHOTOS');
 v_photos := jsonb_build_array(jsonb_set(pg_temp.tw_photo('r_main',2,'result_main','photo1'),'{storage_path}',
   to_jsonb(replace(pg_temp.tw_photo('r_main',2,'result_main','photo1')->>'storage_path',auth.uid()::text,pg_temp.tw_id('other')::text))));
 perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Forged owner path'',%L)',pg_temp.tw_id('r_main'),pg_temp.tw_id('result_main'),v_photos),'22023','INVALID_RESULT_PHOTOS');
 v_photos := jsonb_build_array(pg_temp.tw_photo('r_main',1,'result_main','photo1'));
 perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Wrong path version'',%L)',pg_temp.tw_id('r_main'),pg_temp.tw_id('result_main'),v_photos),'22023','INVALID_RESULT_PHOTOS');
 v_photos := '[]'::jsonb;
 for v_photos in select jsonb_agg(pg_temp.tw_photo('r_main',2,'result_main',key)) from technician_workflow_context where key in ('photo1','photo2','photo3','photo4','photo5','photo6') loop
   perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Too many'',%L)',pg_temp.tw_id('r_main'),pg_temp.tw_id('result_main'),v_photos),'22023','INVALID_RESULT_PHOTOS');
 end loop;
 perform pg_temp.tw_expect_error('update public.repair_requests set status=''awaiting_confirmation'' where id=pg_temp.tw_id(''r_main'')','42501');
 perform pg_temp.tw_expect_error('insert into public.repair_results(request_id,assignment_id,submitted_by,content) values(pg_temp.tw_id(''r_main''),gen_random_uuid(),auth.uid(),''Bypass'')','42501');
end $$;
reset role;

-- Correct-owner objects still require actual Storage MIME and size to agree.
update storage.objects set owner_id=pg_temp.tw_id('technician')::text,
 metadata='{"size":128,"mimetype":"image/jpeg"}'
where bucket_id='repair-images' and name=pg_temp.tw_photo('r_bad_photos',2,'result_bad','badphoto')->>'storage_path';
set local role authenticated;
select pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Wrong MIME'',%L)',
 pg_temp.tw_id('r_bad_photos'),pg_temp.tw_id('result_bad'),jsonb_build_array(pg_temp.tw_photo('r_bad_photos',2,'result_bad','badphoto'))),'22023','INVALID_RESULT_PHOTOS');
reset role;
update storage.objects set metadata='{"size":129,"mimetype":"image/png"}'
where bucket_id='repair-images' and name=pg_temp.tw_photo('r_bad_photos',2,'result_bad','badphoto')->>'storage_path';
set local role authenticated;
select pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Wrong size'',%L)',
 pg_temp.tw_id('r_bad_photos'),pg_temp.tw_id('result_bad'),jsonb_build_array(pg_temp.tw_photo('r_bad_photos',2,'result_bad','badphoto'))),'22023','INVALID_RESULT_PHOTOS');
reset role;
do $$ begin
 if exists(select 1 from public.repair_results where request_id in (pg_temp.tw_id('r_main'),pg_temp.tw_id('r_bad_photos'),pg_temp.tw_id('r_text')))
   or exists(select 1 from public.notifications where request_id=pg_temp.tw_id('r_main'))
   or (select version from public.repair_requests where id=pg_temp.tw_id('r_main')) <> 2 then
   raise exception 'FAIL: invalid submission changed data'; end if;
end $$;

-- Valid submission, exact immutable retry, and no overwrite/deletion afterward.
set local role authenticated;
do $$ declare v_photos jsonb; v_receipt jsonb; v_count integer; begin
 select jsonb_agg(pg_temp.tw_photo('r_main',2,'result_main',key) order by key) into v_photos
   from technician_workflow_context where key in ('photo1','photo2','photo3','photo4','photo5');
 v_receipt := public.technician_submit_result(pg_temp.tw_id('r_main'),2,pg_temp.tw_id('result_main'),'  Đã sửa và kiểm tra  ',v_photos);
 if v_receipt->>'status' <> 'awaiting_confirmation' or v_receipt->>'version' <> '3' or v_receipt->>'replayed' <> 'false' then
   raise exception 'FAIL: submit receipt'; end if;
 v_receipt := public.technician_submit_result(pg_temp.tw_id('r_main'),2,pg_temp.tw_id('result_main'),'Đã sửa và kiểm tra',v_photos);
 if v_receipt->>'replayed' <> 'true' or v_receipt->>'version' <> '3' then raise exception 'FAIL: exact replay'; end if;
 perform pg_temp.tw_expect_error(format('select public.technician_submit_result(%L,2,%L,''Edited result'',%L)',pg_temp.tw_id('r_main'),pg_temp.tw_id('result_main'),v_photos),'22023','RESULT_REPLAY_MISMATCH');
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_main''),2,pg_temp.tw_id(''result_other''),''Duplicate'')','P0001','JOB_STATE_CONFLICT');
 if public._can_delete_technician_result(v_photos->0->>'storage_path') then raise exception 'FAIL: finalized cleanup helper'; end if;
 if public._is_own_uncommitted_technician_result(v_photos->0->>'storage_path') then
   raise exception 'FAIL: finalized object eligible for staging reads'; end if;
 update storage.objects set metadata='{"size":1,"mimetype":"image/png"}'
   where bucket_id='repair-images' and name=v_photos->0->>'storage_path';
 get diagnostics v_count = row_count;
 if v_count <> 0 then raise exception 'FAIL: finalized object overwritten'; end if;
 perform public.technician_submit_result(pg_temp.tw_id('r_text'),2,pg_temp.tw_id('result_text'),'Kết quả không ảnh');
 if public.technician_get_job(pg_temp.tw_id('r_main'))->'workflow'->>'can_submit_result' <> 'false' then
   raise exception 'FAIL: submit remains enabled after completion'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.repair_results where request_id=pg_temp.tw_id('r_main')) <> 1
   or (select content from public.repair_results where id=pg_temp.tw_id('result_main')) <> 'Đã sửa và kiểm tra'
   or (select count(*) from public.request_attachments where result_id=pg_temp.tw_id('result_main')) <> 5
   or (select count(*) from public.request_history where request_id=pg_temp.tw_id('r_main') and action='repair_reported') <> 1
   or (select count(*) from public.notifications where request_id=pg_temp.tw_id('r_main') and event_type='repair_reported') <> 1
   or (select version from public.repair_requests where id=pg_temp.tw_id('r_main')) <> 3 then
   raise exception 'FAIL: atomic result/photos/history/notification/version or replay duplicates'; end if;
end $$;

-- Simulate an authorized future continuation as TEST OWNER only. A second
-- result appends a round; the first result and its photos remain immutable.
update public.repair_requests set status='in_progress',version=version+1 where id=pg_temp.tw_id('r_main');
set local role authenticated;
select public.technician_submit_result(pg_temp.tw_id('r_main'),4,pg_temp.tw_id('result_second'),'Kết quả lần hai');
select pg_temp.tw_expect_error('update public.repair_results set content=''Edited old result'' where id=pg_temp.tw_id(''result_main'')','42501');
select pg_temp.tw_expect_error('delete from public.request_attachments where result_id=pg_temp.tw_id(''result_main'')','42501');
reset role;
do $$ begin
 if (select count(*) from public.repair_results where request_id=pg_temp.tw_id('r_main')) <> 2
   or (select content from public.repair_results where id=pg_temp.tw_id('result_main')) <> 'Đã sửa và kiểm tra'
   or (select count(*) from public.request_attachments where result_id=pg_temp.tw_id('result_main')) <> 5 then
   raise exception 'FAIL: previous result/photos changed in next round'; end if;
end $$;

-- Former technician cannot use owner staging SELECT to retain finalized photos.
update public.request_assignments set ended_at=clock_timestamp(),end_reason='transferred'
 where request_id=pg_temp.tw_id('r_main') and ended_at is null;
update public.repair_requests set assigned_technician_id=pg_temp.tw_id('other'),version=version+1 where id=pg_temp.tw_id('r_main');
select set_config('request.jwt.claim.sub',pg_temp.tw_id('technician')::text,true);
set local role authenticated;
do $$ declare v_count integer; begin
 if exists(select 1 from storage.objects where bucket_id='repair-images'
   and name like ('technician-results/' || auth.uid()::text || '/' || pg_temp.tw_id('r_main')::text || '/2/' || pg_temp.tw_id('result_main')::text || '/%')) then
   raise exception 'FAIL: former technician retained finalized image'; end if;
 if public._can_delete_technician_result(pg_temp.tw_photo('r_main',2,'result_main','photo1')->>'storage_path') then
   raise exception 'FAIL: former technician eligible to delete finalized image'; end if;
 perform pg_temp.tw_expect_error('select public.technician_submit_result(pg_temp.tw_id(''r_main''),2,pg_temp.tw_id(''result_main''),''Đã sửa và kiểm tra'')','P0002','JOB_NOT_FOUND');
end $$;
reset role;

rollback;
select 'PASS: technician start/result gates, version/state conflicts, start/transfer proof, 5-photo staging cap, ownership/metadata checks, atomic immutable result and idempotent replay; all fixtures rolled back' as result;
