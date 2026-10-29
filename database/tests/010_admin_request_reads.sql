-- DF-043/044: Admin-only reads, detail history, combined filters and Vietnam date bounds.
-- Run after 001_schema.sql and 010_admin_request_reads.sql; all test rows roll back.
begin;

create temporary table admin_request_test_context (
  key text primary key,
  id uuid not null default gen_random_uuid()
) on commit drop;
insert into admin_request_test_context (key) values
  ('admin'), ('student'), ('technician'), ('other_technician'),
  ('room_a'), ('room_b'), ('category_a'), ('category_b'),
  ('request_pending'), ('request_assigned'), ('request_rework'),
  ('request_other'), ('request_next_day'), ('assignment_rework'),
  ('result_rework'), ('feedback_rework'), ('attachment_feedback');
grant select on admin_request_test_context to authenticated, anon;

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select id, 'authenticated', 'authenticated', id::text || '@admin-request-test.invalid', now(), now(), now()
from admin_request_test_context
where key in ('admin', 'student', 'technician', 'other_technician');

insert into public.rooms (id, code, building)
select id, case key when 'room_a' then 'TEST-A101' else 'TEST-B202' end, 'Test building'
from admin_request_test_context where key in ('room_a', 'room_b');
insert into public.incident_categories (id, name)
select id, case key when 'category_a' then 'Test electrical' else 'Test plumbing' end
from admin_request_test_context where key in ('category_a', 'category_b');

insert into public.profiles
  (id, identity_code, full_name, email, phone, role, room_id, must_change_password)
select c.id, 'AR-' || c.id::text,
  case c.key when 'admin' then 'Read fixture Admin'
    when 'student' then 'Read fixture Student'
    when 'technician' then 'Read fixture Technician'
    else 'Read fixture Other Technician' end,
  c.id::text || '@admin-request-test.invalid',
  case when c.key = 'admin' then null else '0900000000' end,
  case c.key when 'admin' then 'admin'::public.app_role
    when 'student' then 'student'::public.app_role
    else 'technician'::public.app_role end,
  case when c.key = 'student' then (select id from admin_request_test_context where key = 'room_a') end,
  false
from admin_request_test_context c
where c.key in ('admin', 'student', 'technician', 'other_technician');

insert into public.repair_requests
  (id, student_id, room_id, room_code_snapshot, building_snapshot, category_id,
   category_name_snapshot, title, description, status, assigned_technician_id,
   created_at, updated_at)
select c.id,
  (select id from admin_request_test_context where key = 'student'),
  (select id from admin_request_test_context where key = case
    when c.key = 'request_other' then 'room_b' else 'room_a' end),
  case when c.key = 'request_other' then 'OLD-B202' else 'OLD-A101' end,
  'Old building snapshot',
  (select id from admin_request_test_context where key = case
    when c.key = 'request_other' then 'category_b' else 'category_a' end),
  case when c.key = 'request_other' then 'Old plumbing snapshot' else 'Old electrical snapshot' end,
  'Fixture ' || c.key, 'Fixture repair description',
  case c.key when 'request_pending' then 'pending'::public.repair_status
    when 'request_assigned' then 'assigned'::public.repair_status
    when 'request_rework' then 'awaiting_rework'::public.repair_status
    when 'request_other' then 'assigned'::public.repair_status
    else 'pending'::public.repair_status end,
  case when c.key in ('request_assigned', 'request_rework')
    then (select id from admin_request_test_context where key = 'technician')
    when c.key = 'request_other'
    then (select id from admin_request_test_context where key = 'other_technician') end,
  case c.key
    when 'request_pending' then '2026-10-25 17:00:00+00'::timestamptz
    when 'request_assigned' then '2026-10-26 16:59:59+00'::timestamptz
    when 'request_next_day' then '2026-10-26 17:00:00+00'::timestamptz
    else '2026-10-26 10:00:00+00'::timestamptz end,
  case c.key
    when 'request_pending' then '2026-10-25 17:00:00+00'::timestamptz
    when 'request_assigned' then '2026-10-26 16:59:59+00'::timestamptz
    when 'request_next_day' then '2026-10-26 17:00:00+00'::timestamptz
    else '2026-10-26 10:00:00+00'::timestamptz end
from admin_request_test_context c
where c.key like 'request_%';

insert into public.request_assignments
  (id, request_id, technician_id, assigned_by, assigned_at,
   request_code_snapshot, title_snapshot, room_code_snapshot)
select
  (select id from admin_request_test_context where key = 'assignment_rework'),
  r.id, r.assigned_technician_id,
  (select id from admin_request_test_context where key = 'admin'),
  r.created_at, r.request_code, r.title, r.room_code_snapshot
from public.repair_requests r
where r.id = (select id from admin_request_test_context where key = 'request_rework');

insert into public.repair_results
  (id, request_id, assignment_id, submitted_by, content, submitted_at)
select
  (select id from admin_request_test_context where key = 'result_rework'),
  r.id,
  (select id from admin_request_test_context where key = 'assignment_rework'),
  r.assigned_technician_id, 'Fixture result history', r.updated_at
from public.repair_requests r
where r.id = (select id from admin_request_test_context where key = 'request_rework');

insert into public.request_feedback
  (id, request_id, kind, reason, submitted_by, created_at)
select
  (select id from admin_request_test_context where key = 'feedback_rework'),
  r.id, 'rework', 'Fixture student rework reason', r.student_id, r.updated_at
from public.repair_requests r
where r.id = (select id from admin_request_test_context where key = 'request_rework');

insert into public.request_attachments
  (id, request_id, feedback_id, storage_path, mime_type, size_bytes, uploaded_by)
select
  (select id from admin_request_test_context where key = 'attachment_feedback'),
  r.id,
  (select id from admin_request_test_context where key = 'feedback_rework'),
  'admin-request-test/' || r.id::text || '.png', 'image/png', 128, r.student_id
from public.repair_requests r
where r.id = (select id from admin_request_test_context where key = 'request_rework');

insert into public.request_history
  (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
select r.id, 'request', r.id, 'rework_requested', r.student_id,
  'awaiting_confirmation', 'awaiting_rework', 'Fixture audit note', r.updated_at
from public.repair_requests r
where r.id = (select id from admin_request_test_context where key = 'request_rework');

-- Unauthenticated users cannot execute the Admin RPCs.
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$ begin
  begin perform public.admin_request_filter_options(); raise exception 'FAIL: anon options';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_list_requests(); raise exception 'FAIL: anon list';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_get_request(null); raise exception 'FAIL: anon detail';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- A signed-in Student is also denied by the server-side Admin checks.
select set_config('request.jwt.claim.sub',
  (select id::text from admin_request_test_context where key = 'student'), true);
set local role authenticated;
do $$ begin
  begin perform public.admin_list_requests(); raise exception 'FAIL: Student list';
  exception when insufficient_privilege then
    if sqlerrm <> 'ADMIN_ACCESS_REQUIRED' then raise; end if;
  end;
end $$;
reset role;

-- Admin sees all requests, filters are ANDed, and the Vietnam-local range includes both dates.
select set_config('request.jwt.claim.sub',
  (select id::text from admin_request_test_context where key = 'admin'), true);
set local role authenticated;
do $$
declare
  v_options jsonb := public.admin_request_filter_options();
  v_all jsonb := public.admin_list_requests();
  v_filtered jsonb;
  v_detail jsonb;
  v_pending_id text := (select id::text from admin_request_test_context where key = 'request_pending');
  v_assigned_id text := (select id::text from admin_request_test_context where key = 'request_assigned');
  v_rework_id text := (select id::text from admin_request_test_context where key = 'request_rework');
  v_tech_id text := (select id::text from admin_request_test_context where key = 'technician');
begin
  if jsonb_array_length(v_all) <> 5 then raise exception 'FAIL: all requests visible'; end if;
  if (select count(distinct item->>'status') from jsonb_array_elements(v_all) item) <> 3 then
    raise exception 'FAIL: statuses present in list';
  end if;
  if not (v_options ?& array['rooms', 'categories', 'technicians'])
     or jsonb_array_length(v_options->'technicians') <> 2 then
    raise exception 'FAIL: current technician filter options';
  end if;

  v_filtered := public.admin_list_requests(
    p_status => 'assigned',
    p_room_id => (select id from admin_request_test_context where key = 'room_a'),
    p_category_id => (select id from admin_request_test_context where key = 'category_a'),
    p_technician_id => (select id from admin_request_test_context where key = 'technician'),
    p_date_field => 'created_at',
    p_from => '2026-10-25 17:00:00+00',
    p_to_exclusive => '2026-10-26 17:00:00+00'
  );
  if jsonb_array_length(v_filtered) <> 1 or v_filtered->0->>'id' <> v_assigned_id then
    raise exception 'FAIL: combined AND filters and inclusive Saigon end date';
  end if;

  v_filtered := public.admin_list_requests(
    p_date_field => 'created_at',
    p_from => '2026-10-25 17:00:00+00',
    p_to_exclusive => '2026-10-26 17:00:00+00'
  );
  if not (v_filtered @> jsonb_build_array(jsonb_build_object('id', v_pending_id)))
     or not (v_filtered @> jsonb_build_array(jsonb_build_object('id', v_assigned_id)))
     or v_filtered @> jsonb_build_array(jsonb_build_object('id', (select id::text from admin_request_test_context where key = 'request_next_day'))) then
    raise exception 'FAIL: inclusive Vietnam date boundaries';
  end if;

  v_filtered := public.admin_list_requests(p_date_field => 'updated_at',
    p_from => '2026-10-25 17:00:00+00', p_to_exclusive => '2026-10-26 17:00:00+00');
  if not (v_filtered @> jsonb_build_array(jsonb_build_object('id', v_rework_id))) then
    raise exception 'FAIL: updated_at date filter';
  end if;

  v_detail := public.admin_get_request((select id from admin_request_test_context where key = 'request_rework'));
  if v_detail->'student'->>'full_name' <> 'Read fixture Student'
     or v_detail->'technician'->>'id' <> v_tech_id
     or v_detail->'request'->>'building' <> 'Old building snapshot'
     or jsonb_array_length(v_detail->'results') <> 1
     or jsonb_array_length(v_detail->'feedback') <> 1
     or jsonb_array_length(v_detail->'attachments') <> 1
     or jsonb_array_length(v_detail->'history') <> 1
     or jsonb_array_length(v_detail->'assignments') <> 1 then
    raise exception 'FAIL: detail snapshots, history, feedback and image metadata';
  end if;

  begin
    perform public.admin_list_requests(p_date_field => 'created_at',
      p_from => '2026-10-26 17:00:00+00', p_to_exclusive => '2026-10-25 17:00:00+00');
    raise exception 'FAIL: reversed date range accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'INVALID_DATE_RANGE' then raise; end if;
  end;
end $$;
reset role;

rollback;
select 'PASS: Admin request reads, server role gate, AND filters, Vietnam date bounds and detail history' as result;
