-- DF-023 / DF-026. Apply once after 001, 003 and 004.
-- Files are uploaded/removed through Storage API only; this migration reads and
-- locks Storage metadata but never inserts/updates/deletes its objects.
begin;

alter table public.request_assignments add column started_at timestamptz;
alter table public.request_assignments add constraint assignment_started_after_assignment
  check (started_at is null or started_at >= assigned_at);
alter table public.repair_results add column request_version integer;
alter table public.repair_results add constraint result_request_version_positive
  check (request_version is null or request_version > 0);
create unique index result_request_version_once on public.repair_results (request_id, request_version)
  where request_version is not null;

-- NULL preserves the fact that legacy rows do not prove a start/continuation.
create function public._technician_result_path(p_name text) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_user uuid; v_request uuid; v_result uuid; v_photo uuid; v_version integer;
  v_extension text;
begin
  if coalesce(array_length(v_parts, 1), 0) <> 6 or v_parts[1] <> 'technician-results'
     or v_parts[4] !~ '^[1-9][0-9]{0,9}$'
     or v_parts[6] !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.(jpg|jpeg|png|webp)$' then
    return null;
  end if;
  v_user := v_parts[2]::uuid; v_request := v_parts[3]::uuid;
  v_version := v_parts[4]::integer; v_result := v_parts[5]::uuid;
  v_photo := split_part(v_parts[6], '.', 1)::uuid;
  v_extension := split_part(v_parts[6], '.', 2);
  if v_parts[2] <> v_user::text or v_parts[3] <> v_request::text
     or v_parts[5] <> v_result::text or v_version < 1 then return null; end if;
  return jsonb_build_object('user_id', v_user, 'request_id', v_request,
    'request_version', v_version, 'result_id', v_result, 'photo_id', v_photo,
    'mime_type', case v_extension when 'png' then 'image/png' when 'webp' then 'image/webp' else 'image/jpeg' end);
exception when invalid_text_representation or numeric_value_out_of_range then return null;
end $$;

create function public._technician_workflow_actor() returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_profile public.profiles%rowtype;
begin
  if v_uid is null then raise exception using errcode = '28000', message = 'AUTH_REQUIRED'; end if;
  -- The lock makes an account block and a workflow write serialize.
  select * into v_profile from public.profiles where id = v_uid for share;
  if not found or v_profile.role <> 'technician' or v_profile.status <> 'active'
     or v_profile.must_change_password then
    raise exception using errcode = '42501', message = 'TECHNICIAN_ACCESS_DENIED';
  end if;
  return v_uid;
end $$;

create function public._technician_workflow_capabilities(p_request_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_request public.repair_requests%rowtype; v_assignment public.request_assignments%rowtype;
begin
  select * into v_request from public.repair_requests
    where id = p_request_id and assigned_technician_id = auth.uid();
  if not found or public.current_active_role() is distinct from 'technician'::public.app_role then
    return jsonb_build_object('can_start', false, 'can_submit_result', false, 'blocked_reason', 'READ_ONLY');
  end if;
  select * into v_assignment from public.request_assignments
    where request_id = v_request.id and technician_id = auth.uid() and ended_at is null;
  if not found then
    return jsonb_build_object('can_start', false, 'can_submit_result', false, 'blocked_reason', 'ASSIGNMENT_NOT_READY');
  end if;
  if v_request.status = 'assigned' then
    return jsonb_build_object('can_start', true, 'can_submit_result', false, 'blocked_reason', null);
  elsif v_request.status = 'awaiting_rework' then
    return jsonb_build_object('can_start', false, 'can_submit_result', false, 'blocked_reason', 'CONTINUE_REQUIRED');
  elsif v_request.status = 'in_progress' then
    if v_assignment.needs_transfer_confirmation then
      return jsonb_build_object('can_start', false, 'can_submit_result', false, 'blocked_reason', 'TRANSFER_CONFIRMATION_REQUIRED');
    elsif not (coalesce(v_assignment.started_at >= v_assignment.assigned_at, false)
       or coalesce(v_assignment.transfer_confirmed_at >= v_assignment.assigned_at, false)) then
      return jsonb_build_object('can_start', false, 'can_submit_result', false, 'blocked_reason', 'START_REQUIRED');
    end if;
    return jsonb_build_object('can_start', false, 'can_submit_result', true, 'blocked_reason', null);
  end if;
  return jsonb_build_object('can_start', false, 'can_submit_result', false, 'blocked_reason', 'READ_ONLY');
end $$;

create function public.technician_start_job(p_request_id uuid, p_expected_version integer) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._technician_workflow_actor();
  v_request public.repair_requests%rowtype; v_assignment public.request_assignments%rowtype;
  v_now timestamptz;
begin
  select * into v_request from public.repair_requests
    where id = p_request_id and assigned_technician_id = v_uid for update;
  if not found then raise exception using errcode = 'P0002', message = 'JOB_NOT_FOUND'; end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'JOB_VERSION_REQUIRED';
  end if;
  if v_request.status <> 'assigned' or v_request.version <> p_expected_version then
    raise exception using errcode = 'P0001', message = 'JOB_STATE_CONFLICT';
  end if;
  select * into v_assignment from public.request_assignments
    where request_id = v_request.id and technician_id = v_uid and ended_at is null for update;
  if not found then raise exception using errcode = 'P0001', message = 'ASSIGNMENT_NOT_READY'; end if;
  v_now := clock_timestamp();
  update public.request_assignments set started_at = v_now,
    needs_transfer_confirmation = false, transfer_confirmed_at = null
    where id = v_assignment.id;
  update public.repair_requests set status = 'in_progress', version = version + 1, updated_at = v_now
    where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, occurred_at)
    values (v_request.id, 'request', v_request.id, 'started', v_uid, 'assigned', 'in_progress', v_now);
  return jsonb_build_object('request_id', v_request.id, 'status', v_request.status, 'version', v_request.version);
end $$;

create function public._can_upload_technician_result(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_path jsonb := public._technician_result_path(p_name); v_uid uuid;
  v_request public.repair_requests%rowtype; v_assignment public.request_assignments%rowtype;
begin
  if v_path is null then return false; end if;
  v_uid := public._technician_workflow_actor();
  if v_path->>'user_id' <> v_uid::text then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('technician-result:' || (v_path->>'result_id'), 0));
  if exists (select 1 from public.repair_results where id = (v_path->>'result_id')::uuid) then return false; end if;
  select * into v_request from public.repair_requests
    where id = (v_path->>'request_id')::uuid and assigned_technician_id = v_uid for share;
  if not found or v_request.status <> 'in_progress'
     or v_request.version <> (v_path->>'request_version')::integer then return false; end if;
  select * into v_assignment from public.request_assignments
    where request_id = v_request.id and technician_id = v_uid and ended_at is null for share;
  if not found or v_assignment.needs_transfer_confirmation
     or not (coalesce(v_assignment.started_at >= v_assignment.assigned_at, false)
       or coalesce(v_assignment.transfer_confirmed_at >= v_assignment.assigned_at, false)) then return false; end if;
  -- Serialize inserts for an attempt; finalization also takes this lock.
  return (select count(*) < 5 from storage.objects
    where bucket_id = 'repair-images'
      and name like ('technician-results/' || v_uid::text || '/' || v_request.id::text || '/'
        || v_request.version::text || '/' || (v_path->>'result_id') || '/%'));
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._is_own_uncommitted_technician_result(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.current_active_role() = 'technician'
    and public._technician_result_path(p_name)->>'user_id' = auth.uid()::text
    and not exists (select 1 from public.request_attachments where storage_path = p_name);
$$;

create function public._can_delete_technician_result(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb := public._technician_result_path(p_name); v_uid uuid;
begin
  if v_path is null then return false; end if;
  v_uid := public._technician_workflow_actor();
  if v_path->>'user_id' <> v_uid::text then return false; end if;
  -- A volatile recheck after the shared attempt lock prevents a cleanup request
  -- racing finalization from deleting an image that just became immutable.
  perform pg_advisory_xact_lock(hashtextextended('technician-result:' || (v_path->>'result_id'), 0));
  return not exists (select 1 from public.request_attachments where storage_path = p_name);
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create policy technician_result_upload on storage.objects for insert to authenticated
with check (bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._can_upload_technician_result(name));
create policy technician_result_staged_read on storage.objects for select to authenticated
using (bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._is_own_uncommitted_technician_result(name));
create policy technician_result_staged_delete on storage.objects for delete to authenticated
using (bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._can_delete_technician_result(name));
-- No UPDATE policy: files cannot be overwritten, renamed or moved by clients.

create function public.technician_submit_result(
  p_request_id uuid, p_expected_version integer, p_result_id uuid,
  p_content text, p_photos jsonb default '[]'::jsonb
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._technician_workflow_actor();
  v_request public.repair_requests%rowtype; v_assignment public.request_assignments%rowtype;
  v_existing public.repair_results%rowtype; v_object storage.objects%rowtype;
  v_photo jsonb; v_path jsonb; v_normalized jsonb := '[]'::jsonb; v_existing_photos jsonb;
  v_content text := regexp_replace(p_content, '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_now timestamptz;
begin
  if p_result_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception using errcode = '22023', message = 'JOB_VERSION_REQUIRED';
  end if;
  if v_content is null or length(v_content) = 0 then
    raise exception using errcode = '22023', message = 'RESULT_CONTENT_REQUIRED';
  end if;
  if jsonb_typeof(p_photos) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
  end if;
  if jsonb_array_length(p_photos) > 5 then
    raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
  end if;
  for v_photo in select value from jsonb_array_elements(p_photos) loop
    if jsonb_typeof(v_photo) is distinct from 'object' then
      raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
    end if;
    if not (v_photo ?& array['id','storage_path','mime_type','size_bytes'])
       or (select count(*) from jsonb_object_keys(v_photo)) <> 4 then
      raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
    end if;
    v_path := public._technician_result_path(v_photo->>'storage_path');
    if v_path is null or v_path->>'user_id' <> v_uid::text
       or v_path->>'request_id' <> p_request_id::text
       or v_path->>'request_version' <> p_expected_version::text
       or v_path->>'result_id' <> p_result_id::text
       or v_path->>'photo_id' is distinct from v_photo->>'id'
       or v_path->>'mime_type' is distinct from v_photo->>'mime_type'
       or jsonb_typeof(v_photo->'size_bytes') is distinct from 'number'
       or v_photo->>'size_bytes' !~ '^[1-9][0-9]{0,6}$' then
      raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
    end if;
    if (v_photo->>'size_bytes')::bigint > 5242880 then
      raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
    end if;
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'id', v_path->>'photo_id', 'storage_path', v_photo->>'storage_path',
      'mime_type', v_photo->>'mime_type', 'size_bytes', (v_photo->>'size_bytes')::bigint));
  end loop;
  if (select count(distinct value->>'id') from jsonb_array_elements(v_normalized)) <> jsonb_array_length(v_normalized)
     or (select count(distinct value->>'storage_path') from jsonb_array_elements(v_normalized)) <> jsonb_array_length(v_normalized) then
    raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
  end if;
  select coalesce(jsonb_agg(value order by value->>'storage_path'), '[]'::jsonb) into v_normalized
    from jsonb_array_elements(v_normalized);

  perform pg_advisory_xact_lock(hashtextextended('technician-result:' || p_result_id::text, 0));
  select * into v_request from public.repair_requests
    where id = p_request_id and assigned_technician_id = v_uid for update;
  if not found then raise exception using errcode = 'P0002', message = 'JOB_NOT_FOUND'; end if;
  select * into v_assignment from public.request_assignments
    where request_id = v_request.id and technician_id = v_uid and ended_at is null for update;
  if not found then raise exception using errcode = 'P0001', message = 'ASSIGNMENT_NOT_READY'; end if;

  select * into v_existing from public.repair_results where id = p_result_id for share;
  if found then
    select coalesce(jsonb_agg(jsonb_build_object('id', id::text, 'storage_path', storage_path,
      'mime_type', mime_type, 'size_bytes', size_bytes) order by storage_path), '[]'::jsonb)
      into v_existing_photos from public.request_attachments where result_id = v_existing.id;
    if v_existing.request_id <> v_request.id or v_existing.submitted_by <> v_uid
       or v_existing.assignment_id <> v_assignment.id
       or v_existing.request_version is distinct from p_expected_version
       or v_existing.content <> v_content or v_existing_photos <> v_normalized then
      raise exception using errcode = '22023', message = 'RESULT_REPLAY_MISMATCH';
    end if;
    return jsonb_build_object('request_id', v_request.id, 'result_id', v_existing.id,
      'status', 'awaiting_confirmation', 'version', v_existing.request_version + 1, 'replayed', true);
  end if;
  if v_request.status <> 'in_progress' or v_request.version <> p_expected_version then
    raise exception using errcode = 'P0001', message = 'JOB_STATE_CONFLICT';
  end if;
  if v_assignment.needs_transfer_confirmation then
    raise exception using errcode = 'P0001', message = 'TRANSFER_CONFIRMATION_REQUIRED';
  end if;
  if not (coalesce(v_assignment.started_at >= v_assignment.assigned_at, false)
     or coalesce(v_assignment.transfer_confirmed_at >= v_assignment.assigned_at, false)) then
    raise exception using errcode = 'P0001', message = 'START_REQUIRED';
  end if;
  for v_photo in select value from jsonb_array_elements(v_normalized) loop
    select * into v_object from storage.objects
      where bucket_id = 'repair-images' and name = v_photo->>'storage_path' for update;
    if not found or v_object.owner_id is distinct from v_uid::text
       or v_object.metadata->>'mimetype' is distinct from v_photo->>'mime_type'
       or coalesce(v_object.metadata->>'size', '') !~ '^[1-9][0-9]{0,6}$' then
      raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
    end if;
    if (v_object.metadata->>'size')::bigint is distinct from (v_photo->>'size_bytes')::bigint
       or (v_object.metadata->>'size')::bigint > 5242880 then
      raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
    end if;
    if exists (select 1 from public.request_attachments
        where storage_path = v_object.name or id = (v_photo->>'id')::uuid) then
      raise exception using errcode = '22023', message = 'INVALID_RESULT_PHOTOS';
    end if;
  end loop;

  v_now := clock_timestamp();
  insert into public.repair_results
    (id, request_id, assignment_id, submitted_by, content, submitted_at, request_version)
    values (p_result_id, v_request.id, v_assignment.id, v_uid, v_content, v_now, p_expected_version);
  insert into public.request_attachments
    (id, request_id, result_id, storage_path, mime_type, size_bytes, uploaded_by, created_at)
    select (value->>'id')::uuid, v_request.id, p_result_id, value->>'storage_path',
      value->>'mime_type', (value->>'size_bytes')::bigint, v_uid, v_now
      from jsonb_array_elements(v_normalized);
  update public.repair_requests set status = 'awaiting_confirmation', version = version + 1, updated_at = v_now
    where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, occurred_at)
    values (v_request.id, 'request', v_request.id, 'repair_reported', v_uid, 'in_progress', 'awaiting_confirmation', v_now);
  insert into public.notifications (recipient_id, request_id, event_type, message, created_at)
    values (v_request.student_id, v_request.id, 'repair_reported', 'Yêu cầu sửa chữa đã có kết quả, vui lòng xác nhận.', v_now);
  return jsonb_build_object('request_id', v_request.id, 'result_id', p_result_id,
    'status', v_request.status, 'version', v_request.version, 'replayed', false);
end $$;

revoke all on function public._technician_result_path(text) from public, anon, authenticated;
revoke all on function public._technician_workflow_actor() from public, anon, authenticated;
revoke all on function public._technician_workflow_capabilities(uuid) from public, anon, authenticated;
revoke all on function public._can_upload_technician_result(text) from public, anon;
revoke all on function public._is_own_uncommitted_technician_result(text) from public, anon;
revoke all on function public._can_delete_technician_result(text) from public, anon;
grant execute on function public._can_upload_technician_result(text) to authenticated;
grant execute on function public._is_own_uncommitted_technician_result(text) to authenticated;
grant execute on function public._can_delete_technician_result(text) to authenticated;
revoke all on function public.technician_start_job(uuid, integer) from public, anon;
revoke all on function public.technician_submit_result(uuid, integer, uuid, text, jsonb) from public, anon;
grant execute on function public.technician_start_job(uuid, integer) to authenticated;
grant execute on function public.technician_submit_result(uuid, integer, uuid, text, jsonb) to authenticated;

-- The existing detail RPC is replaced below with the same read data and an
-- additive workflow capability object. Legacy clients ignore the new key.

create or replace function public.technician_get_job(p_request_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_request public.repair_requests%rowtype;
  v_student jsonb;
  v_attachments jsonb;
  v_results jsonb;
  v_feedback jsonb;
  v_history jsonb;
  v_assignments jsonb;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;
  if public.current_active_role() is distinct from 'technician'::public.app_role then
    raise exception using errcode = '42501', message = 'TECHNICIAN_ACCESS_DENIED';
  end if;

  -- Current assignment is the authority, including completed/cancelled jobs.
  -- The same error for missing, unassigned and transferred jobs avoids ID leaks.
  select * into v_request from public.repair_requests r
  where r.id = p_request_id and r.assigned_technician_id = v_uid;
  if not found then
    raise exception using errcode = 'P0002', message = 'JOB_NOT_FOUND';
  end if;

  select jsonb_build_object('full_name', p.full_name, 'phone', p.phone)
  into v_student from public.profiles p where p.id = v_request.student_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'storage_path', a.storage_path, 'mime_type', a.mime_type,
    'size_bytes', a.size_bytes, 'result_id', a.result_id, 'feedback_id', a.feedback_id
  ) order by a.created_at, a.id), '[]'::jsonb)
  into v_attachments from public.request_attachments a
  where a.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'content', r.content, 'submitted_at', r.submitted_at,
    'technician_name', p.full_name
  ) order by r.submitted_at, r.id), '[]'::jsonb)
  into v_results from public.repair_results r
  join public.profiles p on p.id = r.submitted_by
  where r.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id, 'kind', f.kind, 'reason', f.reason, 'created_at', f.created_at,
    'author_name', p.full_name
  ) order by f.created_at, f.id), '[]'::jsonb)
  into v_feedback from public.request_feedback f
  join public.profiles p on p.id = f.submitted_by
  where f.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', h.id, 'action', h.action, 'actor_name', p.full_name,
    'old_status', h.old_status, 'new_status', h.new_status,
    'note', h.note, 'occurred_at', h.occurred_at
  ) order by h.occurred_at, h.id), '[]'::jsonb)
  into v_history from public.request_history h
  join public.profiles p on p.id = h.actor_id
  where h.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'technician_name', technician.full_name,
    'assigned_by_name', administrator.full_name, 'assigned_at', a.assigned_at,
    'ended_at', a.ended_at, 'transfer_reason', a.transfer_reason,
    'end_reason', a.end_reason
  ) order by a.assigned_at, a.id), '[]'::jsonb)
  into v_assignments from public.request_assignments a
  join public.profiles technician on technician.id = a.technician_id
  join public.profiles administrator on administrator.id = a.assigned_by
  where a.request_id = v_request.id;

  return jsonb_build_object(
    'request', jsonb_build_object(
      'id', v_request.id, 'request_code', v_request.request_code,
      'title', v_request.title, 'description', v_request.description,
      'room_code', v_request.room_code_snapshot, 'building', v_request.building_snapshot,
      'category_name', v_request.category_name_snapshot, 'status', v_request.status,
      'created_at', v_request.created_at, 'updated_at', v_request.updated_at,
      'version', v_request.version
    ),
    'student', v_student, 'attachments', v_attachments, 'results', v_results,
    'feedback', v_feedback, 'history', v_history, 'assignments', v_assignments,
    'workflow', public._technician_workflow_capabilities(v_request.id)
  );
end $$;

commit;
