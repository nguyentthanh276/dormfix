-- Owner-run regression for DF-007–010. All users are passwordless synthetic
-- fixtures. Storage entries are metadata only, not physical file uploads.
-- Every row is rolled back; existing business data and profiles are untouched.
begin;

create temporary table student_request_context(key text primary key,
  id uuid not null default gen_random_uuid()) on commit drop;
insert into student_request_context(key) values
 ('a'),('b'),('admin'),('technician'),('missing'),('room'),('new_room'),
 ('category'),('inactive_category'),('text'),('foreign'),('photo'),('quota'),
 ('invalid'),('owner_bad'),('mime_bad'),('size_bad'),('extra_bad'),
 ('photo1'),('photo2'),('quota1'),('quota2'),('quota3'),('quota4'),('quota5'),('quota6'),
 ('bad_photo'),('foreign_photo'),('foreign_stage'),('extra_photo'),
 ('result1'),('result2'),('feedback1'),('assignment'),('result_photo'),('feedback_photo');
grant select on student_request_context to authenticated,anon;
create function pg_temp.sr_id(p_key text) returns uuid language sql stable as $$
 select id from student_request_context where key = p_key;
$$;
create function pg_temp.sr_photo(p_request text,p_photo text,
 p_mime text default 'image/png',p_size integer default 128,p_user text default 'a')
returns jsonb language sql stable as $$
 select jsonb_build_object('id',pg_temp.sr_id(p_photo)::text,
  'storage_path','student-requests/' || pg_temp.sr_id(p_user)::text || '/'
   || pg_temp.sr_id(p_request)::text || '/' || pg_temp.sr_id(p_photo)::text
   || case p_mime when 'image/jpeg' then '.jpg' when 'image/webp' then '.webp' else '.png' end,
  'mime_type',p_mime,'size_bytes',p_size);
$$;
create function pg_temp.sr_create(p_request text,p_photos jsonb default '[]'::jsonb)
returns jsonb language sql volatile as $$
 select public.student_create_request(pg_temp.sr_id(p_request),' Fixture title ',
  pg_temp.sr_id('category'),' Fixture description ',p_photos);
$$;
create function pg_temp.sr_expect_error(p_sql text,p_state text,p_message text default null)
returns void language plpgsql as $$
declare v_state text; v_message text;
begin
 begin execute p_sql;
 exception when others then
  get stacked diagnostics v_state = returned_sqlstate,v_message = message_text;
  if v_state <> p_state or (p_message is not null and v_message <> p_message) then
   raise exception 'FAIL: expected % %, got % %',p_state,p_message,v_state,v_message;
  end if;
  return;
 end;
 raise exception 'FAIL: expected error % %',p_state,p_message;
end $$;
do $$ begin
 execute format('grant usage on schema %I to authenticated,anon',
  (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;
grant execute on function pg_temp.sr_id(text),pg_temp.sr_photo(text,text,text,integer,text),
 pg_temp.sr_create(text,jsonb),pg_temp.sr_expect_error(text,text,text) to authenticated,anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text || '@student-request-test.invalid',now(),now(),now()
from student_request_context where key in ('a','b','admin','technician');
insert into public.rooms(id,code,building)
select id,'SR-' || id::text,case key when 'room' then 'Original building' else 'New building' end
from student_request_context where key in ('room','new_room');
insert into public.incident_categories(id,name,is_active)
select id,'SR-' || id::text,key='category'
from student_request_context where key in ('category','inactive_category');
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'SR-' || id::text,'Student request ' || key,
 id::text || '@student-request-test.invalid','0900000000',
 case key when 'admin' then 'admin'::public.app_role
  when 'technician' then 'technician'::public.app_role else 'student'::public.app_role end,
 case when key in ('a','b') then pg_temp.sr_id('room') end,false
from student_request_context where key in ('a','b','admin','technician');
insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description)
values(pg_temp.sr_id('foreign'),pg_temp.sr_id('b'),pg_temp.sr_id('room'),'Other room',
 'Other building',pg_temp.sr_id('category'),'Other category','Other title','Other description');

-- Public RPCs are guarded; helpers and direct business writes remain private.
do $$ declare v_signature text; begin
 foreach v_signature in array array[
  'public.student_list_categories()','public.student_list_requests()',
  'public.student_get_request(uuid)','public.student_create_request(uuid,text,uuid,text,jsonb)'
 ] loop
  if has_function_privilege('anon',v_signature,'EXECUTE')
    or not has_function_privilege('authenticated',v_signature,'EXECUTE') then
   raise exception 'FAIL: public request RPC ACL';
  end if;
 end loop;
 foreach v_signature in array array[
  'public._student_request_actor()',
  'public._student_request_summary(public.repair_requests)',
  'public._student_request_photo_path(text)'
 ] loop
  if has_function_privilege('anon',v_signature,'EXECUTE')
    or has_function_privilege('authenticated',v_signature,'EXECUTE') then
   raise exception 'FAIL: private helper executable by client';
  end if;
 end loop;
 if has_table_privilege('authenticated','public.repair_requests','INSERT')
  or has_table_privilege('authenticated','public.request_attachments','INSERT')
  or has_table_privilege('authenticated','public.request_history','INSERT')
  or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
     '_student_request_actor','_student_request_summary','_student_request_photo_path',
     'student_list_categories','student_list_requests','student_get_request',
     'student_create_request','_can_upload_student_request_photo',
     '_is_own_staged_student_request_photo','_can_delete_student_request_photo')
    and not ('search_path=""'=any(p.proconfig))) then
  raise exception 'FAIL: direct table write or unpinned search_path';
 end if;
end $$;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.sr_expect_error('select public.student_list_categories()','42501');
select pg_temp.sr_expect_error('select public.student_list_requests()','42501');
select pg_temp.sr_expect_error('select public.student_get_request(null)','42501');
select pg_temp.sr_expect_error('select pg_temp.sr_create(''text'')','42501');
reset role;
set local role authenticated;
select pg_temp.sr_expect_error('select public.student_list_categories()','28000','AUTH_REQUIRED');
select pg_temp.sr_expect_error('select public.student_list_requests()','28000','AUTH_REQUIRED');
select pg_temp.sr_expect_error('select public.student_get_request(null)','28000','AUTH_REQUIRED');
select pg_temp.sr_expect_error('select pg_temp.sr_create(''text'')','28000','AUTH_REQUIRED');
reset role;
do $$ declare v_key text; begin
 foreach v_key in array array['admin','technician','missing'] loop
  perform set_config('request.jwt.claim.sub',pg_temp.sr_id(v_key)::text,true);
  set local role authenticated;
  perform pg_temp.sr_expect_error('select public.student_list_categories()','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sr_expect_error('select public.student_list_requests()','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sr_expect_error('select public.student_get_request(null)','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sr_expect_error('select pg_temp.sr_create(''text'')','42501','STUDENT_ACCESS_DENIED');
  reset role;
 end loop;
end $$;
select set_config('request.jwt.claim.sub',pg_temp.sr_id('a')::text,true);
do $$ declare v_state text; begin
 foreach v_state in array array['locked','revoked','password'] loop
  update public.profiles set status=case when v_state='password' then 'active'::public.account_status
   else v_state::public.account_status end,must_change_password=(v_state='password')
  where id=pg_temp.sr_id('a');
  set local role authenticated;
  perform pg_temp.sr_expect_error('select public.student_list_categories()','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sr_expect_error('select public.student_list_requests()','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sr_expect_error('select public.student_get_request(null)','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sr_expect_error('select pg_temp.sr_create(''text'')','42501','STUDENT_ACCESS_DENIED');
  if public._can_upload_student_request_photo(pg_temp.sr_photo('photo','photo1')->>'storage_path') then
   raise exception 'FAIL: blocked student may upload';
  end if;
  reset role;
 end loop;
 update public.profiles set status='active',must_change_password=false where id=pg_temp.sr_id('a');
end $$;

-- Empty inbox, category filtering, required input, and opaque ownership checks.
set local role authenticated;
do $$ begin
 if public.student_list_requests()<>'[]'::jsonb then raise exception 'FAIL: empty own inbox'; end if;
 if not exists(select 1 from jsonb_array_elements(public.student_list_categories()) x
    where x->>'id'=pg_temp.sr_id('category')::text)
   or exists(select 1 from jsonb_array_elements(public.student_list_categories()) x
    where x->>'id'=pg_temp.sr_id('inactive_category')::text) then
  raise exception 'FAIL: active category filtering';
 end if;
 perform pg_temp.sr_expect_error('select public.student_get_request(pg_temp.sr_id(''foreign''))',
  'P0002','REQUEST_NOT_FOUND');
 perform pg_temp.sr_expect_error('select public.student_get_request(pg_temp.sr_id(''missing''))',
  'P0002','REQUEST_NOT_FOUND');
 perform pg_temp.sr_expect_error('select public.student_create_request(null,''x'',pg_temp.sr_id(''category''),''x'')',
  '22023','INVALID_REQUEST_INPUT');
 perform pg_temp.sr_expect_error('select public.student_create_request(pg_temp.sr_id(''invalid''),'' '',pg_temp.sr_id(''category''),''x'')',
  '22023','INVALID_REQUEST_INPUT');
 perform pg_temp.sr_expect_error(format('select public.student_create_request(pg_temp.sr_id(''invalid''),%L,pg_temp.sr_id(''category''),''x'')',E'\n\t '),
  '22023','INVALID_REQUEST_INPUT');
 perform pg_temp.sr_expect_error('select public.student_create_request(pg_temp.sr_id(''invalid''),''x'',null,''x'')',
  '22023','INVALID_REQUEST_INPUT');
 perform pg_temp.sr_expect_error('select public.student_create_request(pg_temp.sr_id(''invalid''),''x'',pg_temp.sr_id(''category''),null)',
  '22023','INVALID_REQUEST_INPUT');
 perform pg_temp.sr_expect_error('select public.student_create_request(pg_temp.sr_id(''invalid''),''x'',pg_temp.sr_id(''inactive_category''),''x'')',
  '22023','ACTIVE_CATEGORY_REQUIRED');
 perform pg_temp.sr_expect_error('select public.student_create_request(pg_temp.sr_id(''invalid''),''x'',pg_temp.sr_id(''missing''),''x'')',
  '22023','ACTIVE_CATEGORY_REQUIRED');
 perform pg_temp.sr_expect_error('insert into public.repair_requests(id) values(gen_random_uuid())','42501');
 perform pg_temp.sr_expect_error('insert into public.request_history(entity_type) values(''request'')','42501');
 perform pg_temp.sr_expect_error('insert into public.request_attachments(request_id) values(gen_random_uuid())','42501');
end $$;
reset role;
update public.rooms set is_active=false where id=pg_temp.sr_id('room');
set local role authenticated;
select pg_temp.sr_expect_error('select pg_temp.sr_create(''invalid'')','22023','ACTIVE_STUDENT_ROOM_REQUIRED');
reset role;
update public.rooms set is_active=true where id=pg_temp.sr_id('room');

-- Atomic text-only create and exact UUID replay; snapshots come from server.
set local role authenticated;
do $$ declare v_first jsonb; v_again jsonb; begin
 v_first:=pg_temp.sr_create('text'); v_again:=pg_temp.sr_create('text');
 if v_first<>v_again or v_first->>'id'<>pg_temp.sr_id('text')::text
  or v_first->>'student_id'<>auth.uid()::text or v_first->>'status'<>'pending'
  or (v_first->>'version')::integer<>1 or v_first->>'title'<>'Fixture title'
  or (select count(*) from public.request_history where request_id=pg_temp.sr_id('text'))<>1 then
  raise exception 'FAIL: text create/receipt/one audit/idempotency';
 end if;
 perform pg_temp.sr_expect_error('select public.student_create_request(pg_temp.sr_id(''text''),''Different'',pg_temp.sr_id(''category''),''Fixture description'')',
  'P0001','REQUEST_REPLAY_MISMATCH');
 perform pg_temp.sr_expect_error('select pg_temp.sr_create(''foreign'')','P0002','REQUEST_NOT_FOUND');
end $$;
reset role;
do $$ declare v_request public.repair_requests%rowtype; begin
 select * into strict v_request from public.repair_requests where id=pg_temp.sr_id('text');
 if v_request.room_id<>pg_temp.sr_id('room')
  or v_request.room_code_snapshot<>(select code from public.rooms where id=pg_temp.sr_id('room'))
  or v_request.building_snapshot<>'Original building'
  or v_request.category_name_snapshot<>(select name from public.incident_categories where id=pg_temp.sr_id('category'))
  or v_request.student_creation_fingerprint is null then raise exception 'FAIL: server snapshots/digest'; end if;
end $$;
update public.profiles set room_id=pg_temp.sr_id('new_room') where id=pg_temp.sr_id('a');
update public.rooms set code='SR-RENAMED-' || id::text where id=pg_temp.sr_id('room');
update public.incident_categories set name='SR-RENAMED-' || id::text,is_active=false
where id=pg_temp.sr_id('category');
-- Only fixture rows are changed to simulate later administration / future edit.
update public.repair_requests set title='Current edited title',description='Current edited description',
 status='assigned',assigned_technician_id=pg_temp.sr_id('technician'),version=2
where id=pg_temp.sr_id('text');
set local role authenticated;
do $$ declare v_detail jsonb; v_replayed jsonb; begin
 v_detail:=public.student_get_request(pg_temp.sr_id('text'));
 v_replayed:=pg_temp.sr_create('text');
 if v_detail->'request'->>'student_id'<>auth.uid()::text
  or v_detail->'request'->>'room_code' like 'SR-RENAMED-%'
  or v_detail->'request'->>'category_name' like 'SR-RENAMED-%'
  or v_detail->'technician'->>'full_name'<>'Student request technician'
  or v_replayed->>'title'<>'Current edited title' or v_replayed->>'status'<>'assigned'
  or (v_replayed->>'version')::integer<>2
  or jsonb_array_length(public.student_list_requests())<>1 then
  raise exception 'FAIL: old-room ownership/snapshots/contact or replay after edits';
 end if;
end $$;
reset role;
update public.incident_categories set is_active=true where id=pg_temp.sr_id('category');

-- Manifest shape and untrusted upload metadata are checked before any insert.
set local role authenticated;
do $$ declare v_photos jsonb; v_photo jsonb; v_key text; begin
 foreach v_photos in array array['null'::jsonb,'{}'::jsonb,'[null]'::jsonb,'[1]'::jsonb] loop
  perform pg_temp.sr_expect_error(format('select pg_temp.sr_create(''invalid'',%L::jsonb)',v_photos),
   '22023','INVALID_REQUEST_PHOTOS');
 end loop;
 v_photo:=pg_temp.sr_photo('photo','photo1');
 foreach v_photos in array array[
  jsonb_build_array(v_photo - 'id'),jsonb_build_array(v_photo || '{"extra":1}'::jsonb),
  jsonb_build_array(v_photo || '{"mime_type":"text/plain"}'::jsonb),
  jsonb_build_array(v_photo || '{"size_bytes":0}'::jsonb),
  jsonb_build_array(v_photo || '{"size_bytes":5242881}'::jsonb),
  jsonb_build_array(v_photo || '{"size_bytes":1.5}'::jsonb),
  jsonb_build_array(v_photo || '{"size_bytes":"128"}'::jsonb),
  jsonb_build_array(v_photo,v_photo),
  jsonb_build_array(pg_temp.sr_photo('photo','photo1','image/png',128,'b'))
 ] loop
  perform pg_temp.sr_expect_error(format('select pg_temp.sr_create(''photo'',%L::jsonb)',v_photos),
   '22023','INVALID_REQUEST_PHOTOS');
 end loop;
 v_photos:='[]'::jsonb;
 foreach v_key in array array['quota1','quota2','quota3','quota4','quota5','quota6'] loop
  v_photos:=v_photos || jsonb_build_array(pg_temp.sr_photo('quota',v_key));
 end loop;
 perform pg_temp.sr_expect_error(format('select pg_temp.sr_create(''quota'',%L::jsonb)',v_photos),
  '22023','INVALID_REQUEST_PHOTOS');
 perform pg_temp.sr_expect_error(format('select pg_temp.sr_create(''photo'',%L::jsonb)',jsonb_build_array(v_photo)),
  '22023','INVALID_REQUEST_PHOTOS');
end $$;

-- Storage policies permit only this student's own uncommitted staging prefix.
do $$ declare v_key text; v_photo jsonb; v_photos jsonb:='[]'::jsonb; begin
 foreach v_key in array array['quota1','quota2','quota3','quota4','quota5'] loop
  v_photo:=pg_temp.sr_photo('quota',v_key);
  insert into storage.objects(bucket_id,name,owner_id,metadata)
  values('repair-images',v_photo->>'storage_path',auth.uid()::text,'{"size":128,"mimetype":"image/png"}');
  v_photos:=v_photos || jsonb_build_array(v_photo);
 end loop;
 v_photo:=pg_temp.sr_photo('quota','quota6');
 perform pg_temp.sr_expect_error(format('insert into storage.objects(bucket_id,name,owner_id,metadata) values(''repair-images'',%L,%L,''{"size":128,"mimetype":"image/png"}'')',
  v_photo->>'storage_path',auth.uid()::text),'42501');
 perform pg_temp.sr_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',''bad/path.png'',%L)',auth.uid()::text),'42501');
 v_photo:=pg_temp.sr_photo('photo','foreign_photo','image/png',128,'b');
 perform pg_temp.sr_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',%L,%L)',
  v_photo->>'storage_path',auth.uid()::text),'42501');
 v_photo:=pg_temp.sr_photo('photo','photo1');
 perform pg_temp.sr_expect_error(format('insert into storage.objects(bucket_id,name,owner_id) values(''repair-images'',%L,%L)',
  v_photo->>'storage_path',pg_temp.sr_id('b')::text),'42501');
 if not public._can_delete_student_request_photo(pg_temp.sr_photo('quota','quota1')->>'storage_path')
  or not public._is_own_staged_student_request_photo(pg_temp.sr_photo('quota','quota1')->>'storage_path') then
  raise exception 'FAIL: own staged read/delete eligibility';
 end if;
 if public._can_delete_student_request_photo(pg_temp.sr_photo('quota','quota1','image/png',128,'b')->>'storage_path') then
  raise exception 'FAIL: foreign staging delete eligibility';
 end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
  and policyname='student_request_photo_staged_delete' and cmd='DELETE'
  and qual like '%owner_id%' and qual like '%_can_delete_student_request_photo%') then
  raise exception 'FAIL: staging delete policy absent';
 end if;
 perform pg_temp.sr_create('quota',v_photos);
 if public._can_delete_student_request_photo(pg_temp.sr_photo('quota','quota1')->>'storage_path')
  or public._is_own_staged_student_request_photo(pg_temp.sr_photo('quota','quota1')->>'storage_path')
  or public._can_upload_student_request_photo(pg_temp.sr_photo('quota','quota6')->>'storage_path') then
  raise exception 'FAIL: committed upload/delete/staging-read eligible';
 end if;
 if (select count(*) from storage.objects where bucket_id='repair-images'
  and name like ('student-requests/' || auth.uid()::text || '/' || pg_temp.sr_id('quota')::text || '/%'))<>5 then
  raise exception 'FAIL: committed owner cannot read linked objects';
 end if;
end $$;
reset role;

-- Malformed stored metadata is introduced by TEST OWNER only. The real Storage
-- API enforces bucket size/MIME limits as well as the finalization checks here.
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'repair-images',pg_temp.sr_photo(key,'bad_photo')->>'storage_path',
 case when key='owner_bad' then pg_temp.sr_id('b')::text else pg_temp.sr_id('a')::text end,
 case key when 'mime_bad' then '{"size":128,"mimetype":"image/jpeg"}'::jsonb
  when 'size_bad' then '{"size":129,"mimetype":"image/png"}'::jsonb
  else '{"size":128,"mimetype":"image/png"}'::jsonb end
from student_request_context where key in ('owner_bad','mime_bad','size_bad','extra_bad');
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.sr_photo('extra_bad','extra_photo')->>'storage_path',pg_temp.sr_id('a')::text,
 '{"size":128,"mimetype":"image/png"}');
set local role authenticated;
do $$ declare v_key text; begin
 foreach v_key in array array['owner_bad','mime_bad','size_bad','extra_bad'] loop
  perform pg_temp.sr_expect_error(format('select pg_temp.sr_create(%L,%L::jsonb)',v_key,
    jsonb_build_array(pg_temp.sr_photo(v_key,'bad_photo'))),
   '22023','INVALID_REQUEST_PHOTOS');
 end loop;
 if exists(select 1 from public.repair_requests where id in (
  pg_temp.sr_id('invalid'),pg_temp.sr_id('owner_bad'),pg_temp.sr_id('mime_bad'),
  pg_temp.sr_id('size_bad'),pg_temp.sr_id('extra_bad'))) then
  raise exception 'FAIL: invalid photos left a partial request';
 end if;
end $$;

-- Valid PNG + JPEG (including exact 5MB boundary), metadata links and one audit.
do $$ declare v_photo jsonb; v_photos jsonb; v_first jsonb; begin
 v_photos:=jsonb_build_array(pg_temp.sr_photo('photo','photo1'),
   pg_temp.sr_photo('photo','photo2','image/jpeg',5242880));
 for v_photo in select value from jsonb_array_elements(v_photos) loop
  insert into storage.objects(bucket_id,name,owner_id,metadata)
  values('repair-images',v_photo->>'storage_path',auth.uid()::text,
   jsonb_build_object('size',(v_photo->>'size_bytes')::integer,'mimetype',v_photo->>'mime_type'));
 end loop;
 v_first:=pg_temp.sr_create('photo',v_photos);
 if v_first<>pg_temp.sr_create('photo',jsonb_build_array(v_photos->1,v_photos->0))
  or (select count(*) from public.request_attachments where request_id=pg_temp.sr_id('photo'))<>2
  or (select count(*) from public.request_history where request_id=pg_temp.sr_id('photo'))<>1 then
  raise exception 'FAIL: photo create/reordered replay/duplicate metadata or history';
 end if;
 perform pg_temp.sr_expect_error('select pg_temp.sr_create(''photo'')','P0001','REQUEST_REPLAY_MISMATCH');
end $$;
reset role;

-- Full read retains every repair result and feedback round with their photos.
insert into public.request_assignments(id,request_id,technician_id,assigned_by,
 request_code_snapshot,title_snapshot,room_code_snapshot)
select pg_temp.sr_id('assignment'),r.id,pg_temp.sr_id('technician'),pg_temp.sr_id('admin'),
 r.request_code,r.title,r.room_code_snapshot from public.repair_requests r where r.id=pg_temp.sr_id('photo');
update public.repair_requests set assigned_technician_id=pg_temp.sr_id('technician'),
 status='awaiting_confirmation',version=2 where id=pg_temp.sr_id('photo');
insert into public.repair_results(id,request_id,assignment_id,submitted_by,content,submitted_at)
select id,pg_temp.sr_id('photo'),pg_temp.sr_id('assignment'),pg_temp.sr_id('technician'),
 key,case key when 'result1' then now()-interval '1 hour' else now() end
from student_request_context where key in ('result1','result2');
insert into public.request_feedback(id,request_id,kind,reason,submitted_by)
values(pg_temp.sr_id('feedback1'),pg_temp.sr_id('photo'),'rework','Fixture feedback',pg_temp.sr_id('a'));
insert into public.request_attachments(id,request_id,result_id,feedback_id,storage_path,mime_type,size_bytes,uploaded_by)
select id,pg_temp.sr_id('photo'),case key when 'result_photo' then pg_temp.sr_id('result1') end,
 case key when 'feedback_photo' then pg_temp.sr_id('feedback1') end,
 'fixture-read/' || id::text || '.png','image/png',128,
 case key when 'result_photo' then pg_temp.sr_id('technician') else pg_temp.sr_id('a') end
from student_request_context where key in ('result_photo','feedback_photo');
set local role authenticated;
do $$ declare v_detail jsonb; v_list jsonb; begin
 v_detail:=public.student_get_request(pg_temp.sr_id('photo'));
 v_list:=public.student_list_requests();
 if jsonb_array_length(v_detail->'results')<>2 or jsonb_array_length(v_detail->'feedback')<>1
  or jsonb_array_length(v_detail->'attachments')<>4 or jsonb_array_length(v_detail->'history')<>1
  or v_detail->'results'->0->>'id'<>pg_temp.sr_id('result1')::text
  or v_detail->'history'->0->>'actor_id'<>auth.uid()::text
  or exists(select 1 from jsonb_array_elements(v_list) x where x->>'student_id'<>auth.uid()::text)
  or (select count(*) from public.request_history where request_id=pg_temp.sr_id('photo'))<>1 then
  raise exception 'FAIL: full own read/all rounds/history identity';
 end if;
 if v_list->0->>'id'<>pg_temp.sr_id('photo')::text then
  raise exception 'FAIL: request ordering is not newest-created first';
 end if;
end $$;
reset role;

-- Another student cannot read details, claim IDs or see private linked images.
select set_config('request.jwt.claim.sub',pg_temp.sr_id('b')::text,true);
set local role authenticated;
select pg_temp.sr_expect_error('select public.student_get_request(pg_temp.sr_id(''photo''))','P0002','REQUEST_NOT_FOUND');
select pg_temp.sr_expect_error('select pg_temp.sr_create(''photo'')','P0002','REQUEST_NOT_FOUND');
do $$ begin
 if jsonb_array_length(public.student_list_requests())<>1
  or exists(select 1 from storage.objects where bucket_id='repair-images'
    and name like ('student-requests/' || pg_temp.sr_id('a')::text || '/%')) then
  raise exception 'FAIL: foreign inbox/photo isolation';
 end if;
end $$;
reset role;

rollback;
select 'PASS: student ownership/account gates, active room/category snapshots, exact-once text/photo create and replay after edits, 5-photo/private staging checks, immutable committed images and all result/feedback/history reads; fixtures rolled back' as result;
