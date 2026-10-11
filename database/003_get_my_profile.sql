-- Authenticated callers can read only their own profile, including the password gate.
begin;
create or replace function public.get_my_profile() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_room jsonb;
begin
  if v_uid is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;
  select * into v_profile from public.profiles where id = v_uid;
  if not found then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  -- A blocked user sees only the information required to sign out.
  if v_profile.status <> 'active' then
    return jsonb_build_object('id', v_uid, 'status', v_profile.status,
      'can_access', false, 'must_change_password', v_profile.must_change_password);
  end if;
  if v_profile.room_id is not null then
    select jsonb_build_object('id', r.id, 'code', r.code,
      'building', r.building, 'is_active', r.is_active)
    into v_room from public.rooms r where r.id = v_profile.room_id;
  end if;
  return jsonb_build_object(
    'id', v_profile.id, 'identity_code', v_profile.identity_code,
    'full_name', v_profile.full_name, 'email', v_profile.email,
    'phone', v_profile.phone, 'role', v_profile.role,
    'status', v_profile.status, 'room', v_room,
    'must_change_password', v_profile.must_change_password,
    'can_access', not v_profile.must_change_password);
end $$;
revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
comment on function public.get_my_profile() is
 'Own profile only; takes no user ID. Password-gated users may read this response; blocked users receive status only.';
commit;
