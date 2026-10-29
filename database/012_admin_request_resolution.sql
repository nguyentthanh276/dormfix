-- DF-047/048: Admin technician changes and revoked-student resolution.
-- Apply after 011_admin_request_workflow.sql; no legacy Student/Technician RPCs changed.
begin;

create function public.admin_transfer_request(
  p_request_id uuid, p_new_technician_id uuid, p_reason text
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_request public.repair_requests%rowtype;
  v_technician public.profiles%rowtype;
  v_old_assignment public.request_assignments%rowtype;
  v_old_name text;
  v_reason text := nullif(trim(p_reason), '');
  v_now timestamptz := clock_timestamp();
begin
  if v_reason is null then raise exception using errcode = '22023', message = 'Vui lòng nhập lý do đổi Kỹ thuật viên.'; end if;
  select * into v_request from public.repair_requests where id = p_request_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Không tìm thấy yêu cầu sửa chữa.'; end if;
  if not public.admin_request_transition_allowed('transfer', v_request.status) then
    raise exception using errcode = 'P0001', message = 'Không thể đổi Kỹ thuật viên ở trạng thái hiện tại; yêu cầu có thể đã bị hủy.';
  end if;
  if v_request.assigned_technician_id = p_new_technician_id then
    raise exception using errcode = '22023', message = 'Kỹ thuật viên mới phải khác người đang được giao.';
  end if;
  select * into v_technician from public.profiles where id = p_new_technician_id for share;
  if not found or v_technician.role <> 'technician' or v_technician.status <> 'active' then
    raise exception using errcode = '22023', message = 'Chỉ có thể chuyển cho Kỹ thuật viên đang hoạt động.';
  end if;
  select * into v_old_assignment from public.request_assignments
    where request_id = v_request.id and ended_at is null for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'Không tìm thấy phân công hiện tại; không thể đổi Kỹ thuật viên.';
  end if;
  select full_name into v_old_name from public.profiles where id = v_old_assignment.technician_id;
  update public.request_assignments set ended_at = v_now, end_reason = v_reason
    where id = v_old_assignment.id;
  insert into public.request_assignments
    (request_id, technician_id, assigned_by, assigned_at, transfer_reason,
     needs_transfer_confirmation, request_code_snapshot, title_snapshot, room_code_snapshot)
  values (v_request.id, v_technician.id, v_admin, v_now, v_reason,
    v_request.status = 'in_progress', v_request.request_code, v_request.title,
    v_request.room_code_snapshot);
  update public.repair_requests set assigned_technician_id = v_technician.id,
    version = version + 1, updated_at = v_now where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
  values (v_request.id, 'request', v_request.id, 'admin_transferred', v_admin,
    v_request.status::text, v_request.status::text,
    'Từ ' || coalesce(v_old_name, 'Kỹ thuật viên cũ') || ' sang ' || v_technician.full_name || '. Lý do: ' || v_reason,
    v_now);
  return jsonb_build_object('request_id', v_request.id, 'status', v_request.status,
    'technician_id', v_technician.id, 'version', v_request.version);
end $$;

create function public.admin_confirm_revoked_student_request(p_request_id uuid, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_request public.repair_requests%rowtype;
  v_student public.profiles%rowtype;
  v_note text := nullif(trim(p_note), '');
  v_now timestamptz := clock_timestamp();
begin
  if v_note is null then raise exception using errcode = '22023', message = 'Vui lòng nhập ghi chú xác nhận hoàn tất.'; end if;
  select * into v_request from public.repair_requests where id = p_request_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Không tìm thấy yêu cầu sửa chữa.'; end if;
  if not public.admin_request_transition_allowed('confirm_revoked_student', v_request.status) then
    raise exception using errcode = 'P0001', message = 'Yêu cầu không còn ở trạng thái Chờ xác nhận.';
  end if;
  select * into v_student from public.profiles where id = v_request.student_id for share;
  if not found or v_student.status <> 'revoked' then
    raise exception using errcode = 'P0001', message = 'Chỉ xử lý thay khi tài khoản Sinh viên đang Đã thu hồi.';
  end if;
  update public.repair_requests set status = 'completed', completed_at = v_now,
    version = version + 1, updated_at = v_now where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
  values (v_request.id, 'request', v_request.id, 'admin_confirmed_revoked_student', v_admin,
    'awaiting_confirmation', 'completed', v_note, v_now);
  return jsonb_build_object('request_id', v_request.id, 'status', v_request.status,
    'version', v_request.version);
end $$;

create function public.admin_request_rework_revoked_student_request(p_request_id uuid, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_request public.repair_requests%rowtype;
  v_student public.profiles%rowtype;
  v_reason text := nullif(trim(p_reason), '');
  v_now timestamptz := clock_timestamp();
begin
  if v_reason is null then raise exception using errcode = '22023', message = 'Vui lòng nhập lý do yêu cầu sửa lại.'; end if;
  select * into v_request from public.repair_requests where id = p_request_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Không tìm thấy yêu cầu sửa chữa.'; end if;
  if not public.admin_request_transition_allowed('request_rework_revoked_student', v_request.status) then
    raise exception using errcode = 'P0001', message = 'Yêu cầu không còn ở trạng thái Chờ xác nhận.';
  end if;
  select * into v_student from public.profiles where id = v_request.student_id for share;
  if not found or v_student.status <> 'revoked' then
    raise exception using errcode = 'P0001', message = 'Chỉ xử lý thay khi tài khoản Sinh viên đang Đã thu hồi.';
  end if;
  update public.repair_requests set status = 'awaiting_rework',
    version = version + 1, updated_at = v_now where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
  values (v_request.id, 'request', v_request.id, 'admin_rework_for_revoked_student', v_admin,
    'awaiting_confirmation', 'awaiting_rework', v_reason, v_now);
  return jsonb_build_object('request_id', v_request.id, 'status', v_request.status,
    'technician_id', v_request.assigned_technician_id, 'version', v_request.version);
end $$;

revoke all on function public.admin_transfer_request(uuid, uuid, text) from public, anon;
revoke all on function public.admin_confirm_revoked_student_request(uuid, text) from public, anon;
revoke all on function public.admin_request_rework_revoked_student_request(uuid, text) from public, anon;
grant execute on function public.admin_transfer_request(uuid, uuid, text) to authenticated;
grant execute on function public.admin_confirm_revoked_student_request(uuid, text) to authenticated;
grant execute on function public.admin_request_rework_revoked_student_request(uuid, text) to authenticated;

commit;
