-- DF-014/015: student confirmation and rework are atomic, versioned actions.
-- Replay stores a digest only; history remains the original action receipt even
-- after later repair rounds. No existing users/data or table grants are changed.
begin;

alter table public.request_history add column student_action_fingerprint text
  check(student_action_fingerprint is null or student_action_fingerprint ~ '^[a-f0-9]{64}$');

create function public._student_confirmation_ready(
  p_request public.repair_requests,p_expected_version integer
) returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_assignment public.request_assignments%rowtype; v_result public.repair_results%rowtype;
begin
  select * into v_assignment from public.request_assignments
  where request_id=p_request.id and ended_at is null for share;
  if not found or p_request.assigned_technician_id is null
     or v_assignment.technician_id<>p_request.assigned_technician_id
     or v_assignment.needs_transfer_confirmation then return false; end if;
  select * into v_result from public.repair_results where request_id=p_request.id
  order by submitted_at desc,id desc limit 1 for share;
  if not found or v_result.assignment_id<>v_assignment.id
     or v_result.submitted_by<>v_assignment.technician_id then return false; end if;
  -- Legacy results predating migration 005 have no version. They are trusted
  -- only for this exact current assignment; modern results must prove the
  -- transition from in_progress version N to awaiting_confirmation version N+1.
  return v_result.request_version is null or v_result.request_version=p_expected_version-1;
end $$;

create function public._student_feedback_photo_path(p_name text) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_parts text[]:=string_to_array(p_name,'/'); v_user uuid; v_request uuid;
  v_action uuid; v_photo uuid; v_version bigint; v_extension text;
begin
  if coalesce(array_length(v_parts,1),0)<>6 or v_parts[1]<>'student-feedback'
     or v_parts[4]!~'^[1-9][0-9]{0,9}$'
     or v_parts[6]!~'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.(jpg|jpeg|png|webp)$' then
    return null;
  end if;
  v_user:=v_parts[2]::uuid; v_request:=v_parts[3]::uuid; v_action:=v_parts[5]::uuid;
  v_version:=v_parts[4]::bigint; v_photo:=split_part(v_parts[6],'.',1)::uuid;
  v_extension:=split_part(v_parts[6],'.',2);
  if v_parts[2]<>v_user::text or v_parts[3]<>v_request::text
     or v_parts[5]<>v_action::text or v_version>=2147483647 then return null; end if;
  return jsonb_build_object('user_id',v_user,'request_id',v_request,'version',v_version,
    'action_id',v_action,'photo_id',v_photo,'mime_type',case v_extension
      when 'png' then 'image/png' when 'webp' then 'image/webp' else 'image/jpeg' end);
exception when invalid_text_representation or numeric_value_out_of_range then return null;
end $$;

create function public._can_upload_student_feedback_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb:=public._student_feedback_photo_path(p_name); v_uid uuid;
  v_request public.repair_requests%rowtype;
begin
  if v_path is null then return false; end if;
  v_uid:=public._student_request_actor();
  if v_path->>'user_id'<>v_uid::text then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('student-action:'||(v_path->>'action_id'),0));
  select * into v_request from public.repair_requests
  where id=(v_path->>'request_id')::uuid and student_id=v_uid for share;
  if not found or v_request.status<>'awaiting_confirmation'
     or v_request.version<>(v_path->>'version')::integer
     or not public._student_confirmation_ready(v_request,v_request.version)
     or exists(select 1 from public.request_history where id=(v_path->>'action_id')::uuid)
     or exists(select 1 from public.request_feedback where id=(v_path->>'action_id')::uuid)
     or exists(select 1 from public.request_attachments
       where id=(v_path->>'photo_id')::uuid or storage_path=p_name) then return false; end if;
  return (select count(*)<5 from storage.objects where bucket_id='repair-images'
    and name like ('student-feedback/'||v_uid::text||'/'||v_request.id::text||'/'
      ||v_request.version::text||'/'||(v_path->>'action_id')||'/%'));
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._is_own_staged_student_feedback_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb:=public._student_feedback_photo_path(p_name); v_uid uuid;
begin
  if v_path is null then return false; end if;
  v_uid:=public._student_request_actor();
  return v_path->>'user_id'=v_uid::text
    and exists(select 1 from public.repair_requests
      where id=(v_path->>'request_id')::uuid and student_id=v_uid)
    and not exists(select 1 from public.request_history where id=(v_path->>'action_id')::uuid)
    and not exists(select 1 from public.request_feedback where id=(v_path->>'action_id')::uuid)
    and not exists(select 1 from public.request_attachments where storage_path=p_name);
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._can_delete_student_feedback_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb:=public._student_feedback_photo_path(p_name); v_uid uuid;
begin
  if v_path is null then return false; end if;
  v_uid:=public._student_request_actor();
  if v_path->>'user_id'<>v_uid::text then return false; end if;
  -- Same action lock as INSERT/finalization, then recheck committed references.
  -- Failed/stale drafts may be cleaned even after the request changes state.
  perform pg_advisory_xact_lock(hashtextextended('student-action:'||(v_path->>'action_id'),0));
  return public._is_own_staged_student_feedback_photo(p_name);
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._student_resolve_result(
  p_request_id uuid,p_expected_version integer,p_action_id uuid,
  p_is_rework boolean,p_text text,p_photos jsonb
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid:=public._student_request_actor();
  v_text text:=nullif(regexp_replace(p_text,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_action text:=case when p_is_rework then 'student_rework_requested' else 'student_confirmed' end;
  v_status text:=case when p_is_rework then 'awaiting_rework' else 'completed' end;
  v_photos jsonb:='[]'::jsonb; v_photo jsonb; v_path jsonb; v_fingerprint text;
  v_request public.repair_requests%rowtype; v_history public.request_history%rowtype;
  v_object storage.objects%rowtype; v_prefix text; v_count integer;
  v_now timestamptz:=clock_timestamp();
begin
  if p_request_id is null or p_action_id is null or p_expected_version is null
     or p_expected_version<1 or p_expected_version>=2147483647 or p_is_rework is null then
    raise exception using errcode='22023',message='INVALID_CONFIRMATION_INPUT';
  end if;
  if p_is_rework and v_text is null then
    raise exception using errcode='22023',message='REWORK_REASON_REQUIRED';
  end if;
  if p_photos is null or jsonb_typeof(p_photos)<>'array' then
    raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
  end if;
  if jsonb_array_length(p_photos)>5 or (not p_is_rework and p_photos<>'[]'::jsonb) then
    raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
  end if;
  for v_photo in select value from jsonb_array_elements(p_photos) loop
    if jsonb_typeof(v_photo)<>'object' then
      raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
    end if;
    if (select count(*) from jsonb_object_keys(v_photo))<>4
       or jsonb_typeof(v_photo->'id') is distinct from 'string'
       or jsonb_typeof(v_photo->'storage_path') is distinct from 'string'
       or jsonb_typeof(v_photo->'mime_type') is distinct from 'string'
       or jsonb_typeof(v_photo->'size_bytes') is distinct from 'number'
       or coalesce(v_photo->>'size_bytes','')!~'^[1-9][0-9]{0,6}$' then
      raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
    end if;
    v_path:=public._student_feedback_photo_path(v_photo->>'storage_path');
    if v_path is null or v_path->>'user_id'<>v_uid::text
       or v_path->>'request_id'<>p_request_id::text
       or (v_path->>'version')::integer<>p_expected_version
       or v_path->>'action_id'<>p_action_id::text
       or v_path->>'photo_id' is distinct from v_photo->>'id'
       or v_path->>'mime_type' is distinct from v_photo->>'mime_type'
       or (v_photo->>'size_bytes')::bigint>5242880 then
      raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
    end if;
    v_photos:=v_photos||jsonb_build_array(jsonb_build_object('id',v_photo->>'id',
      'storage_path',v_photo->>'storage_path','mime_type',v_photo->>'mime_type',
      'size_bytes',(v_photo->>'size_bytes')::bigint));
  end loop;
  v_count:=jsonb_array_length(v_photos);
  if (select count(distinct value->>'id') from jsonb_array_elements(v_photos))<>v_count
     or (select count(distinct value->>'storage_path') from jsonb_array_elements(v_photos))<>v_count then
    raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
  end if;
  select coalesce(jsonb_agg(value order by value->>'storage_path'),'[]'::jsonb)
    into v_photos from jsonb_array_elements(v_photos);
  v_fingerprint:=encode(sha256(convert_to(jsonb_build_object('student_id',v_uid,
    'request_id',p_request_id,'expected_version',p_expected_version,'action',v_action,
    'text',v_text,'photos',v_photos)::text,'UTF8')),'hex');

  -- Global action UUID lock protects collisions across different requests too.
  -- Lock order: actor profile -> action -> request -> assignment/result -> blobs.
  perform pg_advisory_xact_lock(hashtextextended('student-action:'||p_action_id::text,0));
  select * into v_request from public.repair_requests
    where id=p_request_id and student_id=v_uid for update;
  if not found then raise exception using errcode='P0002',message='REQUEST_NOT_FOUND'; end if;
  select * into v_history from public.request_history where id=p_action_id;
  if found then
    if v_history.request_id is distinct from p_request_id or v_history.actor_id<>v_uid
       or v_history.action<>v_action or v_history.new_status is distinct from v_status
       or v_history.student_action_fingerprint is distinct from v_fingerprint then
      raise exception using errcode='P0001',message='ACTION_REPLAY_MISMATCH';
    end if;
    return jsonb_build_object('request_id',p_request_id,'action_id',p_action_id,
      'status',v_history.new_status,'version',p_expected_version+1,
      'feedback_id',case when p_is_rework then p_action_id end,'replayed',true);
  end if;
  if exists(select 1 from public.request_feedback where id=p_action_id) then
    raise exception using errcode='P0001',message='ACTION_REPLAY_MISMATCH';
  end if;
  if v_request.version<>p_expected_version or v_request.status<>'awaiting_confirmation' then
    raise exception using errcode='P0001',message='REQUEST_STATE_CONFLICT';
  end if;
  if not public._student_confirmation_ready(v_request,p_expected_version) then
    raise exception using errcode='P0001',message='CONFIRMATION_NOT_READY';
  end if;
  v_prefix:='student-feedback/'||v_uid::text||'/'||p_request_id::text||'/'
    ||p_expected_version::text||'/'||p_action_id::text||'/';
  if (select count(*) from storage.objects where bucket_id='repair-images'
      and name like (v_prefix||'%'))<>v_count then
    raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
  end if;
  for v_photo in select value from jsonb_array_elements(v_photos) loop
    select * into v_object from storage.objects where bucket_id='repair-images'
      and name=v_photo->>'storage_path' for update;
    if not found or v_object.owner_id is distinct from v_uid::text
       or v_object.metadata->>'mimetype' is distinct from v_photo->>'mime_type'
       or coalesce(v_object.metadata->>'size','')!~'^[1-9][0-9]{0,6}$' then
      raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
    end if;
    if (v_object.metadata->>'size')::bigint is distinct from (v_photo->>'size_bytes')::bigint
       or (v_object.metadata->>'size')::bigint>5242880
       or exists(select 1 from public.request_attachments
         where id=(v_photo->>'id')::uuid or storage_path=v_object.name) then
      raise exception using errcode='22023',message='INVALID_FEEDBACK_PHOTOS';
    end if;
  end loop;
  if p_is_rework then
    insert into public.request_feedback(id,request_id,kind,reason,submitted_by,created_at)
      values(p_action_id,p_request_id,'rework',v_text,v_uid,v_now);
    insert into public.request_attachments(id,request_id,feedback_id,storage_path,
      mime_type,size_bytes,uploaded_by,created_at)
    select (value->>'id')::uuid,p_request_id,p_action_id,value->>'storage_path',
      value->>'mime_type',(value->>'size_bytes')::bigint,v_uid,v_now
      from jsonb_array_elements(v_photos);
  end if;
  update public.repair_requests set status=v_status::public.repair_status,
    completed_at=case when p_is_rework then null else v_now end,
    version=version+1,updated_at=v_now where id=p_request_id;
  insert into public.request_history(id,request_id,entity_type,entity_id,action,
    actor_id,old_status,new_status,note,occurred_at,student_action_fingerprint)
  values(p_action_id,p_request_id,'request',p_request_id,v_action,v_uid,
    'awaiting_confirmation',v_status,v_text,v_now,v_fingerprint);
  -- The existing 013 status trigger emits exactly one KTV notification.
  return jsonb_build_object('request_id',p_request_id,'action_id',p_action_id,
    'status',v_status,'version',p_expected_version+1,
    'feedback_id',case when p_is_rework then p_action_id end,'replayed',false);
end $$;

create function public.student_confirm_result(
  p_request_id uuid,p_expected_version integer,p_action_id uuid,p_note text default null
) returns jsonb language sql volatile security definer set search_path = '' as $$
  select public._student_resolve_result(p_request_id,p_expected_version,p_action_id,false,p_note,'[]'::jsonb);
$$;
create function public.student_request_rework(
  p_request_id uuid,p_expected_version integer,p_action_id uuid,p_reason text,
  p_photos jsonb default '[]'::jsonb
) returns jsonb language sql volatile security definer set search_path = '' as $$
  select public._student_resolve_result(p_request_id,p_expected_version,p_action_id,true,p_reason,p_photos);
$$;

revoke all on function public._student_confirmation_ready(public.repair_requests,integer),
  public._student_feedback_photo_path(text),
  public._student_resolve_result(uuid,integer,uuid,boolean,text,jsonb) from public,anon,authenticated;
revoke all on function public.student_confirm_result(uuid,integer,uuid,text),
  public.student_request_rework(uuid,integer,uuid,text,jsonb),
  public._can_upload_student_feedback_photo(text),
  public._is_own_staged_student_feedback_photo(text),
  public._can_delete_student_feedback_photo(text) from public,anon;
grant execute on function public.student_confirm_result(uuid,integer,uuid,text),
  public.student_request_rework(uuid,integer,uuid,text,jsonb),
  public._can_upload_student_feedback_photo(text),
  public._is_own_staged_student_feedback_photo(text),
  public._can_delete_student_feedback_photo(text) to authenticated;

create policy student_feedback_photo_upload on storage.objects for insert to authenticated
with check(bucket_id='repair-images' and owner_id=auth.uid()::text
  and public._can_upload_student_feedback_photo(name));
create policy student_feedback_photo_staged_read on storage.objects for select to authenticated
using(bucket_id='repair-images' and owner_id=auth.uid()::text
  and public._is_own_staged_student_feedback_photo(name));
create policy student_feedback_photo_staged_delete on storage.objects for delete to authenticated
using(bucket_id='repair-images' and owner_id=auth.uid()::text
  and public._can_delete_student_feedback_photo(name));

comment on function public.student_confirm_result(uuid,integer,uuid,text) is
  'DF-014: active owning student confirms current assignment result; exact version, atomic completion/audit, stable idempotent action receipt. Former rooms allowed.';
comment on function public.student_request_rework(uuid,integer,uuid,text,jsonb) is
  'DF-015: active owning student requests rework with reason and at most five immutable staged photos; same KTV, atomic feedback/audit, stable idempotent action receipt. Former rooms allowed.';
commit;
