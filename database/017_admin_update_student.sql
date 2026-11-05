-- DF-033: Admin cập nhật thông tin và phòng Sinh viên.
-- Apply after 016_admin_create_technician.sql.
begin;

create or replace function public.admin_get_student_edit_details(p_identity_code text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_identity_code text := lower(trim(p_identity_code));
begin
  perform public._admin_account_actor();
  if v_identity_code is null or length(v_identity_code) = 0 then
    raise exception using errcode = '22023', message = 'Mã Sinh viên không được để trống.';
  end if;

  select jsonb_build_object(
    'full_name', p.full_name,
    'phone', p.phone,
    'room', jsonb_build_object(
      'id', r.id,
      'code', r.code,
      'building', r.building,
      'is_active', r.is_active
    )
  )
  into v_result
  from public.profiles p
  left join public.rooms r on r.id = p.room_id
  where lower(trim(p.identity_code)) = v_identity_code
    and p.role = 'student'
    and p.status <> 'revoked';

  if v_result is null then
    raise exception using errcode = 'P0002', message = 'Không tìm thấy Sinh viên có thể cập nhật.';
  end if;
  return v_result;
end $$;

create or replace function public.admin_update_student(
  p_identity_code text,
  p_full_name text,
  p_phone text,
  p_room_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_account_actor();
  v_identity_code text := lower(trim(p_identity_code));
  v_full_name text := trim(p_full_name);
  v_phone text := trim(p_phone);
  v_student public.profiles%rowtype;
  v_room public.rooms%rowtype;
  v_old_room_code text;
  v_now timestamptz := clock_timestamp();
begin
  if v_identity_code is null or length(v_identity_code) = 0 then
    raise exception using errcode = '22023', message = 'Mã Sinh viên không được để trống.';
  end if;
  if v_full_name is null or length(v_full_name) = 0 then
    raise exception using errcode = '22023', message = 'Họ tên Sinh viên không được để trống.';
  end if;
  if v_phone is null or length(v_phone) = 0 then
    raise exception using errcode = '22023', message = 'Số điện thoại không được để trống.';
  end if;
  if v_phone !~ '^(0|\+84)[0-9]{9}$' then
    raise exception using errcode = '22023', message = 'Số điện thoại không đúng định dạng.';
  end if;
  if p_room_id is null then
    raise exception using errcode = '22023', message = 'Vui lòng chọn phòng đang hoạt động.';
  end if;

  select * into v_student
  from public.profiles
  where lower(trim(identity_code)) = v_identity_code
  for update;
  if not found or v_student.role <> 'student' or v_student.status = 'revoked' then
    raise exception using errcode = 'P0002', message = 'Không tìm thấy Sinh viên có thể cập nhật.';
  end if;

  select * into v_room from public.rooms where id = p_room_id for share;
  if not found or not v_room.is_active then
    raise exception using errcode = 'P0002', message = 'Chỉ được chuyển Sinh viên vào phòng đang hoạt động.';
  end if;

  select code into v_old_room_code from public.rooms where id = v_student.room_id;

  -- Identity code only selects the target; neither it nor email is assigned.
  update public.profiles
  set full_name = v_full_name,
      phone = v_phone,
      room_id = v_room.id,
      updated_at = v_now
  where id = v_student.id;

  insert into public.request_history (
    request_id, entity_type, entity_id, action, actor_id,
    old_status, new_status, note, occurred_at
  ) values (
    null,
    'profile',
    v_student.id,
    'update_student',
    v_admin,
    v_student.status::text,
    v_student.status::text,
    'Cập nhật Sinh viên ' || v_student.identity_code || '; phòng ' ||
      coalesce(v_old_room_code, 'chưa gắn') || ' -> ' || v_room.code,
    v_now
  );

  return jsonb_build_object(
    'identity_code', v_student.identity_code,
    'full_name', v_full_name,
    'phone', v_phone,
    'room', jsonb_build_object(
      'id', v_room.id,
      'code', v_room.code,
      'building', v_room.building,
      'is_active', v_room.is_active
    )
  );
end $$;

revoke all on function public.admin_get_student_edit_details(text) from public, anon;
grant execute on function public.admin_get_student_edit_details(text) to authenticated;
revoke all on function public.admin_update_student(text, text, text, uuid) from public, anon;
grant execute on function public.admin_update_student(text, text, text, uuid) to authenticated;

commit;