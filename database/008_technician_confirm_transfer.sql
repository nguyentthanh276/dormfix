-- DF-025. Apply once after 007_technician_continue_rework.sql.
-- Confirm only a pending transfer of an in-progress request. Admin transfer
-- creation is a separate workflow and must insert a fresh assignment each time.
begin;

create or replace function public._technician_workflow_capabilities(p_request_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_request public.repair_requests%rowtype; v_assignment public.request_assignments%rowtype;
begin
  select * into v_request from public.repair_requests
    where id = p_request_id and assigned_technician_id = auth.uid();
  if not found or public.current_active_role() is distinct from 'technician'::public.app_role then
    return jsonb_build_object('can_start', false, 'can_continue', false, 'can_confirm_transfer', false, 'can_submit_result', false, 'blocked_reason', 'READ_ONLY');
  end if;
  select * into v_assignment from public.request_assignments
    where request_id = v_request.id and technician_id = auth.uid() and ended_at is null;
  if not found then
    return jsonb_build_object('can_start', false, 'can_continue', false, 'can_confirm_transfer', false, 'can_submit_result', false, 'blocked_reason', 'ASSIGNMENT_NOT_READY');
  end if;
  if v_request.status = 'assigned' then
    return jsonb_build_object('can_start', true, 'can_continue', false, 'can_confirm_transfer', false, 'can_submit_result', false, 'blocked_reason', null);
  elsif v_request.status = 'awaiting_rework' then
    if v_assignment.needs_transfer_confirmation then
      return jsonb_build_object('can_start', false, 'can_continue', false, 'can_confirm_transfer', false, 'can_submit_result', false, 'blocked_reason', 'TRANSFER_CONFIRMATION_REQUIRED');
    end if;
    return jsonb_build_object('can_start', false, 'can_continue', true, 'can_confirm_transfer', false, 'can_submit_result', false, 'blocked_reason', 'CONTINUE_REQUIRED');
  elsif v_request.status = 'in_progress' then
    if v_assignment.needs_transfer_confirmation then
      return jsonb_build_object('can_start', false, 'can_continue', false, 'can_confirm_transfer', true, 'can_submit_result', false, 'blocked_reason', 'TRANSFER_CONFIRMATION_REQUIRED');
    elsif not (coalesce(v_assignment.started_at >= v_assignment.assigned_at, false)
       or coalesce(v_assignment.transfer_confirmed_at >= v_assignment.assigned_at, false)) then
      return jsonb_build_object('can_start', false, 'can_continue', false, 'can_confirm_transfer', false, 'can_submit_result', false, 'blocked_reason', 'START_REQUIRED');
    end if;
    return jsonb_build_object('can_start', false, 'can_continue', false, 'can_confirm_transfer', false, 'can_submit_result', true, 'blocked_reason', null);
  end if;
  return jsonb_build_object('can_start', false, 'can_continue', false, 'can_confirm_transfer', false, 'can_submit_result', false, 'blocked_reason', 'READ_ONLY');
end $$;

create function public.technician_confirm_transfer(p_request_id uuid, p_expected_version integer) returns jsonb
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
  if v_request.status <> 'in_progress' or v_request.version <> p_expected_version then
    raise exception using errcode = 'P0001', message = 'JOB_STATE_CONFLICT';
  end if;
  select * into v_assignment from public.request_assignments
    where request_id = v_request.id and technician_id = v_uid and ended_at is null for update;
  if not found then raise exception using errcode = 'P0001', message = 'ASSIGNMENT_NOT_READY'; end if;
  if not v_assignment.needs_transfer_confirmation then
    raise exception using errcode = 'P0001', message = 'JOB_STATE_CONFLICT';
  end if;
  v_now := clock_timestamp();
  -- Malformed future-dated assignments cannot yield valid work proof now.
  if v_assignment.assigned_at > v_now then
    raise exception using errcode = 'P0001', message = 'JOB_STATE_CONFLICT';
  end if;
  update public.request_assignments set needs_transfer_confirmation = false, transfer_confirmed_at = v_now
    where id = v_assignment.id;
  update public.repair_requests set version = version + 1, updated_at = v_now
    where id = v_request.id returning * into v_request;
  insert into public.request_history
    (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, occurred_at)
    values (v_request.id, 'request', v_request.id, 'transfer_confirmed', v_uid, 'in_progress', 'in_progress', v_now);
  return jsonb_build_object('request_id', v_request.id, 'status', v_request.status, 'version', v_request.version);
end $$;

revoke all on function public._technician_workflow_capabilities(uuid) from public, anon, authenticated;
revoke all on function public.technician_confirm_transfer(uuid, integer) from public, anon;
grant execute on function public.technician_confirm_transfer(uuid, integer) to authenticated;

commit;
