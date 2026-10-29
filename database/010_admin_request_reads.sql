-- DF-043/044: Admin-only request reads, detail, and combined filters.
-- Adds RPCs over the existing request/history/attachment schema; no new tables.
begin;

create function public.admin_request_filter_options() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_rooms jsonb; v_categories jsonb; v_technicians jsonb;
begin
  if public.current_active_role() is distinct from 'admin'::public.app_role then
    raise exception using errcode = '42501', message = 'ADMIN_ACCESS_REQUIRED';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', q.room_id::text, 'label', q.room_code, 'subtitle', q.building
  ) order by q.room_code), '[]'::jsonb) into v_rooms
  from (
    select distinct r.room_id, room.code as room_code, room.building
    from public.repair_requests r
    join public.rooms room on room.id = r.room_id
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', q.category_id::text, 'label', q.category_name
  ) order by q.category_name), '[]'::jsonb) into v_categories
  from (
    select distinct r.category_id, category.name as category_name
    from public.repair_requests r
    join public.incident_categories category on category.id = r.category_id
  ) q;

  -- DF-044 filters on the current handler, including handlers whose account
  -- was later locked or revoked, so older/current assignments remain findable.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id::text, 'label', p.full_name
  ) order by p.full_name), '[]'::jsonb) into v_technicians
  from (
    select distinct r.assigned_technician_id
    from public.repair_requests r where r.assigned_technician_id is not null
  ) q
  join public.profiles p on p.id = q.assigned_technician_id;

  return jsonb_build_object(
    'rooms', v_rooms, 'categories', v_categories, 'technicians', v_technicians
  );
end $$;

create function public.admin_list_requests(
  p_status public.repair_status default null,
  p_room_id uuid default null,
  p_category_id uuid default null,
  p_technician_id uuid default null,
  p_date_field text default null,
  p_from timestamptz default null,
  p_to_exclusive timestamptz default null,
  p_offset integer default 0,
  p_limit integer default 20
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_rows jsonb;
begin
  if public.current_active_role() is distinct from 'admin'::public.app_role then
    raise exception using errcode = '42501', message = 'ADMIN_ACCESS_REQUIRED';
  end if;
  if p_offset is null or p_offset < 0 or p_limit is null
     or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'INVALID_PAGINATION';
  end if;
  if num_nonnulls(p_date_field, p_from, p_to_exclusive) not in (0, 3) then
    raise exception using errcode = '22023', message = 'DATE_RANGE_INCOMPLETE';
  end if;
  if p_date_field is not null and p_date_field not in ('created_at', 'updated_at') then
    raise exception using errcode = '22023', message = 'INVALID_DATE_FIELD';
  end if;
  if p_from is not null and p_to_exclusive <= p_from then
    raise exception using errcode = '22023', message = 'INVALID_DATE_RANGE';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc, q.id), '[]'::jsonb)
    into v_rows
  from (
    select r.id::text as id, r.request_code, r.title,
      r.room_code_snapshot as room_code,
      r.category_name_snapshot as category_name,
      student.full_name as student_name,
      technician.full_name as technician_name,
      r.status::text as status, r.created_at, r.updated_at
    from public.repair_requests r
    join public.profiles student on student.id = r.student_id
    left join public.profiles technician on technician.id = r.assigned_technician_id
    where (p_status is null or r.status = p_status)
      and (p_room_id is null or r.room_id = p_room_id)
      and (p_category_id is null or r.category_id = p_category_id)
      and (p_technician_id is null or r.assigned_technician_id = p_technician_id)
      and (p_from is null or
        (p_date_field = 'created_at' and r.created_at >= p_from and r.created_at < p_to_exclusive) or
        (p_date_field = 'updated_at' and r.updated_at >= p_from and r.updated_at < p_to_exclusive))
    order by r.created_at desc, r.id
    offset p_offset limit p_limit
  ) q;
  return v_rows;
end $$;

create function public.admin_get_request(p_request_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_request public.repair_requests%rowtype;
  v_student jsonb;
  v_technician jsonb;
  v_attachments jsonb;
  v_results jsonb;
  v_feedback jsonb;
  v_history jsonb;
  v_assignments jsonb;
begin
  if public.current_active_role() is distinct from 'admin'::public.app_role then
    raise exception using errcode = '42501', message = 'ADMIN_ACCESS_REQUIRED';
  end if;
  select * into v_request from public.repair_requests r where r.id = p_request_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'REQUEST_NOT_FOUND';
  end if;

  select jsonb_build_object('full_name', p.full_name, 'status', p.status::text)
    into v_student from public.profiles p where p.id = v_request.student_id;
  select case when p.id is null then null else jsonb_build_object(
    'id', p.id::text, 'full_name', p.full_name, 'status', p.status::text
  ) end into v_technician
    from public.profiles p where p.id = v_request.assigned_technician_id;
  if not found then v_technician := null; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id::text, 'request_id', a.request_id::text,
    'storage_path', a.storage_path, 'mime_type', a.mime_type,
    'size_bytes', a.size_bytes, 'result_id', a.result_id::text,
    'feedback_id', a.feedback_id::text, 'uploaded_by', a.uploaded_by::text,
    'created_at', a.created_at
  ) order by a.created_at, a.id), '[]'::jsonb)
    into v_attachments from public.request_attachments a
    where a.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rr.id::text, 'content', rr.content, 'submitted_at', rr.submitted_at,
    'technician_name', p.full_name
  ) order by rr.submitted_at, rr.id), '[]'::jsonb)
    into v_results from public.repair_results rr
    join public.profiles p on p.id = rr.submitted_by
    where rr.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id::text, 'kind', f.kind, 'reason', f.reason,
    'created_at', f.created_at, 'author_name', p.full_name
  ) order by f.created_at, f.id), '[]'::jsonb)
    into v_feedback from public.request_feedback f
    join public.profiles p on p.id = f.submitted_by
    where f.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', h.id::text, 'action', h.action, 'actor_name', p.full_name,
    'old_status', h.old_status, 'new_status', h.new_status,
    'note', h.note, 'occurred_at', h.occurred_at
  ) order by h.occurred_at, h.id), '[]'::jsonb)
    into v_history from public.request_history h
    join public.profiles p on p.id = h.actor_id
    where h.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id::text, 'technician_id', a.technician_id::text,
    'technician_name', technician.full_name,
    'assigned_by_name', administrator.full_name,
    'assigned_at', a.assigned_at, 'ended_at', a.ended_at,
    'transfer_reason', a.transfer_reason, 'end_reason', a.end_reason
  ) order by a.assigned_at, a.id), '[]'::jsonb)
    into v_assignments from public.request_assignments a
    join public.profiles technician on technician.id = a.technician_id
    join public.profiles administrator on administrator.id = a.assigned_by
    where a.request_id = v_request.id;

  return jsonb_build_object(
    'request', jsonb_build_object(
      'id', v_request.id::text, 'request_code', v_request.request_code,
      'title', v_request.title, 'description', v_request.description,
      'room_code', v_request.room_code_snapshot,
      'building', v_request.building_snapshot,
      'category_name', v_request.category_name_snapshot,
      'status', v_request.status::text, 'created_at', v_request.created_at,
      'updated_at', v_request.updated_at, 'version', v_request.version
    ),
    'student', v_student, 'technician', v_technician,
    'attachments', v_attachments, 'results', v_results,
    'feedback', v_feedback, 'history', v_history, 'assignments', v_assignments
  );
end $$;

revoke all on function public.admin_request_filter_options() from public, anon;
revoke all on function public.admin_list_requests(public.repair_status, uuid, uuid, uuid, text, timestamptz, timestamptz, integer, integer) from public, anon;
revoke all on function public.admin_get_request(uuid) from public, anon;
grant execute on function public.admin_request_filter_options() to authenticated;
grant execute on function public.admin_list_requests(public.repair_status, uuid, uuid, uuid, text, timestamptz, timestamptz, integer, integer) to authenticated;
grant execute on function public.admin_get_request(uuid) to authenticated;

commit;
