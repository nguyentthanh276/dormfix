-- DF-031: Admin tạo tài khoản Sinh viên và gắn phòng.
begin;

-- Helper kiểm tra quyền Admin đang hoạt động
create or replace function public._admin_account_actor() returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'Vui lòng đăng nhập lại.';
  end if;
  select * into v_profile from public.profiles where id = v_uid for share;
  if not found or v_profile.role <> 'admin' or v_profile.status <> 'active'
     or v_profile.must_change_password then
    raise exception using errcode = '42501', message = 'Chỉ Admin đang hoạt động mới được thực hiện thao tác này.';
  end if;
  return v_uid;
end $$;

-- RPC lấy danh sách phòng đang hoạt động phục vụ gán phòng cho Sinh viên
create or replace function public.admin_get_active_rooms()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rooms jsonb;
begin
  perform public._admin_account_actor();
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'code', r.code,
    'building', r.building,
    'is_active', r.is_active
  ) order by r.building, r.code), '[]'::jsonb)
  into v_rooms
  from public.rooms r
  where r.is_active = true;

  return v_rooms;
end $$;

-- RPC DF-031: Admin tạo tài khoản Sinh viên và gắn phòng
create or replace function public.admin_create_student(
  p_identity_code text,
  p_full_name text,
  p_email text,
  p_phone text,
  p_room_id uuid,
  p_temporary_password text default null
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_account_actor();
  v_identity_code text := trim(p_identity_code);
  v_full_name text := trim(p_full_name);
  v_email text := lower(trim(p_email));
  v_phone text := trim(p_phone);
  v_room public.rooms%rowtype;
  v_user_id uuid;
  v_temp_password text;
  v_encrypted_password text;
  v_now timestamptz := clock_timestamp();
begin
  -- 1. Kiểm tra bắt buộc các trường dữ liệu
  if v_identity_code is null or length(v_identity_code) = 0 then
    raise exception using errcode = '22023', message = 'Mã Sinh viên không được để trống.';
  end if;

  if v_full_name is null or length(v_full_name) = 0 then
    raise exception using errcode = '22023', message = 'Họ tên Sinh viên không được để trống.';
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

  -- Số điện thoại đúng định dạng (10 chữ số bắt đầu bằng 0, hoặc +84 tiếp theo 9 chữ số)
  if v_phone !~ '^(0|\+84)[0-9]{9}$' then
    raise exception using errcode = '22023', message = 'Số điện thoại không đúng định dạng.';
  end if;

  if p_room_id is null then
    raise exception using errcode = '22023', message = 'Vui lòng chọn phòng cho Sinh viên.';
  end if;

  -- 2. Kiểm tra phòng: phòng tồn tại và đang hoạt động
  select * into v_room from public.rooms where id = p_room_id for share;
  if not found then
    raise exception using errcode = 'P0002', message = 'Phòng không tồn tại.';
  end if;

  if not v_room.is_active then
    raise exception using errcode = '22023', message = 'Chỉ được gắn Sinh viên vào phòng đang hoạt động.';
  end if;

  -- 3. Kiểm tra tính duy nhất trên toàn hệ thống (kể cả tài khoản bị thu hồi)
  if exists (
    select 1 from public.profiles
    where lower(trim(identity_code)) = lower(v_identity_code)
  ) then
    raise exception using errcode = '23505', message = 'Mã Sinh viên đã tồn tại trên hệ thống.';
  end if;

  if exists (
    select 1 from public.profiles
    where lower(trim(email)) = v_email
  ) then
    raise exception using errcode = '23505', message = 'Email đã tồn tại trên hệ thống.';
  end if;

  if exists (
    select 1 from auth.users
    where lower(trim(email)) = v_email
  ) then
    raise exception using errcode = '23505', message = 'Email đã tồn tại trong hệ thống xác thực.';
  end if;

  -- 4. Tạo mật khẩu tạm
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

  -- 5. Tạo Auth user
  v_user_id := gen_random_uuid();
  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
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

  -- 6. Tạo Profile (must_change_password = true, status = active, role = student)
  insert into public.profiles (
    id,
    identity_code,
    full_name,
    email,
    phone,
    role,
    status,
    room_id,
    must_change_password,
    created_at,
    updated_at
  ) values (
    v_user_id,
    v_identity_code,
    v_full_name,
    v_email,
    v_phone,
    'student',
    'active',
    v_room.id,
    true,
    v_now,
    v_now
  );

  -- 7. Ghi nhận lịch sử thao tác quản trị
  insert into public.request_history (
    request_id,
    entity_type,
    entity_id,
    action,
    actor_id,
    old_status,
    new_status,
    note,
    occurred_at
  ) values (
    null,
    'profile',
    v_user_id,
    'create_student',
    v_admin,
    null,
    'active',
    'Tạo tài khoản Sinh viên ' || v_identity_code || ' gắn phòng ' || v_room.code,
    v_now
  );

  -- 8. Trả về thông tin sinh viên kèm mật khẩu tạm
  return jsonb_build_object(
    'id', v_user_id,
    'identity_code', v_identity_code,
    'full_name', v_full_name,
    'email', v_email,
    'phone', v_phone,
    'role', 'student',
    'status', 'active',
    'must_change_password', true,
    'temporary_password', v_temp_password,
    'room', jsonb_build_object(
      'id', v_room.id,
      'code', v_room.code,
      'building', v_room.building,
      'is_active', v_room.is_active
    )
  );
end $$;

-- Ràng buộc không cho phép sửa đổi identity_code và email sau khi tạo
create or replace function public.profiles_immutable_fields_check()
returns trigger language plpgsql as $$
begin
  if new.identity_code <> old.identity_code then
    raise exception using errcode = '22023', message = 'Mã định danh không được phép thay đổi.';
  end if;
  if lower(trim(new.email)) <> lower(trim(old.email)) then
    raise exception using errcode = '22023', message = 'Email không được phép thay đổi.';
  end if;
  return new;
end $$;

drop trigger if exists trg_profiles_immutable_fields on public.profiles;
create trigger trg_profiles_immutable_fields
before update on public.profiles
for each row execute function public.profiles_immutable_fields_check();

-- Phân quyền
revoke all on function public._admin_account_actor() from public, anon, authenticated;
revoke all on function public.admin_get_active_rooms() from public, anon;
grant execute on function public.admin_get_active_rooms() to authenticated;

revoke all on function public.admin_create_student(text, text, text, text, uuid, text) from public, anon;
grant execute on function public.admin_create_student(text, text, text, text, uuid, text) to authenticated;

commit;

