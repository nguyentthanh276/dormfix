-- DF-038: Admin resets an existing Student/Technician password.
-- Apply after 019_admin_restore_account.sql.
begin;

create function public.admin_reset_account_password(p_identity_code text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_account_actor();
  v_identity_code text := lower(trim(p_identity_code));
  v_profile public.profiles%rowtype;
  v_temp_password text;
  v_encrypted_password text;
  v_now timestamptz := clock_timestamp();
begin
  if v_identity_code is null or length(v_identity_code) = 0 then
    raise exception using errcode = '22023', message = 'Mã định danh không được để trống.';
  end if;

  select * into v_profile
  from public.profiles
  where lower(trim(identity_code)) = v_identity_code
  for update;
  if not found or v_profile.role not in ('student', 'technician') then
    raise exception using errcode = 'P0002', message = 'Không tìm thấy tài khoản hợp lệ.';
  end if;

  v_temp_password := 'DF@' || replace(gen_random_uuid()::text, '-', '');
  begin
    v_encrypted_password := extensions.crypt(v_temp_password, extensions.gen_salt('bf', 10));
  exception when undefined_function then
    begin
      v_encrypted_password := public.crypt(v_temp_password, public.gen_salt('bf', 10));
    exception when undefined_function then
      v_encrypted_password := null;
    end;
  end;
  if v_encrypted_password is null then
    raise exception using errcode = '55000', message = 'Không thể tạo mật khẩu cho tài khoản.';
  end if;

  update auth.users
  set encrypted_password = v_encrypted_password,
      updated_at = v_now
  where id = v_profile.id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Không tìm thấy tài khoản xác thực.';
  end if;

  update public.profiles
  set must_change_password = true,
      updated_at = v_now
  where id = v_profile.id;

  -- Remove refresh sessions; already-issued JWTs remain subject to the DB password gate.
  delete from auth.sessions where user_id = v_profile.id;

  insert into public.request_history (
    request_id, entity_type, entity_id, action, actor_id,
    old_status, new_status, note, occurred_at
  ) values (
    null,
    'profile',
    v_profile.id,
    'admin_reset_password',
    v_admin,
    v_profile.status::text,
    v_profile.status::text,
    'Admin đặt mật khẩu tạm mới; yêu cầu đổi ở lần đăng nhập kế tiếp.',
    v_now
  );

  return jsonb_build_object(
    'id', v_profile.id,
    'identity_code', v_profile.identity_code,
    'full_name', v_profile.full_name,
    'role', v_profile.role,
    'status', v_profile.status,
    'must_change_password', true,
    'temporary_password', v_temp_password
  );
end $$;

revoke all on function public.admin_reset_account_password(text) from public, anon;
grant execute on function public.admin_reset_account_password(text) to authenticated;

commit;