-- DF-037: Admin khôi phục tài khoản đã thu hồi, không tạo Auth/profile mới.
-- Apply after 018_admin_revoke_account.sql.
begin;

create function public.admin_restore_account(
  p_identity_code text,
  p_room_id uuid default null
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_account_actor();
  v_identity_code text := lower(trim(p_identity_code));
  v_profile public.profiles%rowtype;
  v_room public.rooms%rowtype;
  v_auth_user_id uuid;
  v_now timestamptz := clock_timestamp();
  v_note text;
begin
  if v_identity_code is null or length(v_identity_code) = 0 then
    raise exception using errcode = '22023', message = 'Mã định danh không được để trống.';
  end if;

  select * into v_profile
  from public.profiles
  where lower(trim(identity_code)) = v_identity_code
  for update;
  if not found or v_profile.role not in ('student', 'technician') then
    raise exception using errcode = 'P0002', message = 'Không tìm thấy tài khoản có thể khôi phục.';
  end if;
  if v_profile.status <> 'revoked' then
    raise exception using errcode = 'P0001', message = 'Tài khoản chưa bị thu hồi.';
  end if;

  select id into v_auth_user_id
  from auth.users
  where id = v_profile.id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Không tìm thấy tài khoản xác thực để khôi phục.';
  end if;

  if v_profile.role = 'student' then
    if p_room_id is null then
      raise exception using errcode = '22023', message = 'Vui lòng chọn phòng đang hoạt động cho Sinh viên.';
    end if;
    select * into v_room
    from public.rooms
    where id = p_room_id and is_active
    for share;
    if not found then
      raise exception using errcode = 'P0002', message = 'Chỉ được khôi phục Sinh viên vào phòng đang hoạt động.';
    end if;
    v_note := 'Khôi phục Sinh viên ' || v_profile.identity_code || ' gắn phòng ' || v_room.code;
  else
    if p_room_id is not null then
      raise exception using errcode = '22023', message = 'Kỹ thuật viên không được gắn phòng KTX.';
    end if;
    if exists (
      select 1
      from public.repair_requests r
      where r.assigned_technician_id = v_profile.id
        and r.status not in ('completed', 'rejected', 'cancelled')
    ) then
      raise exception using errcode = 'P0001',
        message = 'Không thể khôi phục Kỹ thuật viên còn công việc chưa hoàn tất.';
    end if;
    v_note := 'Khôi phục Kỹ thuật viên ' || v_profile.identity_code;
  end if;

  update public.profiles
  set status = 'active',
      room_id = case when v_profile.role = 'student' then v_room.id else null end,
      updated_at = v_now
  where id = v_profile.id;

  update auth.users
  set banned_until = null,
      updated_at = v_now
  where id = v_auth_user_id;

  insert into public.request_history (
    request_id, entity_type, entity_id, action, actor_id,
    old_status, new_status, note, occurred_at
  ) values (
    null, 'profile', v_profile.id, 'admin_restore_account', v_admin,
    'revoked', 'active', v_note, v_now
  );

  return jsonb_build_object(
    'id', v_profile.id,
    'identity_code', v_profile.identity_code,
    'role', v_profile.role,
    'status', 'active',
    'room_id', case when v_profile.role = 'student' then v_room.id else null end,
    'must_change_password', v_profile.must_change_password,
    'restored_by', v_admin,
    'restored_at', v_now
  );
end $$;

revoke all on function public.admin_restore_account(text, uuid) from public, anon;
grant execute on function public.admin_restore_account(text, uuid) to authenticated;

commit;