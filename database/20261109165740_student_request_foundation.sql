-- DF-007–010: student-owned request creation, reads and private request photos.
-- No direct client writes to business tables; no change to existing demo users.
begin;

do $$ begin
  if not exists(select 1 from storage.buckets b where b.id = 'repair-images'
      and b.public = false and b.file_size_limit = 5242880
      and b.allowed_mime_types @> array['image/jpeg','image/png','image/webp']
      and b.allowed_mime_types <@ array['image/jpeg','image/png','image/webp']) then
    raise exception 'REPAIR_IMAGES_BUCKET_CONFIG_MISMATCH';
  end if;
end $$;

-- Keep only a digest of the original create payload. Future edits may replace
-- current text/photos without losing retry identity or retaining old content.
alter table public.repair_requests add column student_creation_fingerprint text
  check(student_creation_fingerprint is null or student_creation_fingerprint ~ '^[a-f0-9]{64}$');

create function public._student_request_actor() returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;
  select * into v_profile from public.profiles where id = v_uid for share;
  if not found or v_profile.role <> 'student' or v_profile.status <> 'active'
     or v_profile.must_change_password then
    raise exception using errcode = '42501', message = 'STUDENT_ACCESS_DENIED';
  end if;
  return v_uid;
end $$;

create function public._student_request_summary(p_request public.repair_requests)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_request.id, 'student_id',p_request.student_id,'request_code', p_request.request_code,
    'title', p_request.title, 'category_name', p_request.category_name_snapshot,
    'room_code', p_request.room_code_snapshot, 'status', p_request.status,
    'created_at', p_request.created_at, 'version', p_request.version
  );
$$;

create function public.student_list_categories() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_categories jsonb;
begin
  perform public._student_request_actor();
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)
    order by name,id),'[]'::jsonb) into v_categories
  from public.incident_categories where is_active;
  return v_categories;
end $$;

create function public.student_list_requests() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := public._student_request_actor(); v_requests jsonb;
begin
  select coalesce(jsonb_agg(public._student_request_summary(r)
    order by r.created_at desc,r.id desc),'[]'::jsonb) into v_requests
  from public.repair_requests r where r.student_id = v_uid;
  return v_requests;
end $$;

create function public.student_get_request(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._student_request_actor();
  v_request public.repair_requests%rowtype;
  v_technician jsonb; v_attachments jsonb; v_results jsonb;
  v_feedback jsonb; v_history jsonb;
begin
  select * into v_request from public.repair_requests
  where id = p_request_id and student_id = v_uid;
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
    'technician',v_technician,'attachments',v_attachments,'results',v_results,
    'feedback',v_feedback,'history',v_history
  );
end $$;

-- Parse only canonical, user-scoped staging paths. Never infer ownership from a
-- client manifest without matching the object owner and its stored metadata.
create function public._student_request_photo_path(p_name text) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_parts text[] := string_to_array(p_name,'/');
  v_user uuid; v_request uuid; v_photo uuid; v_extension text;
begin
  if coalesce(array_length(v_parts,1),0) <> 4 or v_parts[1] <> 'student-requests'
     or v_parts[4] !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.(jpg|jpeg|png|webp)$' then
    return null;
  end if;
  v_user := v_parts[2]::uuid; v_request := v_parts[3]::uuid;
  v_photo := split_part(v_parts[4],'.',1)::uuid;
  v_extension := split_part(v_parts[4],'.',2);
  if v_parts[2] <> v_user::text or v_parts[3] <> v_request::text then return null; end if;
  return jsonb_build_object('user_id',v_user,'request_id',v_request,'photo_id',v_photo,
    'mime_type',case v_extension when 'png' then 'image/png'
      when 'webp' then 'image/webp' else 'image/jpeg' end);
exception when invalid_text_representation then return null;
end $$;

create function public._can_upload_student_request_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb := public._student_request_photo_path(p_name); v_uid uuid;
begin
  if v_path is null then return false; end if;
  v_uid := public._student_request_actor();
  if v_path->>'user_id' <> v_uid::text then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('student-request:' || (v_path->>'request_id'),0));
  if exists(select 1 from public.repair_requests where id = (v_path->>'request_id')::uuid)
     or exists(select 1 from public.request_attachments
       where id = (v_path->>'photo_id')::uuid or storage_path = p_name) then return false; end if;
  return (select count(*) < 5 from storage.objects
    where bucket_id = 'repair-images' and name like (
      'student-requests/' || v_uid::text || '/' || (v_path->>'request_id') || '/%'));
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._is_own_staged_student_request_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb := public._student_request_photo_path(p_name); v_uid uuid;
begin
  if v_path is null then return false; end if;
  v_uid := public._student_request_actor();
  return v_path->>'user_id' = v_uid::text
    and not exists(select 1 from public.repair_requests where id = (v_path->>'request_id')::uuid)
    and not exists(select 1 from public.request_attachments where storage_path = p_name);
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public._can_delete_student_request_photo(p_name text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_path jsonb := public._student_request_photo_path(p_name); v_uid uuid;
begin
  if v_path is null then return false; end if;
  v_uid := public._student_request_actor();
  if v_path->>'user_id' <> v_uid::text then return false; end if;
  -- Same transaction lock as upload/finalize prevents stale cleanup deleting a
  -- just-committed object. SELECT policy also permits deletion of own staging.
  perform pg_advisory_xact_lock(hashtextextended('student-request:' || (v_path->>'request_id'),0));
  return not exists(select 1 from public.repair_requests where id = (v_path->>'request_id')::uuid)
    and not exists(select 1 from public.request_attachments where storage_path = p_name);
exception when insufficient_privilege or invalid_authorization_specification then return false;
end $$;

create function public.student_create_request(
  p_request_id uuid,p_title text,p_category_id uuid,p_description text,
  p_photos jsonb default '[]'::jsonb
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := public._student_request_actor();
  v_title text := regexp_replace(p_title,'^[[:space:]]+|[[:space:]]+$','','g');
  v_description text := regexp_replace(p_description,'^[[:space:]]+|[[:space:]]+$','','g');
  v_profile public.profiles%rowtype; v_room public.rooms%rowtype;
  v_category public.incident_categories%rowtype; v_request public.repair_requests%rowtype;
  v_photo jsonb; v_path jsonb; v_photos jsonb := '[]'::jsonb; v_fingerprint text;
  v_object storage.objects%rowtype; v_now timestamptz := clock_timestamp();
  v_prefix text; v_photo_count integer;
begin
  if p_request_id is null or p_category_id is null or nullif(v_title,'') is null
     or nullif(v_description,'') is null then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_INPUT';
  end if;
  if p_photos is null or jsonb_typeof(p_photos) <> 'array' then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
  end if;
  if jsonb_array_length(p_photos) > 5 then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
  end if;
  for v_photo in select value from jsonb_array_elements(p_photos) loop
    if jsonb_typeof(v_photo) <> 'object' then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
    end if;
    if (select count(*) from jsonb_object_keys(v_photo)) <> 4
       or jsonb_typeof(v_photo->'id') is distinct from 'string'
       or jsonb_typeof(v_photo->'storage_path') is distinct from 'string'
       or jsonb_typeof(v_photo->'mime_type') is distinct from 'string'
       or jsonb_typeof(v_photo->'size_bytes') is distinct from 'number'
       or coalesce(v_photo->>'size_bytes','') !~ '^[1-9][0-9]{0,6}$' then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
    end if;
    v_path := public._student_request_photo_path(v_photo->>'storage_path');
    if v_path is null or v_path->>'user_id' <> v_uid::text
       or v_path->>'request_id' <> p_request_id::text
       or v_path->>'photo_id' is distinct from v_photo->>'id'
       or v_path->>'mime_type' is distinct from v_photo->>'mime_type'
       or (v_photo->>'size_bytes')::bigint > 5242880 then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
    end if;
    v_photos := v_photos || jsonb_build_array(jsonb_build_object(
      'id',v_photo->>'id','storage_path',v_photo->>'storage_path',
      'mime_type',v_photo->>'mime_type','size_bytes',(v_photo->>'size_bytes')::bigint));
  end loop;
  v_photo_count := jsonb_array_length(v_photos);
  if (select count(distinct value->>'id') from jsonb_array_elements(v_photos)) <> v_photo_count
     or (select count(distinct value->>'storage_path') from jsonb_array_elements(v_photos)) <> v_photo_count then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
  end if;
  select coalesce(jsonb_agg(value order by value->>'storage_path'),'[]'::jsonb)
    into v_photos from jsonb_array_elements(v_photos);
  v_fingerprint := encode(sha256(convert_to(jsonb_build_object(
    'student_id',v_uid,'request_id',p_request_id,'title',v_title,
    'category_id',p_category_id,'description',v_description,'photos',v_photos
  )::text,'UTF8')),'hex');

  perform pg_advisory_xact_lock(hashtextextended('student-request:' || p_request_id::text,0));
  select * into v_request from public.repair_requests where id = p_request_id for update;
  if found then
    if v_request.student_id <> v_uid then
      raise exception using errcode = 'P0002', message = 'REQUEST_NOT_FOUND';
    end if;
    if v_request.student_creation_fingerprint is distinct from v_fingerprint then
      raise exception using errcode = 'P0001', message = 'REQUEST_REPLAY_MISMATCH';
    end if;
    return public._student_request_summary(v_request);
  end if;

  select * into strict v_profile from public.profiles where id = v_uid;
  select * into v_room from public.rooms where id = v_profile.room_id and is_active for share;
  if not found then
    raise exception using errcode = '22023', message = 'ACTIVE_STUDENT_ROOM_REQUIRED';
  end if;
  select * into v_category from public.incident_categories where id = p_category_id and is_active for share;
  if not found then
    raise exception using errcode = '22023', message = 'ACTIVE_CATEGORY_REQUIRED';
  end if;
  v_prefix := 'student-requests/' || v_uid::text || '/' || p_request_id::text || '/';
  if (select count(*) from storage.objects where bucket_id = 'repair-images'
      and name like (v_prefix || '%')) <> v_photo_count then
    raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
  end if;
  for v_photo in select value from jsonb_array_elements(v_photos) loop
    select * into v_object from storage.objects
    where bucket_id = 'repair-images' and name = v_photo->>'storage_path' for update;
    if not found or v_object.owner_id is distinct from v_uid::text
       or v_object.metadata->>'mimetype' is distinct from v_photo->>'mime_type'
       or coalesce(v_object.metadata->>'size','') !~ '^[1-9][0-9]{0,6}$' then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
    end if;
    if (v_object.metadata->>'size')::bigint is distinct from (v_photo->>'size_bytes')::bigint
       or (v_object.metadata->>'size')::bigint > 5242880
       or exists(select 1 from public.request_attachments
         where storage_path = v_object.name or id = (v_photo->>'id')::uuid) then
      raise exception using errcode = '22023', message = 'INVALID_REQUEST_PHOTOS';
    end if;
  end loop;
  insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
    category_id,category_name_snapshot,title,description,status,created_at,updated_at,student_creation_fingerprint)
  values(p_request_id,v_uid,v_room.id,v_room.code,v_room.building,v_category.id,v_category.name,
    v_title,v_description,'pending',v_now,v_now,v_fingerprint) returning * into v_request;
  insert into public.request_attachments(id,request_id,storage_path,mime_type,size_bytes,uploaded_by,created_at)
  select (value->>'id')::uuid,v_request.id,value->>'storage_path',value->>'mime_type',
    (value->>'size_bytes')::bigint,v_uid,v_now from jsonb_array_elements(v_photos);
  insert into public.request_history(request_id,entity_type,entity_id,action,actor_id,
    old_status,new_status,note,occurred_at)
  values(v_request.id,'request',v_request.id,'created',v_uid,null,'pending','Sinh viên tạo yêu cầu.',v_now);
  return public._student_request_summary(v_request);
end $$;

revoke all on function public._student_request_actor(),
  public._student_request_summary(public.repair_requests),
  public._student_request_photo_path(text) from public,anon,authenticated;
revoke all on function public.student_list_categories(),public.student_list_requests(),
  public.student_get_request(uuid),public.student_create_request(uuid,text,uuid,text,jsonb),
  public._can_upload_student_request_photo(text),
  public._is_own_staged_student_request_photo(text),
  public._can_delete_student_request_photo(text) from public,anon;
grant execute on function public.student_list_categories(),public.student_list_requests(),
  public.student_get_request(uuid),public.student_create_request(uuid,text,uuid,text,jsonb),
  public._can_upload_student_request_photo(text),
  public._is_own_staged_student_request_photo(text),
  public._can_delete_student_request_photo(text) to authenticated;

create policy student_request_photo_upload on storage.objects for insert to authenticated
with check(bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._can_upload_student_request_photo(name));
create policy student_request_photo_staged_read on storage.objects for select to authenticated
using(bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._is_own_staged_student_request_photo(name));
create policy student_request_photo_staged_delete on storage.objects for delete to authenticated
using(bucket_id = 'repair-images' and owner_id = auth.uid()::text
  and public._can_delete_student_request_photo(name));

comment on function public.student_create_request(uuid,text,uuid,text,jsonb) is
  'DF-007: active student creates an owned request with server room/category snapshots, validated staged photos and one creation history entry; exact UUID retries are idempotent.';
comment on function public.student_list_requests() is
  'DF-008/009: all requests owned by current active student, including former rooms, newest created first.';
comment on function public.student_get_request(uuid) is
  'DF-010: current active student reads only own request, private photo metadata, current technician contact and all results, feedback and history.';
commit;
