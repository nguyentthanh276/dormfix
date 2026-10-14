-- DF-031: Admin creates a student account with a temporary password.
-- Only 'admin' role (active, no pending password change) may call this.
-- identity_code and email are permanently unique across all profiles, including revoked ones.
-- A confirmed Auth user is created via auth.create_user() which requires the service_role key
-- that Supabase injects for security-definer functions running under the authenticator/service scope.
-- The temp_password must be supplied by the admin; it is never stored in public tables.
-- The student must change the password on first login (must_change_password=true).
begin;

create or replace function public.admin_create_student(
  p_identity_code text,
  p_full_name     text,
  p_email         text,
  p_phone         text,
  p_room_id       uuid,
  p_temp_password text
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_caller_role public.app_role;
  v_caller_id   uuid := auth.uid();
  v_new_auth_id uuid;
  v_new_profile_id uuid;
  v_identity_code text := lower(trim(p_identity_code));
  v_email         text := lower(trim(p_email));
  v_full_name     text := trim(p_full_name);
  v_phone         text := trim(p_phone);
begin
  -- ── Permission gate ──────────────────────────────────────────────────────
  if v_caller_id is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  select role into v_caller_role
  from public.profiles
  where id = v_caller_id
    and status = 'active'
    and not must_change_password;

  if v_caller_role is distinct from 'admin'::public.app_role then
    raise exception using errcode = '42501', message = 'ADMIN_ONLY';
  end if;

  -- ── Input validation ─────────────────────────────────────────────────────
  if length(v_identity_code) = 0 then
    raise exception using errcode = 'DF001', message = 'IDENTITY_CODE_REQUIRED';
  end if;
  if length(v_full_name) = 0 then
    raise exception using errcode = 'DF002', message = 'FULL_NAME_REQUIRED';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception using errcode = 'DF003', message = 'EMAIL_INVALID';
  end if;
  if length(v_phone) = 0 then
    raise exception using errcode = 'DF004', message = 'PHONE_REQUIRED';
  end if;
  if p_room_id is null then
    raise exception using errcode = 'DF005', message = 'ROOM_REQUIRED';
  end if;
  if length(trim(p_temp_password)) < 8 then
    raise exception using errcode = 'DF006', message = 'PASSWORD_TOO_SHORT';
  end if;

  -- ── Uniqueness checks (including revoked/locked — permanent identifiers) ──
  if exists (
    select 1 from public.profiles
    where lower(trim(identity_code)) = v_identity_code
  ) then
    raise exception using errcode = 'DF007', message = 'IDENTITY_CODE_TAKEN';
  end if;

  if exists (
    select 1 from public.profiles
    where lower(trim(email)) = v_email
  ) then
    raise exception using errcode = 'DF008', message = 'EMAIL_TAKEN';
  end if;

  -- ── Room must be active ───────────────────────────────────────────────────
  if not exists (
    select 1 from public.rooms
    where id = p_room_id and is_active = true
  ) then
    raise exception using errcode = 'DF009', message = 'ROOM_NOT_ACTIVE';
  end if;

  -- ── Create Auth user (service_role context via security definer) ──────────
  -- auth.create_user is available inside security-definer functions on Supabase.
  -- email_confirm=true so the student can log in immediately with the temp password.
  select id into v_new_auth_id
  from auth.create_user(
    jsonb_build_object(
      'email',          p_email,
      'password',       p_temp_password,
      'email_confirm',  true,
      'role',           'authenticated'
    )
  );

  -- ── Insert profile ────────────────────────────────────────────────────────
  insert into public.profiles (
    id, identity_code, full_name, email, phone,
    role, status, room_id, must_change_password
  ) values (
    v_new_auth_id,
    p_identity_code,
    p_full_name,
    p_email,
    p_phone,
    'student',
    'active',
    p_room_id,
    true
  )
  returning id into v_new_profile_id;

  -- ── Audit log ─────────────────────────────────────────────────────────────
  insert into public.request_history (
    entity_type, entity_id, action, actor_id, note
  ) values (
    'profile',
    v_new_profile_id,
    'create_student',
    v_caller_id,
    'identity_code=' || p_identity_code || '; email=' || p_email || '; room_id=' || p_room_id::text
  );

  return jsonb_build_object('id', v_new_profile_id);

exception
  -- Re-raise our domain errors and unique-violation as-is.
  when sqlstate 'DF001' then raise;
  when sqlstate 'DF002' then raise;
  when sqlstate 'DF003' then raise;
  when sqlstate 'DF004' then raise;
  when sqlstate 'DF005' then raise;
  when sqlstate 'DF006' then raise;
  when sqlstate 'DF007' then raise;
  when sqlstate 'DF008' then raise;
  when sqlstate 'DF009' then raise;
  when unique_violation then
    raise exception using errcode = 'DF010', message = 'DUPLICATE_KEY';
end $$;

revoke all on function public.admin_create_student(text, text, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_create_student(text, text, text, text, uuid, text)
  to authenticated;

comment on function public.admin_create_student(text, text, text, text, uuid, text) is
  'DF-031: Admin-only. Creates a student Auth user and profile with must_change_password=true. '
  'identity_code and email are permanently unique. Room must be active. '
  'Returns {id} of the new profile.';

commit;
