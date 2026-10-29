-- DF-045/046: Admin request mutations. Apply after 010_admin_request_reads.sql.
-- Every RPC is one transaction; request/profile locks serialize concurrent changes.
begin;

create function public._admin_request_actor() returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'Vui lòng đăng nhập lại.';
  end if;
  select * into v_profile from public.profiles where id = v_uid for share;
  if not found or v_profile.role <> 'admin' or v_profile.status <> 'active'
     or v_profile.must_change_password then
    raise exception using errcode = '42501', message = 'Chỉ Admin đang hoạt động mới được thao tác.';
  end if;
  return v_uid;
end $$;

-- Keep DF-045/046/047/048 Admin transition rules in one server-side place.
create function public.admin_request_transition_allowed(
  p_action text, p_status public.repair_status
) returns boolean
language sql immutable set search_path = '' as $$
  select case p_action
    when 'assign' then p_status = 'pending'::public.repair_status
    when 'reject' then p_status = 'pending'::public.repair_status
    when 'transfer' then p_status in (
      'assigned'::public.repair_status, 'in_progress'::public.repair_status,
      'awaiting_rework'::public.repair_status)
    when 'confirm_revoked_student' then p_status = 'awaiting_confirmation'::public.repair_status
    when 'request_rework_revoked_student' then p_status = 'awaiting_confirmation'::public.repair_status
    else false
  end
$$;

create function public.admin_request_active_technicians() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_rows jsonb;
begin
  perform public._admin_request_actor();
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id::text, 'label', p.full_name)
    order by p.full_name, p.identity_code), '[]'::jsonb) into v_rows
  from public.profiles p
  where p.role = 'technician' and p.status = 'active';
  -- First-login password change does not make an active account ineligible for assignment.
  return v_rows;
end $$;

create function public.admin_assign_request(p_request_id uuid, p_technician_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_request public.repair_requests%rowtype;
  v_technician public.profiles%rowtype;
  v_old public.request_assignments%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  select * into v_request from public.repair_requests where id = p_request_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Không tìm thấy yêu cầu sửa chữa.'; end if;
  if not public.admin_request_transition_allowed('assign', v_request.status) then
    raise exception using errcode = 'P0001', message = 'Yêu cầu không còn ở trạng thái Chờ tiếp nhận; chưa có thay đổi nào được lưu.';
  end if;
  select * into v_technician from public.profiles where id = p_technician_id for share;
  if not found or v_technician.role <> 'technician' or v_technician.status <> 'active' then
    raise exception using errcode = '22023', message = 'Chỉ có thể phân công Kỹ thuật viên đang hoạt động.';
  end if;
  select * into v_old from public.request_assignments
    where request_id = v_request.id and ended_at is null for update;
  if found then
    update public.request_assignments set ended_at = v_now,
      end_reason = 'Được Admin phân công lại.' where id = v_old.id;
  end if;
  insert into public.request_assignments
    (request_id, technician_id, assigned_by, assigned_at, request_code_snapshot,
     title_snapshot, room_code_snapshot)
  values (v_request.id, v_technician.id, v_admin, v_now, v_request.request_code,
    v_request.title, v_request.room_code_snapshot);
  update public.repair_requests set assigned_technician_id = v_technician.id,
    status = 'assigned', version = version + 1, updated_at = v_now
    where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
  values (v_request.id, 'request', v_request.id, 'admin_assigned', v_admin,
    'pending', 'assigned', v_technician.full_name, v_now);
  return jsonb_build_object('request_id', v_request.id, 'status', v_request.status,
    'technician_id', v_technician.id, 'version', v_request.version);
end $$;

create function public.admin_reject_request(p_request_id uuid, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_request public.repair_requests%rowtype;
  v_reason text := nullif(trim(p_reason), '');
  v_now timestamptz := clock_timestamp();
begin
  if v_reason is null then raise exception using errcode = '22023', message = 'Vui lòng nhập lý do từ chối.'; end if;
  select * into v_request from public.repair_requests where id = p_request_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Không tìm thấy yêu cầu sửa chữa.'; end if;
  if not public.admin_request_transition_allowed('reject', v_request.status) then
    raise exception using errcode = 'P0001', message = 'Chỉ được từ chối yêu cầu đang Chờ tiếp nhận.';
  end if;
  update public.repair_requests set status = 'rejected', version = version + 1,
    updated_at = v_now where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
  values (v_request.id, 'request', v_request.id, 'admin_rejected', v_admin,
    'pending', 'rejected', v_reason, v_now);
  return jsonb_build_object('request_id', v_request.id, 'status', v_request.status,
    'version', v_request.version);
end $$;

revoke all on function public._admin_request_actor() from public, anon, authenticated;
revoke all on function public.admin_request_transition_allowed(text, public.repair_status) from public, anon, authenticated;
revoke all on function public.admin_request_active_technicians() from public, anon;
revoke all on function public.admin_assign_request(uuid, uuid) from public, anon;
revoke all on function public.admin_reject_request(uuid, text) from public, anon;
grant execute on function public.admin_request_active_technicians() to authenticated;
grant execute on function public.admin_assign_request(uuid, uuid) to authenticated;
grant execute on function public.admin_reject_request(uuid, text) to authenticated;

commit;
