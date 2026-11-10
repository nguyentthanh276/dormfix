-- Owner-run DF-014/015 regression. Passwordless random Auth fixtures only;
-- Storage rows are synthetic metadata, not uploads. Everything rolls back.
begin;
create temporary table student_confirmation_context(key text primary key,
  id uuid not null default gen_random_uuid()) on commit drop;
insert into student_confirmation_context(key) values
 ('a'),('b'),('admin'),('technician'),('other_technician'),('missing'),('room'),('new_room'),('category'),
 ('confirm'),('rework'),('foreign'),('invalid'),('legacy'),('wrong_assignment'),('wrong_result'),
 ('confirm_action'),('rework_action'),('second_action'),('legacy_action'),('bad_action'),
 ('photo_action'),('photo_request'),('photo1'),('photo2'),('photo3'),('photo4'),('photo5'),('photo6'),
 ('bad_photo'),('foreign_photo'),('extra_photo'),('other_assignment'),('other_result'),
 ('stale_action'),('stale_photo'),('empty_request'),('empty_action');
grant select on student_confirmation_context to authenticated,anon;
create function pg_temp.sc_id(p_key text) returns uuid language sql stable as $$
 select id from student_confirmation_context where key=p_key;
$$;
create function pg_temp.sc_photo(p_photo text,p_action text default 'photo_action',
 p_request text default 'photo_request',p_version integer default 8,p_user text default 'a',
 p_mime text default 'image/png',p_size integer default 128)
returns jsonb language sql stable as $$
 select jsonb_build_object('id',pg_temp.sc_id(p_photo)::text,
  'storage_path','student-feedback/'||pg_temp.sc_id(p_user)::text||'/'
    ||pg_temp.sc_id(p_request)::text||'/'||p_version::text||'/'||pg_temp.sc_id(p_action)::text
    ||'/'||pg_temp.sc_id(p_photo)::text||case p_mime
      when 'image/jpeg' then '.jpeg' when 'image/webp' then '.webp' else '.png' end,
  'mime_type',p_mime,'size_bytes',p_size);
$$;
create function pg_temp.sc_confirm(p_request text default 'confirm',p_version integer default 8,
 p_action text default 'confirm_action',p_note text default null)
returns jsonb language sql volatile as $$
 select public.student_confirm_result(pg_temp.sc_id(p_request),p_version,pg_temp.sc_id(p_action),p_note);
$$;
create function pg_temp.sc_rework(p_request text default 'rework',p_version integer default 8,
 p_action text default 'rework_action',p_reason text default ' Still leaking ',p_photos jsonb default '[]')
returns jsonb language sql volatile as $$
 select public.student_request_rework(pg_temp.sc_id(p_request),p_version,pg_temp.sc_id(p_action),p_reason,p_photos);
$$;
create function pg_temp.sc_expect_error(p_sql text,p_state text,p_message text default null)
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
 execute format('grant usage on schema %I to authenticated,anon',
  (select nspname from pg_namespace where oid=pg_my_temp_schema()));
end $$;
grant execute on function pg_temp.sc_id(text),
 pg_temp.sc_photo(text,text,text,integer,text,text,integer),pg_temp.sc_confirm(text,integer,text,text),
 pg_temp.sc_rework(text,integer,text,text,jsonb),pg_temp.sc_expect_error(text,text,text) to authenticated,anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text||'@student-confirmation-test.invalid',now(),now(),now()
from student_confirmation_context where key in ('a','b','admin','technician','other_technician');
insert into public.rooms(id,code,building)
select id,'SC-'||id::text,'Fixture building' from student_confirmation_context
where key in ('room','new_room');
insert into public.incident_categories(id,name)
values(pg_temp.sc_id('category'),'SC-'||pg_temp.sc_id('category')::text);
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'SC-'||id::text,'Confirmation '||key,id::text||'@student-confirmation-test.invalid','0900000000',
 case when key='admin' then 'admin'::public.app_role
  when key in ('technician','other_technician') then 'technician'::public.app_role
  else 'student'::public.app_role end,
 case when key in ('a','b') then pg_temp.sc_id('room') end,false
from student_confirmation_context where key in ('a','b','admin','technician','other_technician');
insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id,version)
select id,case when key='foreign' then pg_temp.sc_id('b') else pg_temp.sc_id('a') end,
 pg_temp.sc_id('room'),'Original room','Original building',pg_temp.sc_id('category'),
 'Original category','Confirmation fixture '||key,'Fixture description',
 'awaiting_confirmation',pg_temp.sc_id('technician'),8
from student_confirmation_context where key in
 ('confirm','rework','foreign','invalid','legacy','wrong_assignment','wrong_result','photo_request','empty_request');
insert into public.request_assignments(request_id,technician_id,assigned_by,
 request_code_snapshot,title_snapshot,room_code_snapshot)
select id,pg_temp.sc_id('technician'),pg_temp.sc_id('admin'),request_code,title,room_code_snapshot
from public.repair_requests where id in (select id from student_confirmation_context
 where key in ('confirm','rework','foreign','invalid','legacy','wrong_assignment','wrong_result','photo_request'));
insert into public.repair_results(request_id,assignment_id,submitted_by,content,request_version)
select a.request_id,a.id,a.technician_id,'Result fixture',
 case when r.id=pg_temp.sc_id('legacy') then null else 7 end
from public.request_assignments a join public.repair_requests r on r.id=a.request_id
where r.id in(select id from student_confirmation_context
 where key in ('confirm','rework','foreign','invalid','legacy','wrong_assignment','wrong_result','photo_request'));
-- Mismatched current assignment and a modern result with an unrelated version.
update public.request_assignments set technician_id=pg_temp.sc_id('other_technician')
where request_id=pg_temp.sc_id('wrong_assignment');
update public.repair_results set request_version=6 where request_id=pg_temp.sc_id('wrong_result');

-- RPC ACL, private helper ACL, pinned search paths, no direct business writes.
do $$ declare v_signature text; begin
 foreach v_signature in array array[
  'public.student_confirm_result(uuid,integer,uuid,text)',
  'public.student_request_rework(uuid,integer,uuid,text,jsonb)'
 ] loop
  if has_function_privilege('anon',v_signature,'EXECUTE')
   or not has_function_privilege('authenticated',v_signature,'EXECUTE') then
   raise exception 'FAIL: confirmation RPC ACL'; end if;
 end loop;
 foreach v_signature in array array[
  'public._student_confirmation_ready(public.repair_requests,integer)',
  'public._student_feedback_photo_path(text)',
  'public._student_resolve_result(uuid,integer,uuid,boolean,text,jsonb)'
 ] loop
  if has_function_privilege('anon',v_signature,'EXECUTE')
   or has_function_privilege('authenticated',v_signature,'EXECUTE') then
   raise exception 'FAIL: private confirmation helper exposed'; end if;
 end loop;
 if has_table_privilege('authenticated','public.repair_requests','UPDATE')
  or has_table_privilege('authenticated','public.request_feedback','INSERT')
  or has_table_privilege('authenticated','public.request_attachments','INSERT')
  or has_table_privilege('authenticated','public.request_history','INSERT')
  or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('student_confirm_result','student_request_rework',
    '_student_confirmation_ready','_student_feedback_photo_path','_student_resolve_result',
    '_can_upload_student_feedback_photo','_is_own_staged_student_feedback_photo','_can_delete_student_feedback_photo')
   and not ('search_path=""'=any(p.proconfig))) then
  raise exception 'FAIL: direct business writes or unpinned search path'; end if;
end $$;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.sc_expect_error('select pg_temp.sc_confirm()','42501');
select pg_temp.sc_expect_error('select pg_temp.sc_rework()','42501');
reset role;
set local role authenticated;
select pg_temp.sc_expect_error('select pg_temp.sc_confirm()','28000','AUTH_REQUIRED');
select pg_temp.sc_expect_error('select pg_temp.sc_rework()','28000','AUTH_REQUIRED');
reset role;
do $$ declare v_key text; begin
 foreach v_key in array array['admin','technician','missing'] loop
  perform set_config('request.jwt.claim.sub',pg_temp.sc_id(v_key)::text,true);
  set local role authenticated;
  perform pg_temp.sc_expect_error('select pg_temp.sc_confirm()','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sc_expect_error('select pg_temp.sc_rework()','42501','STUDENT_ACCESS_DENIED');
  reset role;
 end loop;
end $$;
select set_config('request.jwt.claim.sub',pg_temp.sc_id('a')::text,true);
do $$ declare v_state text; begin
 foreach v_state in array array['locked','revoked','password'] loop
  update public.profiles set status=case when v_state='password' then 'active'::public.account_status
    else v_state::public.account_status end,must_change_password=(v_state='password') where id=pg_temp.sc_id('a');
  set local role authenticated;
  perform pg_temp.sc_expect_error('select pg_temp.sc_confirm()','42501','STUDENT_ACCESS_DENIED');
  perform pg_temp.sc_expect_error('select pg_temp.sc_rework()','42501','STUDENT_ACCESS_DENIED');
  if public._can_upload_student_feedback_photo(pg_temp.sc_photo('photo1')->>'storage_path') then
   raise exception 'FAIL: blocked student upload'; end if;
  reset role;
 end loop;
 update public.profiles set status='active',must_change_password=false where id=pg_temp.sc_id('a');
end $$;

-- Ownership, input, state/version and current result guards leave no partial rows.
set local role authenticated;
do $$ declare v_sql text; begin
 perform pg_temp.sc_expect_error('select pg_temp.sc_confirm(''foreign'')','P0002','REQUEST_NOT_FOUND');
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''missing'')','P0002','REQUEST_NOT_FOUND');
 foreach v_sql in array array[
  'select public.student_confirm_result(null,8,pg_temp.sc_id(''bad_action''))',
  'select public.student_confirm_result(pg_temp.sc_id(''invalid''),null,pg_temp.sc_id(''bad_action''))',
  'select public.student_confirm_result(pg_temp.sc_id(''invalid''),0,pg_temp.sc_id(''bad_action''))',
  'select public.student_confirm_result(pg_temp.sc_id(''invalid''),2147483647,pg_temp.sc_id(''bad_action''))',
  'select public.student_confirm_result(pg_temp.sc_id(''invalid''),8,null)'
 ] loop perform pg_temp.sc_expect_error(v_sql,'22023','INVALID_CONFIRMATION_INPUT'); end loop;
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''invalid'',8,''bad_action'',null)',
  '22023','REWORK_REASON_REQUIRED');
 perform pg_temp.sc_expect_error(format('select pg_temp.sc_rework(''invalid'',8,''bad_action'',%L)',E'\n\t '),
  '22023','REWORK_REASON_REQUIRED');
 perform pg_temp.sc_expect_error('select pg_temp.sc_confirm(''invalid'',7,''bad_action'')','P0001','REQUEST_STATE_CONFLICT');
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''wrong_assignment'',8,''bad_action'')','P0001','CONFIRMATION_NOT_READY');
 perform pg_temp.sc_expect_error('select pg_temp.sc_confirm(''wrong_result'',8,''bad_action'')','P0001','CONFIRMATION_NOT_READY');
 perform pg_temp.sc_expect_error('select pg_temp.sc_confirm(''empty_request'',8,''empty_action'')','P0001','CONFIRMATION_NOT_READY');
 perform pg_temp.sc_expect_error('update public.repair_requests set status=''completed'' where id=pg_temp.sc_id(''confirm'')','42501');
 perform pg_temp.sc_expect_error('insert into public.request_feedback(request_id) values(pg_temp.sc_id(''confirm''))','42501');
end $$;
reset role;
update public.repair_requests set status='in_progress' where id=pg_temp.sc_id('invalid');
set local role authenticated;
select pg_temp.sc_expect_error('select pg_temp.sc_confirm(''invalid'',8,''bad_action'')','P0001','REQUEST_STATE_CONFLICT');
reset role;
update public.repair_requests set status='awaiting_confirmation' where id=pg_temp.sc_id('invalid');
do $$ begin
 if exists(select 1 from public.request_history where id in(pg_temp.sc_id('bad_action'),pg_temp.sc_id('empty_action')))
  or exists(select 1 from public.request_feedback where id=pg_temp.sc_id('bad_action')) then
  raise exception 'FAIL: rejected operation left partial audit/feedback'; end if;
end $$;

-- Former rooms remain eligible, even inactive/renamed rooms/categories.
update public.profiles set room_id=pg_temp.sc_id('new_room') where id=pg_temp.sc_id('a');
update public.rooms set is_active=false,code='SC-RENAMED-'||id::text where id=pg_temp.sc_id('room');
update public.incident_categories set is_active=false,name='SC-RENAMED-'||id::text where id=pg_temp.sc_id('category');
set local role authenticated;
do $$ declare v_first jsonb; v_again jsonb; begin
 v_first:=pg_temp.sc_confirm(); v_again:=pg_temp.sc_confirm();
 if v_first<>jsonb_build_object('request_id',pg_temp.sc_id('confirm'),'action_id',pg_temp.sc_id('confirm_action'),
   'status','completed','version',9,'feedback_id',null,'replayed',false)
  or v_again<>jsonb_set(v_first,'{replayed}','true') then raise exception 'FAIL: confirm receipt/replay'; end if;
 perform pg_temp.sc_expect_error('select pg_temp.sc_confirm(''confirm'',8,''confirm_action'',''Different'')',
  'P0001','ACTION_REPLAY_MISMATCH');
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''confirm'',8,''confirm_action'')',
  'P0001','ACTION_REPLAY_MISMATCH');
 perform pg_temp.sc_expect_error('select pg_temp.sc_confirm(''rework'',8,''confirm_action'')',
  'P0001','ACTION_REPLAY_MISMATCH');
 perform pg_temp.sc_expect_error('select pg_temp.sc_confirm(''confirm'',9,''second_action'')',
  'P0001','REQUEST_STATE_CONFLICT');
 v_first:=pg_temp.sc_rework(); v_again:=pg_temp.sc_rework('rework',8,'rework_action','Still leaking');
 if v_first->>'status'<>'awaiting_rework' or v_first->>'feedback_id'<>pg_temp.sc_id('rework_action')::text
  or (v_first->>'version')::integer<>9 or v_first->>'replayed'<>'false'
  or v_again<>jsonb_set(v_first,'{replayed}','true') then raise exception 'FAIL: rework receipt/normalized replay'; end if;
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''rework'',8,''rework_action'',''Different'')',
  'P0001','ACTION_REPLAY_MISMATCH');
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''rework'',9,''rework_action'')',
  'P0001','ACTION_REPLAY_MISMATCH');
 perform pg_temp.sc_confirm('legacy',8,'legacy_action');
end $$;
reset role;
do $$ begin
 if (select count(*) from public.request_history where request_id=pg_temp.sc_id('confirm'))<>1
  or (select completed_at is null or version<>9 or assigned_technician_id<>pg_temp.sc_id('technician')
      or room_code_snapshot<>'Original room' from public.repair_requests where id=pg_temp.sc_id('confirm'))
  or (select count(*) from public.notifications where request_id=pg_temp.sc_id('confirm')
      and recipient_id=pg_temp.sc_id('technician') and event_type='completed')<>1
  or (select count(*) from public.request_feedback where request_id=pg_temp.sc_id('confirm'))<>0
  or (select count(*) from public.request_history where request_id=pg_temp.sc_id('rework'))<>1
  or (select count(*) from public.request_feedback where id=pg_temp.sc_id('rework_action')
      and reason='Still leaking' and kind='rework' and submitted_by=pg_temp.sc_id('a'))<>1
  or (select status<>'awaiting_rework' or version<>9 or completed_at is not null
      or assigned_technician_id<>pg_temp.sc_id('technician') from public.repair_requests where id=pg_temp.sc_id('rework'))
  or (select count(*) from public.notifications where request_id=pg_temp.sc_id('rework')
      and recipient_id=pg_temp.sc_id('technician') and event_type='rework_requested')<>1 then
  raise exception 'FAIL: atomic audit/feedback/time/version/retained assignment/exactly-one notification'; end if;
end $$;

-- Replay stays the original action snapshot after another repair round.
update public.repair_requests set status='in_progress',version=10 where id=pg_temp.sc_id('rework');
insert into public.repair_results(request_id,assignment_id,submitted_by,content,request_version,submitted_at)
select request_id,id,technician_id,'Second result',10,clock_timestamp()
from public.request_assignments where request_id=pg_temp.sc_id('rework') and ended_at is null;
update public.repair_requests set status='awaiting_confirmation',version=11 where id=pg_temp.sc_id('rework');
set local role authenticated;
do $$ declare v_receipt jsonb; begin
 v_receipt:=pg_temp.sc_rework();
 if v_receipt->>'status'<>'awaiting_rework' or v_receipt->>'version'<>'9'
  or v_receipt->>'replayed'<>'true' then raise exception 'FAIL: original replay snapshot after later round'; end if;
 perform pg_temp.sc_confirm('rework',11,'second_action','Done');
 v_receipt:=pg_temp.sc_rework();
 if v_receipt->>'status'<>'awaiting_rework' or v_receipt->>'version'<>'9'
  or v_receipt->>'replayed'<>'true' then raise exception 'FAIL: replay after completion'; end if;
end $$;
reset role;
update public.profiles set status='locked' where id=pg_temp.sc_id('a');
set local role authenticated;
select pg_temp.sc_expect_error('select pg_temp.sc_rework()','42501','STUDENT_ACCESS_DENIED');
reset role;
update public.profiles set status='active' where id=pg_temp.sc_id('a');

-- Legacy NULL version cannot authorize a result for a previous assignment.
update public.request_assignments set technician_id=pg_temp.sc_id('technician'),ended_at=clock_timestamp()
where request_id=pg_temp.sc_id('wrong_assignment');
update public.repair_results set request_version=null where request_id=pg_temp.sc_id('wrong_assignment');
insert into public.request_assignments(request_id,technician_id,assigned_by,request_code_snapshot,title_snapshot,room_code_snapshot)
select id,assigned_technician_id,pg_temp.sc_id('admin'),request_code,title,room_code_snapshot
from public.repair_requests where id=pg_temp.sc_id('wrong_assignment');
set local role authenticated;
select pg_temp.sc_expect_error('select pg_temp.sc_confirm(''wrong_assignment'',8,''bad_action'')',
 'P0001','CONFIRMATION_NOT_READY');

-- Malformed manifest / missing blobs never change request state.
do $$ declare v_photos jsonb; begin
 foreach v_photos in array array['null'::jsonb,'{}'::jsonb,'[null]'::jsonb,'[{}]'::jsonb,
   jsonb_build_array(pg_temp.sc_photo('photo1')||jsonb_build_object('extra',true)),
   jsonb_build_array(pg_temp.sc_photo('photo1')||jsonb_build_object('size_bytes','128')),
   jsonb_build_array(pg_temp.sc_photo('photo1')||jsonb_build_object('size_bytes',0)),
   jsonb_build_array(pg_temp.sc_photo('photo1')||jsonb_build_object('size_bytes',5242881)),
   jsonb_build_array(pg_temp.sc_photo('photo1')||jsonb_build_object('mime_type','image/jpeg')),
   jsonb_build_array(pg_temp.sc_photo('photo1'),pg_temp.sc_photo('photo1')),
   jsonb_build_array(pg_temp.sc_photo('photo1','photo_action','photo_request',7)),
   jsonb_build_array(pg_temp.sc_photo('photo1','photo_action','photo_request',8,'b'))
 ] loop
  perform pg_temp.sc_expect_error(format('select pg_temp.sc_rework(''photo_request'',8,''photo_action'',''Still broken'',%L::jsonb)',v_photos),
   '22023','INVALID_FEEDBACK_PHOTOS');
 end loop;
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''photo_request'',8,''photo_action'',''Still broken'',jsonb_build_array(pg_temp.sc_photo(''photo1'')))',
  '22023','INVALID_FEEDBACK_PHOTOS');
end $$;

-- Staging policy accepts own current-version files and enforces five-file quota.
do $$ declare v_photo jsonb; v_key text; begin
 foreach v_key in array array['photo1','photo2','photo3','photo4','photo5'] loop
  v_photo:=pg_temp.sc_photo(v_key);
  if not public._can_upload_student_feedback_photo(v_photo->>'storage_path') then
   raise exception 'FAIL: valid staging denied'; end if;
  insert into storage.objects(bucket_id,name,owner_id,metadata)
  values('repair-images',v_photo->>'storage_path',auth.uid()::text,
   jsonb_build_object('mimetype',v_photo->>'mime_type','size',128));
 end loop;
 if public._can_upload_student_feedback_photo(pg_temp.sc_photo('photo6')->>'storage_path')
  or public._can_upload_student_feedback_photo(pg_temp.sc_photo('foreign_photo','photo_action','foreign')->>'storage_path')
  or public._can_upload_student_feedback_photo(pg_temp.sc_photo('photo6','photo_action','photo_request',7)->>'storage_path') then
  raise exception 'FAIL: quota/foreign/stale staging allowed'; end if;
 perform pg_temp.sc_expect_error('insert into storage.objects(bucket_id,name,owner_id,metadata) values(''repair-images'',pg_temp.sc_photo(''photo6'')->>''storage_path'',auth.uid()::text,''{}'')','42501');
 perform pg_temp.sc_expect_error('select pg_temp.sc_rework(''photo_request'',8,''photo_action'',''Still broken'',jsonb_build_array(pg_temp.sc_photo(''photo1'')))',
  '22023','INVALID_FEEDBACK_PHOTOS');
end $$;
reset role;

-- Metadata owner, MIME, size and attachment UUID collisions are authoritative.
update storage.objects set owner_id=pg_temp.sc_id('b')::text
where name=pg_temp.sc_photo('photo1')->>'storage_path';
set local role authenticated;
do $$ declare v_photos jsonb; begin
 select jsonb_agg(pg_temp.sc_photo(key) order by key) into v_photos
 from student_confirmation_context where key in('photo1','photo2','photo3','photo4','photo5');
 perform pg_temp.sc_expect_error(format('select pg_temp.sc_rework(''photo_request'',8,''photo_action'',''Still broken'',%L::jsonb)',v_photos),
  '22023','INVALID_FEEDBACK_PHOTOS');
end $$;
reset role;
update storage.objects set owner_id=pg_temp.sc_id('a')::text,metadata='{"size":128,"mimetype":"image/jpeg"}'::jsonb
where name=pg_temp.sc_photo('photo1')->>'storage_path';
set local role authenticated;
do $$ declare v_photos jsonb; begin
 select jsonb_agg(pg_temp.sc_photo(key)) into v_photos from student_confirmation_context
 where key in('photo1','photo2','photo3','photo4','photo5');
 perform pg_temp.sc_expect_error(format('select pg_temp.sc_rework(''photo_request'',8,''photo_action'',''Still broken'',%L::jsonb)',v_photos),
  '22023','INVALID_FEEDBACK_PHOTOS');
end $$;
reset role;
update storage.objects set metadata='{"size":129,"mimetype":"image/png"}'::jsonb
where name=pg_temp.sc_photo('photo1')->>'storage_path';
set local role authenticated;
do $$ declare v_photos jsonb; begin
 select jsonb_agg(pg_temp.sc_photo(key)) into v_photos from student_confirmation_context
 where key in('photo1','photo2','photo3','photo4','photo5');
 perform pg_temp.sc_expect_error(format('select pg_temp.sc_rework(''photo_request'',8,''photo_action'',''Still broken'',%L::jsonb)',v_photos),
  '22023','INVALID_FEEDBACK_PHOTOS');
end $$;
reset role;
update storage.objects set metadata='{"size":128,"mimetype":"image/png"}'::jsonb
where name=pg_temp.sc_photo('photo1')->>'storage_path';

-- All five photos finalize atomically, canonical manifest order replays, linked
-- objects cannot be overwritten/deleted. Provider prohibits raw SQL DELETE;
-- check its policy helper here; parent also tests actual Storage API removal.
set local role authenticated;
do $$ declare v_photos jsonb; v_reverse jsonb; v_receipt jsonb; begin
 select jsonb_agg(pg_temp.sc_photo(key) order by key),jsonb_agg(pg_temp.sc_photo(key) order by key desc)
 into v_photos,v_reverse from student_confirmation_context where key in('photo1','photo2','photo3','photo4','photo5');
 v_receipt:=pg_temp.sc_rework('photo_request',8,'photo_action','Still broken',v_photos);
 if v_receipt->>'replayed'<>'false' or pg_temp.sc_rework('photo_request',8,'photo_action','Still broken',v_reverse)
   <>jsonb_set(v_receipt,'{replayed}','true') then raise exception 'FAIL: photo rework/reordered replay'; end if;
 if public._can_upload_student_feedback_photo(pg_temp.sc_photo('photo6')->>'storage_path')
  or public._can_delete_student_feedback_photo(pg_temp.sc_photo('photo1')->>'storage_path')
  or public._is_own_staged_student_feedback_photo(pg_temp.sc_photo('photo1')->>'storage_path') then
  raise exception 'FAIL: committed photo staging/cleanup permitted'; end if;
 if (select count(*) from public.request_attachments where feedback_id=pg_temp.sc_id('photo_action'))<>5
  or (select count(*) from public.request_feedback where id=pg_temp.sc_id('photo_action'))<>1
  or (select count(*) from public.request_history where id=pg_temp.sc_id('photo_action'))<>1 then
  raise exception 'FAIL: atomic five photos/feedback/history'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.notifications where request_id=pg_temp.sc_id('photo_request')
   and event_type='rework_requested' and recipient_id=pg_temp.sc_id('technician'))<>1 then
  raise exception 'FAIL: photo rework emits exactly one KTV notification'; end if;
end $$;

-- Failed attempts remain cleanable after a competing action changes state.
insert into storage.objects(bucket_id,name,owner_id,metadata)
values('repair-images',pg_temp.sc_photo('stale_photo','stale_action','invalid')->>'storage_path',
 pg_temp.sc_id('a')::text,'{"size":128,"mimetype":"image/png"}');
update public.repair_requests set status='completed',version=9,completed_at=clock_timestamp()
where id=pg_temp.sc_id('invalid');
set local role authenticated;
do $$ begin
 if not public._can_delete_student_feedback_photo(pg_temp.sc_photo('stale_photo','stale_action','invalid')->>'storage_path')
  or public._can_upload_student_feedback_photo(pg_temp.sc_photo('stale_photo','stale_action','invalid')->>'storage_path') then
  raise exception 'FAIL: stale staging cleanup'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',pg_temp.sc_id('b')::text,true);
set local role authenticated;
do $$ begin
 if public._can_delete_student_feedback_photo(pg_temp.sc_photo('stale_photo','stale_action','invalid')->>'storage_path')
  or exists(select 1 from storage.objects where name=pg_temp.sc_photo('photo1')->>'storage_path') then
  raise exception 'FAIL: foreign staging cleanup/linked image read'; end if;
end $$;
reset role;
rollback;
select 'PASS: DF-014/015 student result confirmation/rework regression rolled back' as result;
