-- Run once from SQL Editor after manually creating the three confirmed Auth users.
-- No passwords are stored here. This seed creates application profiles, not Auth users.
-- Demo names/phone numbers are fictitious. Keep this file for the development project.
begin;

do $$
declare
  v_admin uuid;
  v_student uuid;
  v_technician uuid;
  v_room uuid;
begin
  select id into strict v_admin from auth.users
    where lower(email) = 'admin@example.com' and email_confirmed_at is not null;
  select id into strict v_student from auth.users
    where lower(email) = 'student@example.com' and email_confirmed_at is not null;
  select id into strict v_technician from auth.users
    where lower(email) = 'technican@example.com' and email_confirmed_at is not null;

  -- Stop rather than changing a profile that might already be in use.
  if exists (select 1 from public.profiles
    where id in (v_admin, v_student, v_technician)
       or lower(trim(identity_code)) in ('admin001', 'sv001', 'ktv001')
       or lower(trim(email)) in ('admin@example.com', 'student@example.com', 'technican@example.com')) then
    raise exception 'Demo profiles already exist or identifiers are in use. Check before running again.';
  end if;

  select id into v_room from public.rooms where lower(trim(code)) = 'demo-a101';
  if v_room is null then
    insert into public.rooms (code, building) values ('DEMO-A101', 'Tòa demo') returning id into v_room;
  elsif not exists (select 1 from public.rooms where id = v_room and is_active) then
    raise exception 'DEMO-A101 is inactive. Choose an active demo room before proceeding.';
  end if;

  insert into public.profiles
    (id, identity_code, full_name, email, phone, role, status, room_id, must_change_password)
  values
    (v_admin, 'ADMIN001', 'Admin Demo', 'admin@example.com', null, 'admin', 'active', null, false),
    (v_student, 'SV001', 'Sinh viên Demo', 'student@example.com', '0000000001', 'student', 'active', v_room, true),
    (v_technician, 'KTV001', 'Kỹ thuật viên Demo', 'technican@example.com', '0000000002', 'technician', 'active', null, true);
exception
  when no_data_found then
    raise exception 'Create and confirm all three demo Auth users before running this seed.';
end $$;

commit;

select identity_code, full_name, email, role, status, room_id, must_change_password
from public.profiles
where identity_code in ('ADMIN001', 'SV001', 'KTV001')
order by identity_code;
