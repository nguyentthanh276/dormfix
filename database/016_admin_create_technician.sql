-- DF-032: Admin tạo tài khoản Kỹ thuật viên.
-- Apply after 015_admin_create_student.sql.
begin;

create or replace function public.admin_create_technician(
  p_identity_code text,
  p_full_name text,
  p_email text,
  p_phone text,
  p_temporary_password text default null
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_account_actor();
  v_identity_code text := trim(p_identity_code);
  v_full_name text := trim(p_full_name);
  v_email text := lower(trim(p_email));
  v_phone text := trim(p_phone);
  v_user_id uuid;
  v_temp_password text;
  v_encrypted_password text;
  v_now timestamptz := clock_timestamp();
begin
  if v_identity_code is null or length(v_identity_code) = 0 then
    raise exception using errcode = '22023', message = 'Mã Kỹ thuật viên không được để trống.';
  end if;
  if v_full_name is null or length(v_full_name) = 0 then
    raise exception using errcode = '22023', message = 'Họ tên Kỹ thuật viên không được để trống.';
  end if;
  if v_email is null or length(v_email) = 0 then
    raise exception using errcode = '22023', message = 'Email không được để trống.';
  end if;
  if v_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    raise exception using errcode = '22023', message = 'Email không đúng định dạng.';
  end if;
  if v_phone is null or length(v_phone) = 0 then
    raise exception using errcode = '22023', message = 'Số điện thoại không được để trống.';
  end if;
  if v_phone !~ '^(0|\+84)[0-9]{9}$' then
    raise exception using errcode = '22023', message = 'Số điện thoại không đúng định dạng.';
  end if;

  -- The unique profiles indexes include every role and account status.
  if exists (
    select 1 from public.profiles
    where lower(trim(identity_code)) = lower(v_identity_code)
  ) then
    raise exception using errcode = '23505', message = 'Mã Kỹ thuật viên đã tồn tại trên hệ thống.';
  end if;
  if exists (
    select 1 from public.profiles
    where lower(trim(email)) = v_email
  ) or exists (
    select 1 from auth.users
    where lower(trim(email)) = v_email
  ) then
    raise exception using errcode = '23505', message = 'Email đã tồn tại trên hệ thống.';
  end if;

  if p_temporary_password is not null and length(trim(p_temporary_password)) >= 6 then
    v_temp_password := trim(p_temporary_password);
  else
    v_temp_password := 'DF@' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 7);
  end if;

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

  v_user_id := gen_random_uuid();
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    v_encrypted_password,
    v_now,
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    jsonb_build_object('full_name', v_full_name),
    v_now,
    v_now
  );

  insert into public.profiles (
    id, identity_code, full_name, email, phone, role, status,
    room_id, must_change_password, created_at, updated_at
  ) values (
    v_user_id, v_identity_code, v_full_name, v_email, v_phone, 'technician', 'active',
    null, true, v_now, v_now
  );

  insert into public.request_history (
    request_id, entity_type, entity_id, action, actor_id,
    old_status, new_status, note, occurred_at
  ) values (
    null,
    'profile',
    v_user_id,
    'create_technician',
    v_admin,
    null,
    'active',
    'Tạo tài khoản Kỹ thuật viên ' || v_identity_code,
    v_now
  );

  return jsonb_build_object(
    'id', v_user_id,
    'identity_code', v_identity_code,
    'full_name', v_full_name,
    'email', v_email,
    'phone', v_phone,
    'role', 'technician',
    'status', 'active',
    'must_change_password', true,
    'temporary_password', v_temp_password
  );
end $$;

revoke all on function public.admin_create_technician(text, text, text, text, text)
  from public, anon;
grant execute on function public.admin_create_technician(text, text, text, text, text)
  to authenticated;

commit;