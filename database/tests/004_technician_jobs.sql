-- Run manually as the SQL Editor/database owner after migration 004.
-- Creates synthetic Auth rows WITHOUT passwords, sessions or Auth API changes.
-- JWT subjects are simulated with SET LOCAL ROLE; every fixture is rolled back.
-- Storage fixtures are metadata only: this does not test real image downloads.
begin;

create temporary table technician_jobs_test_context (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;
insert into technician_jobs_test_context (key) values
 ('admin'), ('student'), ('technician'), ('other_technician'), ('room'), ('category'),
 ('request_other'), ('assignment_old'), ('assignment_current'),
 ('result_old'), ('result_current'), ('feedback_rework'), ('feedback_reopen'),
 ('attachment_request'), ('attachment_result'), ('attachment_feedback'), ('attachment_other');
insert into technician_jobs_test_context (key)
select 'request_' || status::text from unnest(enum_range(null::public.repair_status)) status;
grant select on technician_jobs_test_context to authenticated, anon;

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@technician-test.invalid', now(), now(), now()
from technician_jobs_test_context where key in ('admin', 'student', 'technician', 'other_technician');
insert into public.rooms (id, code, building)
select id, 'CURRENT-' || id::text, 'Current building' from technician_jobs_test_context where key = 'room';
insert into public.incident_categories (id, name)
select id, 'Current category ' || id::text from technician_jobs_test_context where key = 'category';
insert into public.profiles (id, identity_code, full_name, email, phone, role, room_id, must_change_password)
select c.id, 'TJ-' || c.id::text,
  case c.key when 'admin' then 'Fixture administrator' when 'student' then 'Fixture student'
    when 'technician' then 'Fixture current technician' else 'Fixture former technician' end,
  c.id::text || '@technician-test.invalid', '0900000000',
  case c.key when 'admin' then 'admin'::public.app_role when 'student' then 'student'::public.app_role
    else 'technician'::public.app_role end,
  case when c.key = 'student' then (select id from technician_jobs_test_context where key = 'room') end,
  false
from technician_jobs_test_context c where c.key in ('admin', 'student', 'technician', 'other_technician');

-- Empty arrays are part of the API contract, not null.
select set_config('request.jwt.claim.sub', (select id::text from technician_jobs_test_context where key = 'technician'), true);
set local role authenticated;
do $$ begin
  if public.technician_list_jobs() is distinct from '[]'::jsonb then raise exception 'FAIL: empty job list'; end if;
end $$;
reset role;

insert into public.repair_requests
 (id, student_id, room_id, room_code_snapshot, building_snapshot, category_id,
  category_name_snapshot, title, description, status, assigned_technician_id, created_at, updated_at)
select c.id,
 (select id from technician_jobs_test_context where key = 'student'),
 (select id from technician_jobs_test_context where key = 'room'), 'Old room A101', 'Old building',
 (select id from technician_jobs_test_context where key = 'category'), 'Category at creation',
 'Fixture ' || s.status::text, 'Description ' || s.status::text, s.status,
 (select id from technician_jobs_test_context where key = 'technician'),
 '2026-01-01 00:00:00+00'::timestamptz + s.ordinal * interval '1 hour',
 '2026-01-01 00:00:00+00'::timestamptz + s.ordinal * interval '1 hour'
from unnest(enum_range(null::public.repair_status)) with ordinality s(status, ordinal)
join technician_jobs_test_context c on c.key = 'request_' || s.status::text;
insert into public.repair_requests
 (id, student_id, room_id, room_code_snapshot, building_snapshot, category_id,
  category_name_snapshot, title, description, status, assigned_technician_id)
select c.id,
 (select id from technician_jobs_test_context where key = 'student'),
 (select id from technician_jobs_test_context where key = 'room'), 'Other room', 'Other building',
 (select id from technician_jobs_test_context where key = 'category'), 'Other category',
 'Other technician only', 'Must never leak', 'assigned',
 (select id from technician_jobs_test_context where key = 'other_technician')
from technician_jobs_test_context c where c.key = 'request_other';

insert into public.request_assignments
 (id, request_id, technician_id, assigned_by, assigned_at, ended_at, transfer_reason, end_reason,
  request_code_snapshot, title_snapshot, room_code_snapshot)
select c.id, r.id,
 (select id from technician_jobs_test_context where key = case when c.key = 'assignment_old' then 'other_technician' else 'technician' end),
 (select id from technician_jobs_test_context where key = 'admin'),
 case when c.key = 'assignment_old' then '2025-12-01'::timestamptz else '2025-12-03'::timestamptz end,
 case when c.key = 'assignment_old' then '2025-12-02'::timestamptz end,
 case when c.key = 'assignment_old' then 'Transfer explanation' end,
 case when c.key = 'assignment_old' then 'transferred' end,
 r.request_code, r.title, r.room_code_snapshot
from technician_jobs_test_context c
join public.repair_requests r on r.id = (select id from technician_jobs_test_context where key = 'request_awaiting_rework')
where c.key in ('assignment_old', 'assignment_current');
insert into public.repair_results (id, request_id, assignment_id, submitted_by, content, submitted_at)
select c.id,
 (select id from technician_jobs_test_context where key = 'request_awaiting_rework'),
 (select id from technician_jobs_test_context where key = case when c.key = 'result_old' then 'assignment_old' else 'assignment_current' end),
 (select id from technician_jobs_test_context where key = case when c.key = 'result_old' then 'other_technician' else 'technician' end),
 case when c.key = 'result_old' then 'Previous result' else 'Current result' end,
 case when c.key = 'result_old' then '2025-12-01 12:00:00+00'::timestamptz else '2025-12-04'::timestamptz end
from technician_jobs_test_context c where c.key in ('result_old', 'result_current');
insert into public.request_feedback (id, request_id, kind, reason, submitted_by, created_at)
select c.id, (select id from technician_jobs_test_context where key = 'request_awaiting_rework'),
 case when c.key = 'feedback_reopen' then 'reopen' else 'rework' end,
 case when c.key = 'feedback_reopen' then 'Previous reopen reason' else 'Still broken' end,
 (select id from technician_jobs_test_context where key = 'student'),
 case when c.key = 'feedback_reopen' then '2025-12-02'::timestamptz else '2025-12-05'::timestamptz end
from technician_jobs_test_context c where c.key in ('feedback_reopen', 'feedback_rework');
insert into public.request_attachments
 (id, request_id, result_id, feedback_id, storage_path, mime_type, size_bytes, uploaded_by, created_at)
select c.id,
 (select id from technician_jobs_test_context where key = case when c.key = 'attachment_other' then 'request_other' else 'request_awaiting_rework' end),
 case when c.key = 'attachment_result' then (select id from technician_jobs_test_context where key = 'result_current') end,
 case when c.key = 'attachment_feedback' then (select id from technician_jobs_test_context where key = 'feedback_rework') end,
 'technician-test/' || c.id::text || '.png', 'image/png', 128,
 (select id from technician_jobs_test_context where key = 'student'),
 case c.key when 'attachment_request' then '2025-12-01'::timestamptz
   when 'attachment_result' then '2025-12-04'::timestamptz else '2025-12-05'::timestamptz end
from technician_jobs_test_context c where c.key like 'attachment_%';
insert into storage.objects (id, bucket_id, name, metadata)
select a.id, 'repair-images', a.storage_path, jsonb_build_object('mimetype', a.mime_type, 'size', a.size_bytes)
from public.request_attachments a join technician_jobs_test_context c on c.id = a.id;
-- Unregistered metadata is not readable, even in the right bucket.
insert into storage.objects (bucket_id, name)
select 'repair-images', 'technician-test/' || id::text || '-unregistered.png'
from technician_jobs_test_context where key = 'room';
insert into public.request_history
 (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
select r.id, 'request', r.id, 'created',
 (select id from technician_jobs_test_context where key = 'student'), null, 'pending', null, '2025-12-01'
from public.repair_requests r where r.id = (select id from technician_jobs_test_context where key = 'request_awaiting_rework');
insert into public.request_history
 (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
select r.id, 'request', r.id, 'transferred',
 (select id from technician_jobs_test_context where key = 'admin'), 'in_progress', 'in_progress',
 'Transfer audit note', '2025-12-03'
from public.repair_requests r where r.id = (select id from technician_jobs_test_context where key = 'request_awaiting_rework');
-- A different request's timeline must not appear in the authorized detail.
insert into public.request_history (request_id, entity_type, entity_id, action, actor_id, occurred_at)
select id, 'request', id, 'foreign_request_history',
 (select id from technician_jobs_test_context where key = 'admin'), '2025-12-01'
from technician_jobs_test_context where key = 'request_other';

-- Anon has no EXECUTE grant. Authenticated without an identity gets AUTH_REQUIRED.
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$ begin
  begin perform public.technician_list_jobs(); raise exception 'FAIL: anon list';
  exception when insufficient_privilege then null; end;
  begin perform public.technician_get_job(null); raise exception 'FAIL: anon detail';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role authenticated;
do $$ begin
  begin perform public.technician_list_jobs(); raise exception 'FAIL: missing identity list';
  exception when invalid_authorization_specification then
    if sqlerrm <> 'AUTH_REQUIRED' then raise; end if;
  end;
  begin perform public.technician_get_job(null); raise exception 'FAIL: missing identity detail';
  exception when invalid_authorization_specification then
    if sqlerrm <> 'AUTH_REQUIRED' then raise; end if;
  end;
end $$;
reset role;

-- A JWT subject without a profile must fail the role check (NULL is not a role).
select set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
set local role authenticated;
do $$ begin
  begin perform public.technician_list_jobs(); raise exception 'FAIL: missing profile list';
  exception when insufficient_privilege then if sqlerrm <> 'TECHNICIAN_ACCESS_DENIED' then raise; end if; end;
  begin perform public.technician_get_job(null); raise exception 'FAIL: missing profile detail';
  exception when insufficient_privilege then if sqlerrm <> 'TECHNICIAN_ACCESS_DENIED' then raise; end if; end;
end $$;
reset role;

-- Neither Admin nor student may use these technician-specific endpoints.
do $$ declare v_key text; begin
  foreach v_key in array array['admin', 'student'] loop
    perform set_config('request.jwt.claim.sub', (select id::text from technician_jobs_test_context where key = v_key), true);
    set local role authenticated;
    begin perform public.technician_list_jobs(); raise exception 'FAIL: non-technician list';
    exception when insufficient_privilege then
      if sqlerrm <> 'TECHNICIAN_ACCESS_DENIED' then raise; end if;
    end;
    begin perform public.technician_get_job((select id from technician_jobs_test_context where key = 'request_awaiting_rework'));
      raise exception 'FAIL: non-technician detail';
    exception when insufficient_privilege then
      if sqlerrm <> 'TECHNICIAN_ACCESS_DENIED' then raise; end if;
    end;
    if (select count(*) from storage.objects where bucket_id = 'repair-images' and name like 'technician-test/%') <> 4 then
      raise exception 'FAIL: authorized Admin/student Storage metadata %', v_key;
    end if;
    reset role;
  end loop;
end $$;

select set_config('request.jwt.claim.sub', (select id::text from technician_jobs_test_context where key = 'technician'), true);
set local role authenticated;
do $$
declare
  v_jobs jsonb := public.technician_list_jobs();
  v_detail jsonb := public.technician_get_job((select id from technician_jobs_test_context where key = 'request_awaiting_rework'));
  v_empty jsonb := public.technician_get_job((select id from technician_jobs_test_context where key = 'request_completed'));
  v_key text;
begin
  if jsonb_array_length(v_jobs) <> 8 or v_jobs->0->>'status' <> 'cancelled'
     or (select count(distinct item->>'status') from jsonb_array_elements(v_jobs) item) <> 8 then
    raise exception 'FAIL: all current statuses/newest order';
  end if;
  if v_jobs->0->>'room_code' <> 'Old room A101' or v_jobs->0->>'building' <> 'Old building'
     or v_jobs->0->>'category_name' <> 'Category at creation'
     or not (v_jobs->0 ?& array['id','request_code','title','description','room_code','building','category_name','status','created_at','updated_at','version']) then
    raise exception 'FAIL: list fields/snapshots';
  end if;
  if v_detail->'student' is distinct from '{"full_name":"Fixture student","phone":"0900000000"}'::jsonb
     or v_detail->'request'->>'description' <> 'Description awaiting_rework'
     or v_detail->'request'->>'room_code' <> 'Old room A101' then raise exception 'FAIL: contact/detail snapshots'; end if;
  if public.technician_get_job((select id from technician_jobs_test_context where key = 'request_cancelled'))
      ->'request'->>'status' <> 'cancelled' then raise exception 'FAIL: cancelled detail remains readable'; end if;
  if jsonb_array_length(v_detail->'attachments') <> 3
     or v_detail->'attachments'->0->'result_id' <> 'null'::jsonb
     or v_detail->'attachments'->0->'feedback_id' <> 'null'::jsonb
     or v_detail->'attachments'->1->>'result_id' <> (select id::text from technician_jobs_test_context where key = 'result_current')
     or v_detail->'attachments'->2->>'feedback_id' <> (select id::text from technician_jobs_test_context where key = 'feedback_rework') then
    raise exception 'FAIL: request/result/feedback attachment groups/order';
  end if;
  if jsonb_array_length(v_detail->'results') <> 2 or v_detail->'results'->0->>'content' <> 'Previous result'
     or v_detail->'results'->0->>'technician_name' <> 'Fixture former technician'
     or v_detail->'results'->1->>'technician_name' <> 'Fixture current technician' then raise exception 'FAIL: result history/order/names'; end if;
  if jsonb_array_length(v_detail->'feedback') <> 2 or v_detail->'feedback'->0->>'kind' <> 'reopen'
     or v_detail->'feedback'->1->>'reason' <> 'Still broken'
     or v_detail->'feedback'->1->>'author_name' <> 'Fixture student' then raise exception 'FAIL: feedback history/order/names'; end if;
  if jsonb_array_length(v_detail->'history') <> 2 or v_detail->'history'->0->>'action' <> 'created'
     or v_detail->'history'->0->'old_status' <> 'null'::jsonb
     or v_detail->'history'->1->>'actor_name' <> 'Fixture administrator'
     or v_detail->'history'->1->>'note' <> 'Transfer audit note' then raise exception 'FAIL: scoped audit history/order'; end if;
  if jsonb_array_length(v_detail->'assignments') <> 2
     or v_detail->'assignments'->0->>'technician_name' <> 'Fixture former technician'
     or v_detail->'assignments'->0->>'assigned_by_name' <> 'Fixture administrator'
     or v_detail->'assignments'->0->>'transfer_reason' <> 'Transfer explanation'
     or v_detail->'assignments'->0->>'end_reason' <> 'transferred'
     or v_detail->'assignments'->1->'ended_at' <> 'null'::jsonb then raise exception 'FAIL: full assignment history/order'; end if;
  foreach v_key in array array['attachments','results','feedback','history','assignments'] loop
    if v_empty->v_key is distinct from '[]'::jsonb then raise exception 'FAIL: empty % array', v_key; end if;
  end loop;
  if (select count(*) from storage.objects where bucket_id = 'repair-images' and name like 'technician-test/%') <> 3 then
    raise exception 'FAIL: Storage isolation/unregistered object denial';
  end if;
  begin perform public.technician_get_job((select id from technician_jobs_test_context where key = 'request_other'));
    raise exception 'FAIL: wrong assignee';
  exception when no_data_found then if sqlerrm <> 'JOB_NOT_FOUND' then raise; end if; end;
  begin perform public.technician_get_job(gen_random_uuid()); raise exception 'FAIL: missing job';
  exception when no_data_found then if sqlerrm <> 'JOB_NOT_FOUND' then raise; end if; end;
  begin perform public.technician_get_job(null); raise exception 'FAIL: null job';
  exception when no_data_found then if sqlerrm <> 'JOB_NOT_FOUND' then raise; end if; end;
  begin update public.repair_requests set title = 'Forbidden'; raise exception 'FAIL: client request write';
  exception when insufficient_privilege then null; end;
  begin update public.profiles set must_change_password = false where id = auth.uid(); raise exception 'FAIL: client profile write';
  exception when insufficient_privilege then null; end;
  begin perform email from public.profiles; raise exception 'FAIL: direct email read';
  exception when insufficient_privilege then null; end;
  begin perform transfer_reason from public.request_assignments; raise exception 'FAIL: broad assignment grant';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Check live status/password state despite an unchanged JWT subject.
do $$ declare v_state text; begin
  foreach v_state in array array['password', 'locked', 'revoked'] loop
    update public.profiles set must_change_password = (v_state = 'password'),
      status = case when v_state = 'password' then 'active'::public.account_status else v_state::public.account_status end
    where id = (select id from technician_jobs_test_context where key = 'technician');
    set local role authenticated;
    begin perform public.technician_list_jobs(); raise exception 'FAIL: blocked list %', v_state;
    exception when insufficient_privilege then if sqlerrm <> 'TECHNICIAN_ACCESS_DENIED' then raise; end if; end;
    begin perform public.technician_get_job((select id from technician_jobs_test_context where key = 'request_awaiting_rework'));
      raise exception 'FAIL: blocked detail %', v_state;
    exception when insufficient_privilege then if sqlerrm <> 'TECHNICIAN_ACCESS_DENIED' then raise; end if; end;
    if exists (select 1 from storage.objects where bucket_id = 'repair-images' and name like 'technician-test/%') then
      raise exception 'FAIL: blocked Storage read %', v_state;
    end if;
    reset role;
  end loop;
end $$;
update public.profiles set must_change_password = false, status = 'active'
where id = (select id from technician_jobs_test_context where key = 'technician');

-- Transfer without relying on a Sprint 2 UI: old technician loses detail/images.
update public.request_assignments set ended_at = '2026-01-02', end_reason = 'transferred'
where id = (select id from technician_jobs_test_context where key = 'assignment_current');
update public.repair_requests set assigned_technician_id =
 (select id from technician_jobs_test_context where key = 'other_technician')
where id = (select id from technician_jobs_test_context where key = 'request_awaiting_rework');
insert into public.request_assignments
 (request_id, technician_id, assigned_by, assigned_at, transfer_reason,
  request_code_snapshot, title_snapshot, room_code_snapshot)
select r.id, r.assigned_technician_id, (select id from technician_jobs_test_context where key = 'admin'),
 '2026-01-02', 'Regression transfer', r.request_code, r.title, r.room_code_snapshot
from public.repair_requests r where r.id = (select id from technician_jobs_test_context where key = 'request_awaiting_rework');
set local role authenticated;
do $$ begin
  if jsonb_array_length(public.technician_list_jobs()) <> 7 then raise exception 'FAIL: transferred job remains in list'; end if;
  begin perform public.technician_get_job((select id from technician_jobs_test_context where key = 'request_awaiting_rework'));
    raise exception 'FAIL: former technician detail';
  exception when no_data_found then if sqlerrm <> 'JOB_NOT_FOUND' then raise; end if; end;
  if exists (select 1 from storage.objects where bucket_id = 'repair-images' and name like 'technician-test/%') then
    raise exception 'FAIL: former technician Storage access';
  end if;
  if not exists (select 1 from public.request_assignments) then raise exception 'FAIL: former assignment summary missing'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from technician_jobs_test_context where key = 'other_technician'), true);
set local role authenticated;
do $$ declare v_detail jsonb := public.technician_get_job((select id from technician_jobs_test_context where key = 'request_awaiting_rework')); begin
  if jsonb_array_length(v_detail->'assignments') <> 3 or jsonb_array_length(v_detail->'attachments') <> 3 then
    raise exception 'FAIL: new technician full detail';
  end if;
  if (select count(*) from storage.objects where bucket_id = 'repair-images' and name like 'technician-test/%') <> 4 then
    raise exception 'FAIL: new technician Storage access';
  end if;
end $$;
reset role;

rollback;
select 'PASS: technician roles, gates, all statuses, snapshots, contacts, related history, assignment transfer, Storage metadata policies; fixtures rolled back' as result;
