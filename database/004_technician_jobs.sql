-- DF-020 / DF-022: current-technician job reads and authenticated private images.
-- Apply once after 001_schema.sql and 003_get_my_profile.sql. No workflow writes.
begin;

create function public.technician_list_jobs() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_jobs jsonb;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;
  if public.current_active_role() is distinct from 'technician'::public.app_role then
    raise exception using errcode = '42501', message = 'TECHNICIAN_ACCESS_DENIED';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'request_code', r.request_code, 'title', r.title,
    'description', r.description, 'room_code', r.room_code_snapshot,
    'building', r.building_snapshot, 'category_name', r.category_name_snapshot,
    'status', r.status, 'created_at', r.created_at, 'updated_at', r.updated_at,
    'version', r.version
  ) order by r.updated_at desc, r.id desc), '[]'::jsonb)
  into v_jobs
  from public.repair_requests r where r.assigned_technician_id = v_uid;
  return v_jobs;
end $$;

create function public.technician_get_job(p_request_id uuid) returns jsonb
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
    'feedback', v_feedback, 'history', v_history, 'assignments', v_assignments
  );
end $$;

revoke all on function public.technician_list_jobs() from public, anon;
revoke all on function public.technician_get_job(uuid) from public, anon;
grant execute on function public.technician_list_jobs() to authenticated;
grant execute on function public.technician_get_job(uuid) to authenticated;
comment on function public.technician_list_jobs() is
 'DF-020: active, password-cleared technician only; all currently assigned jobs, newest updated first.';
comment on function public.technician_get_job(uuid) is
 'DF-022: full read-only job detail for its current technician; no access from former assignments.';

-- Never silently turn an existing public/unrestricted bucket into a private one.
-- A configuration mismatch aborts this transaction for explicit operator review.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('repair-images', 'repair-images', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
do $$
declare
  v_bucket storage.buckets%rowtype;
  v_mimes text[] := array['image/jpeg', 'image/png', 'image/webp'];
begin
  select * into strict v_bucket from storage.buckets where id = 'repair-images';
  if v_bucket.public is distinct from false
     or v_bucket.file_size_limit is distinct from 5242880::bigint
     or v_bucket.allowed_mime_types is null
     or not (v_bucket.allowed_mime_types @> v_mimes and v_bucket.allowed_mime_types <@ v_mimes) then
    raise exception 'REPAIR_IMAGES_BUCKET_CONFIG_MISMATCH: inspect existing bucket; expected private, 5242880 bytes, JPEG/PNG/WebP only';
  end if;
end $$;

create policy repair_images_authorized_read on storage.objects
for select to authenticated using (
  bucket_id = 'repair-images' and exists (
    select 1 from public.request_attachments a
    where a.storage_path = storage.objects.name
      and public.can_read_request(a.request_id)
  )
);
-- No upload, update, delete, workflow mutation or new public-table grant.
commit;
