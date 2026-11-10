-- DF-011/012/016: owner-only edit, cancel and reopen with atomic action receipts.
begin;

create function public._student_lifecycle_photo_path(p_name text) returns jsonb
language sql immutable set search_path = '' as $$
  select public._student_feedback_photo_path(
    regexp_replace(p_name, '^student-request-edits/', 'student-feedback/'));
$$;

create function public._student_lifecycle_assignment_valid(
  p_request public.repair_requests
) returns boolean language plpgsql stable set search_path = '' as $$
declare
  v_assignment public.request_assignments%rowtype;
begin
  select * into v_assignment from public.request_assignments
  where request_id = p_request.id and ended_at is null;
  -- A legacy completed request may have no open assignment to end.
  if not found then
    return p_request.status = 'completed'
      or (p_request.status = 'pending' and p_request.assigned_technician_id is null);
  end if;
  if p_request.assigned_technician_id is null then
    return false;
  end if;
  return v_assignment.technician_id = p_request.assigned_technician_id
    and (p_request.status = 'completed'
      or (p_request.status = 'assigned' and v_assignment.started_at is null));
end $$;

create function public._student_in_original_room(
  p_request public.repair_requests, p_uid uuid
) returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    join public.rooms r on r.id = p.room_id and r.is_active
    where p.id = p_uid and r.id = p_request.room_id
  );
$$;

-- Existing feedback policy keeps handling rework. This policy adds edit uploads
-- and completed/current-room reopen uploads under their exact action prefixes.
create function public._can_upload_student_lifecycle_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_path jsonb := public._student_lifecycle_photo_path(p_name);
  v_uid uuid;
  v_request public.repair_requests%rowtype;
  v_prefix text := split_part(p_name,'/',1);
begin
  if v_path is null then return false; end if;
  v_uid := public._student_request_actor();
  if v_path->>'user_id' <> v_uid::text then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('student-action:' || (v_path->>'action_id'),0));
  select * into v_request from public.repair_requests
  where id = (v_path->>'request_id')::uuid and student_id = v_uid for share;
  if not found or v_request.version <> (v_path->>'version')::integer
     or not public._student_lifecycle_assignment_valid(v_request)
     or exists(select 1 from public.request_history where id = (v_path->>'action_id')::uuid)
     or exists(select 1 from public.request_feedback where id = (v_path->>'action_id')::uuid)
     or exists(select 1 from public.request_attachments
       where id = (v_path->>'photo_id')::uuid or storage_path = p_name) then return false; end if;
  if v_prefix = 'student-request-edits' then
    if v_request.status <> 'pending' then return false; end if;
  elsif v_request.status <> 'completed' or not public._student_in_original_room(v_request,v_uid) then
    return false;
  end if;
  return (select count(*) < 5 from storage.objects where bucket_id = 'repair-images'
    and name like (v_prefix || '/' || v_uid::text || '/' || v_request.id::text || '/'
      || v_request.version::text || '/' || (v_path->>'action_id') || '/%'));
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._is_own_staged_student_edit_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb; v_uid uuid;
begin
  if split_part(p_name,'/',1) is distinct from 'student-request-edits' then return false; end if;
  v_path := public._student_lifecycle_photo_path(p_name);
  if v_path is null then return false; end if;
  v_uid := public._student_request_actor();
  return v_path->>'user_id' = v_uid::text
    and exists(select 1 from public.repair_requests
      where id = (v_path->>'request_id')::uuid and student_id = v_uid)
    and not exists(select 1 from public.request_history where id = (v_path->>'action_id')::uuid)
    and not exists(select 1 from public.request_feedback where id = (v_path->>'action_id')::uuid)
    and not exists(select 1 from public.request_attachments where storage_path = p_name);
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._can_delete_student_edit_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb; v_uid uuid;
begin
  if split_part(p_name,'/',1) is distinct from 'student-request-edits' then return false; end if;
  v_path := public._student_lifecycle_photo_path(p_name);
  if v_path is null then return false; end if;
  v_uid := public._student_request_actor();
  if v_path->>'user_id' <> v_uid::text then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('student-action:' || (v_path->>'action_id'),0));
  return public._is_own_staged_student_edit_photo(p_name);
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

-- Return a canonical manifest for reliable same-action replay. Staged bytes
-- and ownership are verified separately after the locks and replay check.
create function public._student_lifecycle_manifest(
  p_photos jsonb, p_prefix text, p_error text
) returns jsonb language plpgsql immutable set search_path = '' as $$
declare v_photo jsonb; v_path jsonb; v_canonical jsonb := '[]'::jsonb;
begin
  if p_photos is null or jsonb_typeof(p_photos) <> 'array' then
    raise exception using errcode = '22023', message = p_error;
  end if;
  if jsonb_array_length(p_photos) > 5 then
    raise exception using errcode = '22023', message = p_error;
  end if;
  for v_photo in select value from jsonb_array_elements(p_photos) loop
    if jsonb_typeof(v_photo) <> 'object' then
      raise exception using errcode = '22023', message = p_error;
    end if;
    if (select count(*) from jsonb_object_keys(v_photo)) <> 4
       or jsonb_typeof(v_photo->'id') is distinct from 'string'
       or jsonb_typeof(v_photo->'storage_path') is distinct from 'string'
       or jsonb_typeof(v_photo->'mime_type') is distinct from 'string'
       or jsonb_typeof(v_photo->'size_bytes') is distinct from 'number'
       or coalesce(v_photo->>'size_bytes','') !~ '^[1-9][0-9]{0,6}$' then
      raise exception using errcode = '22023', message = p_error;
    end if;
    v_path := public._student_lifecycle_photo_path(v_photo->>'storage_path');
    if v_path is null or not starts_with(v_photo->>'storage_path',p_prefix)
       or v_path->>'photo_id' is distinct from v_photo->>'id'
       or v_path->>'mime_type' is distinct from v_photo->>'mime_type'
       or (v_photo->>'size_bytes')::bigint > 5242880 then
      raise exception using errcode = '22023', message = p_error;
    end if;
    v_canonical := v_canonical || jsonb_build_array(v_photo);
  end loop;
  if (select count(distinct value->>'id') from jsonb_array_elements(v_canonical))
      <> jsonb_array_length(v_canonical) then
    raise exception using errcode = '22023', message = p_error;
  end if;
  return (select coalesce(jsonb_agg(value order by value->>'id'),'[]'::jsonb)
    from jsonb_array_elements(v_canonical));
end $$;

create function public._student_lifecycle_validate_staging(
  p_uid uuid, p_photos jsonb, p_prefix text, p_error text
) returns void language plpgsql volatile set search_path = '' as $$
declare v_photo jsonb; v_object storage.objects%rowtype;
begin
  if (select count(*) from storage.objects where bucket_id = 'repair-images'
       and name like (p_prefix || '%')) <> jsonb_array_length(p_photos) then
    raise exception using errcode = '22023', message = p_error;
  end if;
  for v_photo in select value from jsonb_array_elements(p_photos) loop
    select * into v_object from storage.objects where bucket_id = 'repair-images'
      and name = v_photo->>'storage_path' for update;
    if not found or v_object.owner_id is distinct from p_uid::text
       or v_object.metadata->>'mimetype' is distinct from v_photo->>'mime_type'
       or coalesce(v_object.metadata->>'size','') !~ '^[1-9][0-9]{0,6}$' then
      raise exception using errcode = '22023', message = p_error;
    end if;
    if (v_object.metadata->>'size')::bigint is distinct from (v_photo->>'size_bytes')::bigint
       or exists(select 1 from public.request_attachments
         where id = (v_photo->>'id')::uuid or storage_path = v_object.name) then
      raise exception using errcode = '22023', message = p_error;
    end if;
  end loop;
end $$;

create function public._student_mutate_request(
  p_request_id uuid, p_expected_version integer, p_action_id uuid, p_operation text,
  p_title text, p_category_id uuid, p_description text, p_keep_attachment_ids uuid[],
  p_reason text, p_photos jsonb
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._student_request_actor();
  v_request public.repair_requests%rowtype;
  v_history public.request_history%rowtype;
  v_category public.incident_categories%rowtype;
  v_title text := nullif(regexp_replace(p_title,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_description text := nullif(regexp_replace(p_description,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_reason text := nullif(regexp_replace(p_reason,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_keep uuid[] := '{}'::uuid[];
  v_photos jsonb := '[]'::jsonb;
  v_prefix text;
  v_photo_error text;
  v_action text;
  v_status public.repair_status;
  v_feedback_id uuid;
  v_fingerprint text;
  v_now timestamptz;
begin
  if p_request_id is null or p_action_id is null or p_expected_version is null
     or p_expected_version < 1 or p_expected_version >= 2147483647 then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_INPUT';
  end if;
  case p_operation
  when 'edit' then
    if v_title is null or p_category_id is null or v_description is null then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_INPUT';
    end if;
    if p_keep_attachment_ids is null or cardinality(p_keep_attachment_ids) > 5
       or (select count(distinct id) from unnest(p_keep_attachment_ids) id)
          <> cardinality(p_keep_attachment_ids) then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
    end if;
    select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_keep
    from unnest(p_keep_attachment_ids) id;
    v_action := 'student_edited';
    v_status := 'pending';
    v_prefix := 'student-request-edits/';
    v_photo_error := 'INVALID_REQUEST_PHOTOS';
  when 'cancel' then
    if v_reason is null then
      raise exception using errcode = '22023', message = 'CANCELLATION_REASON_REQUIRED';
    end if;
    v_action := 'student_cancelled';
    v_status := 'cancelled';
  when 'reopen' then
    if v_reason is null then
      raise exception using errcode = '22023', message = 'REOPEN_REASON_REQUIRED';
    end if;
    v_action := 'student_reopened';
    v_status := 'pending';
    v_prefix := 'student-feedback/';
    v_photo_error := 'INVALID_FEEDBACK_PHOTOS';
    v_feedback_id := p_action_id;
  end case;
  if v_prefix is not null then
    v_prefix := v_prefix || v_uid::text || '/' || p_request_id::text || '/'
      || p_expected_version::text || '/' || p_action_id::text || '/';
    v_photos := public._student_lifecycle_manifest(p_photos,v_prefix,v_photo_error);
    if cardinality(v_keep) + jsonb_array_length(v_photos) > 5 then
      raise exception using errcode = '22023', message = v_photo_error;
    end if;
  end if;
  v_fingerprint := encode(sha256(convert_to(jsonb_build_object(
    'student_id',v_uid, 'request_id',p_request_id, 'expected_version',p_expected_version,
    'action',v_action, 'title',v_title, 'category_id',p_category_id,
    'description',v_description, 'keep_ids',v_keep, 'reason',v_reason, 'photos',v_photos
  )::text,'UTF8')),'hex');

  -- Same global action lock as Phase 2 and staging. Existing Admin/KTV writes
  -- take the request lock before changing the current assignment or status.
  perform pg_advisory_xact_lock(hashtextextended('student-action:' || p_action_id::text,0));
  select * into v_request from public.repair_requests
  where id = p_request_id and student_id = v_uid for update;
  if not found then raise exception using errcode = 'P0002', message = 'REQUEST_NOT_FOUND'; end if;
  select * into v_history from public.request_history where id = p_action_id;
  if found then
    if v_history.request_id is distinct from p_request_id or v_history.actor_id <> v_uid
       or v_history.action <> v_action or v_history.new_status is distinct from v_status::text
       or v_history.student_action_fingerprint is distinct from v_fingerprint then
      raise exception using errcode = 'P0001', message = 'ACTION_REPLAY_MISMATCH';
    end if;
    return jsonb_build_object('request_id',p_request_id,'action_id',p_action_id,
      'status',v_history.new_status,'version',p_expected_version+1,
      'feedback_id',v_feedback_id,'replayed',true);
  end if;
  if exists(select 1 from public.request_feedback where id = p_action_id) then
    raise exception using errcode = 'P0001', message = 'ACTION_REPLAY_MISMATCH';
  end if;
  if v_request.version <> p_expected_version or not (
     (p_operation = 'edit' and v_request.status = 'pending')
     or (p_operation = 'cancel' and v_request.status in ('pending','assigned'))
     or (p_operation = 'reopen' and v_request.status = 'completed')) then
    raise exception using errcode = 'P0001', message = 'REQUEST_STATE_CONFLICT';
  end if;
  if not public._student_lifecycle_assignment_valid(v_request) then
    raise exception using errcode = 'P0001', message = 'REQUEST_ASSIGNMENT_CONFLICT';
  end if;

  if p_operation = 'edit' then
    select * into v_category from public.incident_categories
    where id = p_category_id and is_active for share;
    if not found then raise exception using errcode = '22023', message = 'ACTIVE_CATEGORY_REQUIRED'; end if;
    if (select count(*) from public.request_attachments
        where request_id = p_request_id and id = any(v_keep)
          and result_id is null and feedback_id is null) <> cardinality(v_keep) then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
    end if;
  elsif p_operation = 'reopen' then
    -- The actor helper has already locked the profile. Lock the room as well so
    -- the active-room decision cannot change between validation and reopening.
    perform 1 from public.rooms r join public.profiles p on p.room_id = r.id
    where p.id = v_uid and r.id = v_request.room_id and r.is_active for share of r;
    if not found then raise exception using errcode = 'P0001', message = 'REOPEN_ROOM_MISMATCH'; end if;
  end if;
  if v_prefix is not null then
    perform public._student_lifecycle_validate_staging(v_uid,v_photos,v_prefix,v_photo_error);
  end if;
  v_now := clock_timestamp();

  if p_operation = 'edit' then
    update public.repair_requests set title = v_title, description = v_description,
      category_id = v_category.id, category_name_snapshot = v_category.name,
      version = version+1, updated_at = v_now where id = p_request_id;
    -- Remove omitted initial-photo links. Storage objects are retained, private,
    -- and no longer readable through either linked or staging RLS.
    delete from public.request_attachments where request_id = p_request_id
      and result_id is null and feedback_id is null and not (id = any(v_keep));
  else
    update public.request_assignments set ended_at = greatest(v_now,assigned_at),
      end_reason = case p_operation when 'cancel' then 'Sinh viên đã hủy yêu cầu.'
        else 'Sinh viên đã mở lại yêu cầu.' end
    where request_id = p_request_id and ended_at is null;
    -- The existing 013 trigger delivers one cancellation to the previous KTV.
    -- Reopen returns to the Admin queue without exposing details to old KTVs.
    update public.repair_requests set status = v_status, assigned_technician_id = null,
      completed_at = null, version = version+1, updated_at = v_now where id = p_request_id;
    if p_operation = 'reopen' then
      insert into public.request_feedback(id,request_id,kind,reason,submitted_by,created_at)
      values(p_action_id,p_request_id,'reopen',v_reason,v_uid,v_now);
    end if;
  end if;
  insert into public.request_attachments(id,request_id,feedback_id,storage_path,
    mime_type,size_bytes,uploaded_by,created_at)
  select (value->>'id')::uuid,p_request_id,v_feedback_id,value->>'storage_path',
    value->>'mime_type',(value->>'size_bytes')::bigint,v_uid,v_now
    from jsonb_array_elements(v_photos);
  insert into public.request_history(id,request_id,entity_type,entity_id,action,
    actor_id,old_status,new_status,note,occurred_at,student_action_fingerprint)
  values(p_action_id,p_request_id,'request',p_request_id,v_action,v_uid,
    v_request.status::text,v_status::text,v_reason,v_now,v_fingerprint);
  return jsonb_build_object('request_id',p_request_id,'action_id',p_action_id,
    'status',v_status,'version',p_expected_version+1,'feedback_id',v_feedback_id,'replayed',false);
end $$;

create function public.student_edit_request(
  p_request_id uuid, p_expected_version integer, p_action_id uuid,
  p_title text, p_category_id uuid, p_description text, p_keep_attachment_ids uuid[],
  p_photos jsonb default '[]'::jsonb
) returns jsonb language sql volatile security definer set search_path = '' as $$
  select public._student_mutate_request(p_request_id,p_expected_version,p_action_id,
    'edit',p_title,p_category_id,p_description,p_keep_attachment_ids,null,p_photos);
$$;
create function public.student_cancel_request(
  p_request_id uuid, p_expected_version integer, p_action_id uuid, p_reason text
) returns jsonb language sql volatile security definer set search_path = '' as $$
  select public._student_mutate_request(p_request_id,p_expected_version,p_action_id,
    'cancel',null,null,null,null,p_reason,'[]'::jsonb);
$$;
create function public.student_reopen_request(
  p_request_id uuid, p_expected_version integer, p_action_id uuid, p_reason text,
  p_photos jsonb default '[]'::jsonb
) returns jsonb language sql volatile security definer set search_path = '' as $$
  select public._student_mutate_request(p_request_id,p_expected_version,p_action_id,
    'reopen',null,null,null,null,p_reason,p_photos);
$$;

-- Preserve the existing detail payload and expose server capability flags.
create or replace function public.student_get_request(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._student_request_actor();
  v_request public.repair_requests%rowtype;
  v_technician jsonb; v_attachments jsonb; v_results jsonb;
  v_feedback jsonb; v_history jsonb;
begin
  select * into v_request from public.repair_requests
  where id = p_request_id and student_id = v_uid for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'REQUEST_NOT_FOUND';
  end if;
  select jsonb_build_object('full_name',full_name,'phone',phone)
    into v_technician from public.profiles where id = v_request.assigned_technician_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'storage_path',a.storage_path,'mime_type',a.mime_type,
    'size_bytes',a.size_bytes,'result_id',a.result_id,'feedback_id',a.feedback_id
  ) order by a.created_at,a.id),'[]'::jsonb) into v_attachments
  from public.request_attachments a where a.request_id = v_request.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'content',r.content,'submitted_at',r.submitted_at,
    'technician_name',p.full_name
  ) order by r.submitted_at,r.id),'[]'::jsonb) into v_results
  from public.repair_results r join public.profiles p on p.id = r.submitted_by
  where r.request_id = v_request.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',f.id,'kind',f.kind,'reason',f.reason,'created_at',f.created_at,
    'author_name',p.full_name
  ) order by f.created_at,f.id),'[]'::jsonb) into v_feedback
  from public.request_feedback f join public.profiles p on p.id = f.submitted_by
  where f.request_id = v_request.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',h.id,'action',h.action,'actor_id',h.actor_id,'actor_name',p.full_name,
    'old_status',h.old_status,'new_status',h.new_status,'note',h.note,
    'occurred_at',h.occurred_at
  ) order by h.occurred_at,h.id),'[]'::jsonb) into v_history
  from public.request_history h join public.profiles p on p.id = h.actor_id
  where h.request_id = v_request.id;
  return jsonb_build_object(
    'request',public._student_request_summary(v_request) || jsonb_build_object(
      'description',v_request.description,'category_id',v_request.category_id),
    'can_edit',v_request.status='pending' and public._student_lifecycle_assignment_valid(v_request),
    'can_cancel',v_request.status in ('pending','assigned') and public._student_lifecycle_assignment_valid(v_request),
    'can_reopen',v_request.status='completed' and public._student_lifecycle_assignment_valid(v_request)
      and public._student_in_original_room(v_request,v_uid),
    'technician',v_technician,'attachments',v_attachments,'results',v_results,
    'feedback',v_feedback,'history',v_history
  );
end $$;

revoke all on function public._student_lifecycle_photo_path(text),
  public._student_lifecycle_assignment_valid(public.repair_requests),
  public._student_in_original_room(public.repair_requests,uuid),
  public._student_lifecycle_manifest(jsonb,text,text),
  public._student_lifecycle_validate_staging(uuid,jsonb,text,text),
  public._student_mutate_request(uuid,integer,uuid,text,text,uuid,text,uuid[],text,jsonb)
  from public,anon,authenticated;
revoke all on function public.student_edit_request(uuid,integer,uuid,text,uuid,text,uuid[],jsonb),
  public.student_cancel_request(uuid,integer,uuid,text),
  public.student_reopen_request(uuid,integer,uuid,text,jsonb),
  public._can_upload_student_lifecycle_photo(text),
  public._is_own_staged_student_edit_photo(text),
  public._can_delete_student_edit_photo(text) from public,anon;
grant execute on function public.student_edit_request(uuid,integer,uuid,text,uuid,text,uuid[],jsonb),
  public.student_cancel_request(uuid,integer,uuid,text),
  public.student_reopen_request(uuid,integer,uuid,text,jsonb),
  public._can_upload_student_lifecycle_photo(text),
  public._is_own_staged_student_edit_photo(text),
  public._can_delete_student_edit_photo(text) to authenticated;

create policy student_lifecycle_photo_upload on storage.objects for insert to authenticated
with check(bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._can_upload_student_lifecycle_photo(name));
create policy student_edit_photo_staged_read on storage.objects for select to authenticated
using(bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._is_own_staged_student_edit_photo(name));
create policy student_edit_photo_staged_delete on storage.objects for delete to authenticated
using(bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._can_delete_student_edit_photo(name));

comment on function public.student_edit_request(uuid,integer,uuid,text,uuid,text,uuid[],jsonb) is
  'DF-011: owner edits pending request text/category and selects retained/new initial photos.';
comment on function public.student_cancel_request(uuid,integer,uuid,text) is
  'DF-012: owner cancels pending/assigned request with a reason, ending any current assignment.';
comment on function public.student_reopen_request(uuid,integer,uuid,text,jsonb) is
  'DF-016: owner reopens a completed request in the same active room, preserving history and result/feedback.';
commit;
