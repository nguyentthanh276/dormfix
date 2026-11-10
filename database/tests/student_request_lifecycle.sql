-- DF-011/012/016 owner-run regression. All users and Storage metadata are
-- synthetic. The transaction is rolled back and no physical objects are touched.
begin;
create temporary table lifecycle_ids(key text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lifecycle_ids(key) values
 ('student'),('other'),('admin'),('tech'),('room'),('same_code_room'),('category'),('new_category'),('inactive_category'),
 ('edit'),('pending'),('assigned'),('started'),('foreign'),('complete'),('legacy'),('missing'),
 ('edit_action'),('pending_action'),('cancel_action'),('reopen_action'),('legacy_action'),('invalid_action'),
 ('keep'),('omit'),('new_photo'),('extra_photo'),('reopen_photo'),('result'),('result_photo'),('feedback'),('feedback_photo');
grant select on lifecycle_ids to anon,authenticated;
do $$ begin
  execute format('grant usage on schema %I to anon,authenticated',
    (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;
create function pg_temp.lc_id(p_key text) returns uuid language sql stable as $$
  select id from lifecycle_ids where key=p_key;
$$;
create function pg_temp.lc_photo(
 p_photo text,p_action text default 'edit_action',p_request text default 'edit',p_version integer default 4,
 p_prefix text default 'student-request-edits',p_owner text default 'student'
) returns jsonb language sql stable as $$
  select jsonb_build_object('id',pg_temp.lc_id(p_photo),'storage_path',p_prefix||'/'||pg_temp.lc_id(p_owner)::text
    ||'/'||pg_temp.lc_id(p_request)::text||'/'||p_version::text||'/'||pg_temp.lc_id(p_action)::text
    ||'/'||pg_temp.lc_id(p_photo)::text||'.png','mime_type','image/png','size_bytes',128);
$$;
create function pg_temp.lc_edit(
 p_key text default 'edit', p_version integer default 4, p_action text default 'edit_action',
 p_title text default ' Updated title ', p_category text default 'new_category',
 p_keep uuid[] default '{}'::uuid[], p_photos jsonb default '[]'
) returns jsonb language sql volatile as $$
  select public.student_edit_request(pg_temp.lc_id(p_key),p_version,pg_temp.lc_id(p_action),
    p_title,pg_temp.lc_id(p_category),' Updated description ',p_keep,p_photos);
$$;
create function pg_temp.lc_cancel(
 p_key text default 'assigned',p_version integer default 4,p_action text default 'cancel_action',
 p_reason text default ' No longer needed '
) returns jsonb language sql volatile as $$
  select public.student_cancel_request(pg_temp.lc_id(p_key),p_version,pg_temp.lc_id(p_action),p_reason);
$$;
create function pg_temp.lc_reopen(
 p_key text default 'complete',p_version integer default 4,p_action text default 'reopen_action',
 p_reason text default ' Problem returned ',p_photos jsonb default '[]'
) returns jsonb language sql volatile as $$
  select public.student_reopen_request(pg_temp.lc_id(p_key),p_version,pg_temp.lc_id(p_action),p_reason,p_photos);
$$;
create function pg_temp.lc_error(p_sql text,p_code text,p_message text default null)
returns void language plpgsql as $$
declare v_code text; v_message text;
begin
  begin execute p_sql;
  exception when others then
    get stacked diagnostics v_code=returned_sqlstate,v_message=message_text;
    if v_code<>p_code or (p_message is not null and p_message<>v_message) then
      raise exception 'FAIL: expected % %, got % %',p_code,p_message,v_code,v_message;
    end if;
    return;
  end;
  raise exception 'FAIL: expected % %',p_code,p_message;
end $$;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text||'@student-lifecycle.invalid',now(),now(),now()
from lifecycle_ids where key in ('student','other','admin','tech');
insert into public.rooms(id,code,building)
select id,'LC-'||id::text,'Lifecycle building' from lifecycle_ids where key in ('room','same_code_room');
insert into public.incident_categories(id,name,is_active)
select id,'LC-'||id::text,key<>'inactive_category' from lifecycle_ids
where key in ('category','new_category','inactive_category');
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'LC-'||id::text,'Lifecycle '||key,id::text||'@student-lifecycle.invalid','0900000000',
  case when key='admin' then 'admin'::public.app_role when key='tech' then 'technician'::public.app_role
    else 'student'::public.app_role end,
  case when key in ('student','other') then pg_temp.lc_id('room') end,false
from lifecycle_ids where key in ('student','other','admin','tech');

insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id,version,completed_at)
select id,case when key='foreign' then pg_temp.lc_id('other') else pg_temp.lc_id('student') end,
 pg_temp.lc_id('room'),'Original snapshot','Original building',pg_temp.lc_id('category'),
 'Original category','Lifecycle '||key,'Original description',
 case when key in ('assigned','started') then 'assigned'::public.repair_status
   when key in ('complete','legacy') then 'completed'::public.repair_status else 'pending'::public.repair_status end,
 case when key in ('assigned','started','complete','legacy') then pg_temp.lc_id('tech') end,4,
 case when key in ('complete','legacy') then now() end
from lifecycle_ids where key in ('edit','pending','assigned','started','foreign','complete','legacy');
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,started_at,
 request_code_snapshot,title_snapshot,room_code_snapshot)
select r.id,pg_temp.lc_id('tech'),pg_temp.lc_id('admin'),now()-interval '2 days',
 case when c.key<>'assigned' then now()-interval '1 day' end,r.request_code,r.title,r.room_code_snapshot
from public.repair_requests r join lifecycle_ids c on c.id=r.id where c.key in ('assigned','started','complete');
insert into public.repair_results(id,request_id,assignment_id,submitted_by,content,request_version)
select pg_temp.lc_id('result'),a.request_id,a.id,a.technician_id,'Earlier result',2
from public.request_assignments a where a.request_id=pg_temp.lc_id('complete');
insert into public.request_feedback(id,request_id,kind,reason,submitted_by)
values(pg_temp.lc_id('feedback'),pg_temp.lc_id('edit'),'rework','Historical feedback',pg_temp.lc_id('student'));
insert into public.request_attachments(id,request_id,feedback_id,storage_path,mime_type,size_bytes,uploaded_by)
select id,pg_temp.lc_id('edit'),case when key='feedback_photo' then pg_temp.lc_id('feedback') end,
 'student-requests/'||pg_temp.lc_id('student')::text||'/'||pg_temp.lc_id('edit')::text||'/'||id::text||'.png',
 'image/png',128,pg_temp.lc_id('student')
from lifecycle_ids where key in ('keep','omit','feedback_photo');
insert into public.request_attachments(id,request_id,result_id,storage_path,mime_type,size_bytes,uploaded_by)
values(pg_temp.lc_id('result_photo'),pg_temp.lc_id('complete'),pg_temp.lc_id('result'),
 'fixture-result/'||pg_temp.lc_id('result_photo')::text,'image/png',128,pg_temp.lc_id('tech'));
insert into storage.objects(bucket_id,name,owner_id,metadata)
select 'repair-images',storage_path,uploaded_by::text,'{"size":128,"mimetype":"image/png"}'::jsonb
from public.request_attachments where id in(pg_temp.lc_id('keep'),pg_temp.lc_id('omit'),pg_temp.lc_id('feedback_photo'));

-- ACL, authentication, ownership and backend capability gates.
do $$ declare v_signature text; begin
  foreach v_signature in array array[
    'public.student_edit_request(uuid,integer,uuid,text,uuid,text,uuid[],jsonb)',
    'public.student_cancel_request(uuid,integer,uuid,text)',
    'public.student_reopen_request(uuid,integer,uuid,text,jsonb)'
  ] loop
    if has_function_privilege('anon',v_signature,'EXECUTE')
       or not has_function_privilege('authenticated',v_signature,'EXECUTE') then
      raise exception 'FAIL: public lifecycle ACL'; end if;
  end loop;
  foreach v_signature in array array[
    'public._student_lifecycle_photo_path(text)','public._student_lifecycle_assignment_valid(public.repair_requests)',
    'public._student_in_original_room(public.repair_requests,uuid)','public._student_lifecycle_manifest(jsonb,text,text)',
    'public._student_lifecycle_validate_staging(uuid,jsonb,text,text)',
    'public._student_mutate_request(uuid,integer,uuid,text,text,uuid,text,uuid[],text,jsonb)'
  ] loop
    if has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('authenticated',v_signature,'EXECUTE') then
      raise exception 'FAIL: private lifecycle helper exposed'; end if;
  end loop;
  if has_table_privilege('authenticated','public.repair_requests','UPDATE')
    or has_table_privilege('authenticated','public.request_attachments','DELETE')
    or has_table_privilege('authenticated','public.request_assignments','UPDATE') then
    raise exception 'FAIL: direct write privileges'; end if;
end $$;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.lc_error('select pg_temp.lc_edit()','42501');
select pg_temp.lc_error('select pg_temp.lc_cancel()','42501');
select pg_temp.lc_error('select pg_temp.lc_reopen()','42501');
reset role;
set local role authenticated;
select pg_temp.lc_error('select pg_temp.lc_edit()','28000','AUTH_REQUIRED');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.lc_id('student')::text,true);
update public.profiles set must_change_password=true where id=pg_temp.lc_id('student');
set local role authenticated;
select pg_temp.lc_error('select pg_temp.lc_cancel()','42501','STUDENT_ACCESS_DENIED');
reset role;
update public.profiles set must_change_password=false where id=pg_temp.lc_id('student');
set local role authenticated;
do $$ begin
  if (public.student_get_request(pg_temp.lc_id('edit'))->>'can_edit') is distinct from 'true'
     or (public.student_get_request(pg_temp.lc_id('assigned'))->>'can_cancel') is distinct from 'true'
     or (public.student_get_request(pg_temp.lc_id('started'))->>'can_cancel') is distinct from 'false'
     or (public.student_get_request(pg_temp.lc_id('complete'))->>'can_reopen') is distinct from 'true'
     or (public.student_get_request(pg_temp.lc_id('edit'))->>'can_reopen') is distinct from 'false' then
    raise exception 'FAIL: capabilities do not match server constraints'; end if;
  perform pg_temp.lc_error('select pg_temp.lc_edit(''foreign'')','P0002','REQUEST_NOT_FOUND');
  perform pg_temp.lc_error('select pg_temp.lc_cancel(''missing'')','P0002','REQUEST_NOT_FOUND');
  perform pg_temp.lc_error('select pg_temp.lc_reopen(''foreign'')','P0002','REQUEST_NOT_FOUND');
  perform pg_temp.lc_error('select pg_temp.lc_edit(''assigned'')','P0001','REQUEST_STATE_CONFLICT');
  perform pg_temp.lc_error('select pg_temp.lc_edit(''edit'',3)','P0001','REQUEST_STATE_CONFLICT');
  perform pg_temp.lc_error('select pg_temp.lc_edit(''edit'',4,''edit_action'',''  '')','22023','INVALID_REQUEST_INPUT');
  perform pg_temp.lc_error('select pg_temp.lc_edit(''edit'',4,''edit_action'',''Updated'',''inactive_category'')','22023','ACTIVE_CATEGORY_REQUIRED');
  perform pg_temp.lc_error('select pg_temp.lc_cancel(''started'')','P0001','REQUEST_ASSIGNMENT_CONFLICT');
  perform pg_temp.lc_error('select pg_temp.lc_cancel(''assigned'',4,''cancel_action'','' '')','22023','CANCELLATION_REASON_REQUIRED');
  perform pg_temp.lc_error('select pg_temp.lc_reopen(''complete'',4,''reopen_action'',null)','22023','REOPEN_REASON_REQUIRED');
end $$;
reset role;

-- A formerly occupied room is rejected even when its historical code matches a
-- different current room. A renamed room with the same ID still qualifies.
update public.rooms set code='Renamed original '||id::text where id=pg_temp.lc_id('room');
update public.rooms set code='Original snapshot' where id=pg_temp.lc_id('same_code_room');
update public.profiles set room_id=pg_temp.lc_id('same_code_room') where id=pg_temp.lc_id('student');
set local role authenticated;
do $$ begin
  if (public.student_get_request(pg_temp.lc_id('complete'))->>'can_reopen') is distinct from 'false'
     or public._can_upload_student_lifecycle_photo(
       pg_temp.lc_photo('reopen_photo','reopen_action','complete',4,'student-feedback')->>'storage_path') then
    raise exception 'FAIL: former-room reopen capability/staging'; end if;
  perform pg_temp.lc_error('select pg_temp.lc_reopen()','P0001','REOPEN_ROOM_MISMATCH');
end $$;
reset role;
update public.profiles set room_id=pg_temp.lc_id('room') where id=pg_temp.lc_id('student');
update public.rooms set is_active=false where id=pg_temp.lc_id('room');
set local role authenticated;
select pg_temp.lc_error('select pg_temp.lc_reopen()','P0001','REOPEN_ROOM_MISMATCH');
reset role;
update public.rooms set is_active=true where id=pg_temp.lc_id('room');

-- Edit retains chosen initial photos, hides omitted links, preserves historical
-- feedback photos and atomically binds only correctly staged metadata.
set local role authenticated;
do $$ declare v_photo jsonb:=pg_temp.lc_photo('new_photo'); begin
  perform pg_temp.lc_error('select pg_temp.lc_edit(p_keep=>array[pg_temp.lc_id(''feedback_photo'')])','22023','INVALID_REQUEST_PHOTOS');
  perform pg_temp.lc_error('select pg_temp.lc_edit(p_keep=>array[pg_temp.lc_id(''keep''),pg_temp.lc_id(''keep'')])','22023','INVALID_REQUEST_PHOTOS');
  perform pg_temp.lc_error('select pg_temp.lc_edit(p_photos=>jsonb_build_array(pg_temp.lc_photo(''new_photo'')))','22023','INVALID_REQUEST_PHOTOS');
  perform pg_temp.lc_error('select pg_temp.lc_edit(p_photos=>jsonb_build_array(pg_temp.lc_photo(''new_photo'',''edit_action'',''edit'',4,''student-request-edits'',''other'')))',
    '22023','INVALID_REQUEST_PHOTOS');
  if public._can_upload_student_lifecycle_photo(pg_temp.lc_photo('new_photo','edit_action','edit',3)->>'storage_path')
     or public._can_upload_student_lifecycle_photo(pg_temp.lc_photo('new_photo','edit_action','foreign')->>'storage_path') then
    raise exception 'FAIL: stale/foreign edit upload'; end if;
  insert into storage.objects(bucket_id,name,owner_id,metadata)
  values('repair-images',v_photo->>'storage_path',auth.uid()::text,'{"size":128,"mimetype":"image/png"}');
  if not public._can_delete_student_edit_photo(v_photo->>'storage_path') then
    raise exception 'FAIL: staged edit photo cannot be cleaned'; end if;
  perform pg_temp.lc_error('select pg_temp.lc_edit()','22023','INVALID_REQUEST_PHOTOS');
  perform pg_temp.lc_error('select pg_temp.lc_edit(p_photos=>jsonb_build_array(pg_temp.lc_photo(''new_photo'')||jsonb_build_object(''size_bytes'',129)))',
    '22023','INVALID_REQUEST_PHOTOS');
end $$;
reset role;
do $$ begin
  if (select version from public.repair_requests where id=pg_temp.lc_id('edit'))<>4
    or exists(select 1 from public.request_history where id=pg_temp.lc_id('edit_action')) then
    raise exception 'FAIL: invalid edit partially mutated data'; end if;
end $$;
set local role authenticated;
do $$ declare v_photo jsonb:=pg_temp.lc_photo('new_photo'); v_first jsonb; v_replay jsonb; begin
  v_first:=pg_temp.lc_edit(p_keep=>array[pg_temp.lc_id('keep')],p_photos=>jsonb_build_array(v_photo));
  v_replay:=pg_temp.lc_edit(p_keep=>array[pg_temp.lc_id('keep')],p_photos=>jsonb_build_array(v_photo));
  if v_first is distinct from jsonb_build_object('request_id',pg_temp.lc_id('edit'),'action_id',pg_temp.lc_id('edit_action'),
    'status','pending','version',5,'feedback_id',null,'replayed',false)
    or v_replay is distinct from jsonb_set(v_first,'{replayed}','true')
    or public._can_delete_student_edit_photo(v_photo->>'storage_path')
    or (select count(*) from public.request_attachments where request_id=pg_temp.lc_id('edit'))<>3
    or exists(select 1 from storage.objects where name like '%'||pg_temp.lc_id('omit')::text||'.png')
    or not exists(select 1 from storage.objects where name=v_photo->>'storage_path') then
    raise exception 'FAIL: edit receipt/photo retention/immutability'; end if;
  perform pg_temp.lc_error('select pg_temp.lc_edit(p_title=>''Different'')','P0001','ACTION_REPLAY_MISMATCH');
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.repair_requests where id=pg_temp.lc_id('edit')
    and title='Updated title' and description='Updated description' and room_code_snapshot='Original snapshot'
    and building_snapshot='Original building' and room_id=pg_temp.lc_id('room')
    and category_id=pg_temp.lc_id('new_category') and category_name_snapshot='LC-'||pg_temp.lc_id('new_category')::text)
    or not exists(select 1 from storage.objects where name like '%'||pg_temp.lc_id('omit')::text||'.png')
    or not exists(select 1 from public.request_attachments where id=pg_temp.lc_id('feedback_photo')
      and feedback_id=pg_temp.lc_id('feedback'))
    or (select count(*) from public.request_history where id=pg_temp.lc_id('edit_action'))<>1 then
    raise exception 'FAIL: atomic edit snapshots, old object retained, historical photo retained'; end if;
end $$;

-- Cancel both allowed states. Assigned cancellation closes the assignment and
-- preserves exactly one generic notification and a redacted history entry.
set local role authenticated;
do $$ declare v_first jsonb; begin
  v_first:=pg_temp.lc_cancel();
  if v_first is distinct from jsonb_build_object('request_id',pg_temp.lc_id('assigned'),'action_id',pg_temp.lc_id('cancel_action'),
    'status','cancelled','version',5,'feedback_id',null,'replayed',false)
    or pg_temp.lc_cancel() is distinct from jsonb_set(v_first,'{replayed}','true') then
    raise exception 'FAIL: cancellation receipt/retry'; end if;
  perform pg_temp.lc_cancel('pending',4,'pending_action');
  perform pg_temp.lc_error('select pg_temp.lc_cancel(''assigned'',4,''invalid_action'')','P0001','REQUEST_STATE_CONFLICT');
end $$;
reset role;
do $$ begin
  if (select count(*) from public.notifications where request_id=pg_temp.lc_id('assigned')
    and recipient_id=pg_temp.lc_id('tech') and event_type='cancelled')<>1
    or exists(select 1 from public.notifications where request_id in (pg_temp.lc_id('assigned'),pg_temp.lc_id('pending'))
      and event_type='transferred_out')
    or not exists(select 1 from public.request_assignments where request_id=pg_temp.lc_id('assigned') and ended_at is not null)
    or not exists(select 1 from public.request_history where id=pg_temp.lc_id('cancel_action')
      and old_status='assigned' and new_status='cancelled' and note='No longer needed') then
    raise exception 'FAIL: cancel assignment/audit/exact notification'; end if;
end $$;
select set_config('request.jwt.claim.sub',pg_temp.lc_id('tech')::text,true);
set local role authenticated;
do $$ begin
  if not exists(select 1 from jsonb_array_elements(public.technician_list_notifications()) n
    where n->>'event_type'='cancelled' and n->>'can_open_detail'='false')
    or not exists(select 1 from jsonb_array_elements(public.technician_list_work_history()) h
      where h->>'title'='Lifecycle assigned' and h->>'can_open_detail'='false' and h->>'request_id' is null) then
    raise exception 'FAIL: former technician loses redacted cancellation history or notification'; end if;
end $$;
reset role;

-- Reopen queues the original request, keeping completed result/history and
-- linking optional feedback images, with an original receipt after later edits.
select set_config('request.jwt.claim.sub',pg_temp.lc_id('student')::text,true);
set local role authenticated;
do $$ declare v_photo jsonb:=pg_temp.lc_photo('reopen_photo','reopen_action','complete',4,'student-feedback');
  v_first jsonb;
begin
  insert into storage.objects(bucket_id,name,owner_id,metadata)
  values('repair-images',v_photo->>'storage_path',auth.uid()::text,'{"size":128,"mimetype":"image/png"}');
  v_first:=pg_temp.lc_reopen(p_photos=>jsonb_build_array(v_photo));
  if v_first is distinct from jsonb_build_object('request_id',pg_temp.lc_id('complete'),'action_id',pg_temp.lc_id('reopen_action'),
    'status','pending','version',5,'feedback_id',pg_temp.lc_id('reopen_action'),'replayed',false)
    or public._can_delete_student_feedback_photo(v_photo->>'storage_path') then
    raise exception 'FAIL: reopen receipt or committed image cleanup'; end if;
  perform pg_temp.lc_edit('complete',5,'invalid_action');
  if pg_temp.lc_reopen(p_photos=>jsonb_build_array(v_photo)) is distinct from jsonb_set(v_first,'{replayed}','true') then
    raise exception 'FAIL: reopen replay does not retain original version'; end if;
  perform pg_temp.lc_reopen('legacy',4,'legacy_action');
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.repair_requests where id=pg_temp.lc_id('complete')
    and assigned_technician_id is null and status='pending' and completed_at is null and version=6)
    or not exists(select 1 from public.request_assignments where request_id=pg_temp.lc_id('complete') and ended_at is not null)
    or not exists(select 1 from public.repair_results where id=pg_temp.lc_id('result'))
    or not exists(select 1 from public.request_attachments where id=pg_temp.lc_id('result_photo'))
    or not exists(select 1 from public.request_feedback where id=pg_temp.lc_id('reopen_action') and kind='reopen'
      and reason='Problem returned' and submitted_by=pg_temp.lc_id('student'))
    or not exists(select 1 from public.request_attachments where id=pg_temp.lc_id('reopen_photo')
      and feedback_id=pg_temp.lc_id('reopen_action'))
    or (select count(*) from public.request_history where id=pg_temp.lc_id('reopen_action')
      and old_status='completed' and new_status='pending')<>1 then
    raise exception 'FAIL: atomic reopen assignment/result/feedback/photo/history'; end if;
end $$;
rollback;
select 'PASS: DF-011/012/016 student edit, cancellation and reopen regression rolled back' as result;
