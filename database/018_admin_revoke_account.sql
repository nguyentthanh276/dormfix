-- DF-036: Admin thu hồi Sinh viên/Kỹ thuật viên, giữ nguyên hồ sơ và lịch sử.
-- Apply after 017_admin_update_student.sql.
begin;

create function public.admin_revoke_account(
  p_identity_code text,
  p_reason text
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_account_actor();
  v_identity_code text := lower(trim(p_identity_code));
  v_reason text := nullif(trim(p_reason), '');
  v_profile public.profiles%rowtype;
  v_now timestamptz := clock_timestamp();
  v_banned_until timestamptz;
begin
  if v_identity_code is null or length(v_identity_code) = 0 then
    raise exception using errcode = '22023', message = 'Mã định danh không được để trống.';
  end if;
  if v_reason is null then
    raise exception using errcode = '22023', message = 'Vui lòng nhập lý do thu hồi.';
  end if;

  -- This lock serializes assignment against revocation: assignment locks the same
  -- profile FOR SHARE and rechecks status before writing the assignment.
  select * into v_profile
  from public.profiles
  where lower(trim(identity_code)) = v_identity_code
  for update;
  if not found or v_profile.role not in ('student', 'technician') then
    raise exception using errcode = 'P0002', message = 'Không tìm thấy tài khoản có thể thu hồi.';
  end if;
  if v_profile.status = 'revoked' then
    raise exception using errcode = 'P0001', message = 'Tài khoản đã được thu hồi.';
  end if;

  if v_profile.role = 'technician' and exists (
    select 1
    from public.repair_requests r
    where r.assigned_technician_id = v_profile.id
      and r.status not in ('completed', 'rejected', 'cancelled')
  ) then
    raise exception using errcode = 'P0001',
      message = 'Không thể thu hồi Kỹ thuật viên còn công việc chưa hoàn tất.';
  end if;

  -- Auth ban blocks new sign-ins while profile status also rejects existing tokens.
  v_banned_until := v_now + interval '100 years';
  update auth.users
  set banned_until = v_banned_until,
      updated_at = v_now
  where id = v_profile.id;

  update public.profiles
  set status = 'revoked', updated_at = v_now
  where id = v_profile.id;

  insert into public.request_history (
    request_id, entity_type, entity_id, action, actor_id,
    old_status, new_status, note, occurred_at
  ) values (
    null,
    'profile',
    v_profile.id,
    'admin_revoke_account',
    v_admin,
    v_profile.status::text,
    'revoked',
    v_reason,
    v_now
  );

  return jsonb_build_object(
    'id', v_profile.id,
    'identity_code', v_profile.identity_code,
    'role', v_profile.role,
    'status', 'revoked',
    'revoked_by', v_admin,
    'revoked_at', v_now,
    'reason', v_reason
  );
end $$;

revoke all on function public.admin_revoke_account(text, text) from public, anon;
grant execute on function public.admin_revoke_account(text, text) to authenticated;

commit;