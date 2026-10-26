-- DF-006 & DF-019: Cập nhật số điện thoại cho Sinh viên và Kỹ thuật viên
begin;

create or replace function public.update_my_phone(p_phone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_trimmed text := trim(p_phone);
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  if v_trimmed is null or length(v_trimmed) = 0 then
    raise exception using errcode = '22023', message = 'PHONE_REQUIRED';
  end if;

  -- Chỉ cho phép cập nhật số điện thoại của chính người gọi đang active
  update public.profiles
  set phone = v_trimmed, updated_at = now()
  where id = v_uid and status = 'active';

  if not found then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;

  return public.get_my_profile();
end $$;

revoke all on function public.update_my_phone(text) from public, anon;
grant execute on function public.update_my_phone(text) to authenticated;

comment on function public.update_my_phone(text) is
  'Cập nhật số điện thoại của chính tài khoản đang đăng nhập. Trả về hồ sơ mới nhất.';

commit;
