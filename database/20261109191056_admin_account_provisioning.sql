-- Admin account creation/profile updates and proof of first password change.
-- Supabase Auth owns the credential. DormFix keeps a short-lived provisioning
-- context and, only while gated, a SHA-256 digest of Auth's initial password hash.
begin;

create schema dormfix_private;
revoke all on schema dormfix_private from public,anon,authenticated,service_role;

create table dormfix_private.account_provisions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null,
  identity_code text not null,
  full_name text not null,
  email text not null,
  phone text not null,
  role public.app_role not null,
  room_id uuid,
  expires_at timestamptz not null,
  check (role in ('student','technician')),
  check ((role = 'student') = (room_id is not null))
);
create index account_provisions_expiry_idx on dormfix_private.account_provisions(expires_at);
alter table dormfix_private.account_provisions enable row level security;

create table dormfix_private.initial_password_gates (
  account_id uuid primary key references public.profiles(id) on delete cascade,
  fingerprint bytea not null check (octet_length(fingerprint) = 32)
);
alter table dormfix_private.initial_password_gates enable row level security;
revoke all on dormfix_private.account_provisions,dormfix_private.initial_password_gates
  from public,anon,authenticated,service_role;

create function dormfix_private.account_summary(p_profile public.profiles) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'id',p_profile.id,'identity_code',p_profile.identity_code,'full_name',p_profile.full_name,
    'email',p_profile.email,'phone',p_profile.phone,'role',p_profile.role,'status',p_profile.status,
    'room_id',p_profile.room_id,'must_change_password',p_profile.must_change_password
  );
$$;

create function dormfix_private.account_phone(p_phone text) returns text
language plpgsql immutable set search_path = '' as $$
declare v_phone text := regexp_replace(p_phone,'[[:space:].-]+','','g');
begin
  if v_phone is null or v_phone !~ '^(0|\+84)[0-9]{9}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCOUNT_PHONE';
  end if;
  return v_phone;
end $$;

create function dormfix_private.lock_account_room(p_role public.app_role,p_room_id uuid)
returns void language plpgsql volatile set search_path = '' as $$
begin
  if p_role = 'student' then
    perform 1 from public.rooms where id = p_room_id and is_active for share;
    if not found then
      raise exception using errcode = '22023', message = 'ACTIVE_STUDENT_ROOM_REQUIRED';
    end if;
  elsif p_role = 'technician' and p_room_id is not null then
    raise exception using errcode = '22023', message = 'INVALID_ACCOUNT_INPUT';
  end if;
end $$;

create function public.admin_get_account(p_identity_code text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_profile public.profiles%rowtype;
begin
  perform public._admin_request_actor();
  select * into v_profile from public.profiles
    where lower(trim(identity_code)) = lower(regexp_replace(p_identity_code,'^[[:space:]]+|[[:space:]]+$','','g'))
      and role in ('student','technician');
  if not found then raise exception using errcode = 'P0002', message = 'ACCOUNT_NOT_FOUND'; end if;
  return dormfix_private.account_summary(v_profile);
end $$;

create function public.admin_prepare_account_provision(
  p_identity_code text,p_full_name text,p_email text,p_phone text,p_role text,p_room_id uuid
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_code text := nullif(regexp_replace(p_identity_code,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_name text := nullif(regexp_replace(p_full_name,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_email text := lower(regexp_replace(p_email,'^[[:space:]]+|[[:space:]]+$','','g'));
  v_phone text;
  v_provision_id uuid;
  v_now timestamptz;
begin
  if v_code is null or v_name is null or v_email is null
    or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    or p_role is null or p_role not in ('student','technician') then
    raise exception using errcode = '22023', message = 'INVALID_ACCOUNT_INPUT';
  end if;
  v_phone := dormfix_private.account_phone(p_phone);
  perform dormfix_private.lock_account_room(p_role::public.app_role,p_room_id);

  if exists(select 1 from public.profiles p where lower(trim(p.identity_code)) = lower(v_code)) then
    raise exception using errcode = '23505', message = 'ACCOUNT_IDENTITY_ALREADY_EXISTS';
  end if;
  if exists(select 1 from public.profiles p where lower(trim(p.email)) = v_email)
    or exists(select 1 from auth.users u where lower(u.email) = v_email) then
    raise exception using errcode = '23505', message = 'ACCOUNT_EMAIL_ALREADY_EXISTS';
  end if;

  v_now := clock_timestamp();
  delete from dormfix_private.account_provisions where expires_at <= v_now;
  insert into dormfix_private.account_provisions(admin_id,identity_code,full_name,email,phone,role,room_id,expires_at)
  values(v_admin,v_code,v_name,v_email,v_phone,p_role::public.app_role,p_room_id,v_now+interval '5 minutes')
  returning id into v_provision_id;
  return jsonb_build_object('provision_id',v_provision_id,'email',v_email);
end $$;

create function public.admin_cancel_account_provision(p_provision_id uuid) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_admin uuid := public._admin_request_actor();
begin
  delete from dormfix_private.account_provisions where id = p_provision_id and admin_id = v_admin;
  return found;
end $$;

-- GoTrue can persist Admin app_metadata after INSERT, inside the same Auth
-- transaction. The nonce is server-owned app metadata, never user metadata.
create function dormfix_private.provision_account() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_provision_id uuid;
  v_provision dormfix_private.account_provisions%rowtype;
  v_now timestamptz;
begin
  if jsonb_typeof(new.raw_app_meta_data->'dormfix_provision_id') is distinct from 'string'
     or new.raw_app_meta_data->>'dormfix_provision_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACCOUNT_PROVISION';
  end if;
  v_provision_id := (new.raw_app_meta_data->>'dormfix_provision_id')::uuid;
  delete from dormfix_private.account_provisions
    where id = v_provision_id and expires_at > clock_timestamp()
    returning * into v_provision;
  if not found or new.email is distinct from v_provision.email
     or nullif(new.encrypted_password,'') is null then
    raise exception using errcode = '22023', message = 'INVALID_ACCOUNT_PROVISION';
  end if;

  perform 1 from public.profiles where id = v_provision.admin_id
    and role = 'admin' and status = 'active' and not must_change_password for share;
  if not found then
    raise exception using errcode = '42501', message = 'ACCOUNT_PROVISION_ADMIN_DENIED';
  end if;
  perform dormfix_private.lock_account_room(v_provision.role,v_provision.room_id);

  v_now := clock_timestamp();
  insert into public.profiles(id,identity_code,full_name,email,phone,role,status,room_id,
    must_change_password,created_at,updated_at)
  values(new.id,v_provision.identity_code,v_provision.full_name,v_provision.email,v_provision.phone,
    v_provision.role,'active',v_provision.room_id,true,v_now,v_now);
  insert into dormfix_private.initial_password_gates(account_id,fingerprint)
  values(new.id,sha256(convert_to(new.encrypted_password,'UTF8')));
  insert into public.request_history(entity_type,entity_id,action,actor_id,new_status,note,occurred_at)
  values('profile',new.id,'admin_account_created',v_provision.admin_id,'active',v_provision.role::text,v_now);

  -- Strip the consumed nonce from persisted metadata. This update cannot
  -- re-enter the trigger body because the new row no longer has the key.
  update auth.users set raw_app_meta_data = raw_app_meta_data - 'dormfix_provision_id'
  where id = new.id;
  return new;
end $$;

create trigger dormfix_provision_account
after insert or update of raw_app_meta_data on auth.users
for each row when (new.raw_app_meta_data ? 'dormfix_provision_id')
execute function dormfix_private.provision_account();

create function dormfix_private.prevent_account_email_change() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
begin
  if (new.email is distinct from old.email
      or (new.email_change is distinct from old.email_change and nullif(new.email_change,'') is not null))
    and exists(select 1 from public.profiles where id = old.id) then
    raise exception using errcode = '42501', message = 'ACCOUNT_EMAIL_IMMUTABLE';
  end if;
  return new;
end $$;

create trigger dormfix_prevent_account_email_change
before update of email,email_change on auth.users
for each row execute function dormfix_private.prevent_account_email_change();

create function public.admin_update_account(
  p_account_id uuid,p_full_name text,p_phone text,p_room_id uuid
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_profile public.profiles%rowtype;
  v_name text := nullif(regexp_replace(p_full_name,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_phone text;
  v_note text;
  v_now timestamptz;
begin
  if v_name is null then
    raise exception using errcode = '22023', message = 'INVALID_ACCOUNT_INPUT';
  end if;
  v_phone := dormfix_private.account_phone(p_phone);
  select * into v_profile from public.profiles
    where id = p_account_id and role in ('student','technician') for update;
  if not found then raise exception using errcode = 'P0002', message = 'ACCOUNT_NOT_FOUND'; end if;

  -- A revoked student can retain the former room for history. Any move must
  -- lock an active destination against the Admin room deactivation RPC.
  if v_profile.status <> 'revoked' or v_profile.room_id is distinct from p_room_id then
    perform dormfix_private.lock_account_room(v_profile.role,p_room_id);
  end if;
  if v_name = v_profile.full_name and v_phone = v_profile.phone
    and p_room_id is not distinct from v_profile.room_id then
    return dormfix_private.account_summary(v_profile) || jsonb_build_object('changed',false);
  end if;

  v_note := concat_ws(', ',
    case when v_name <> v_profile.full_name then 'Họ và tên' end,
    case when v_phone <> v_profile.phone then 'Số điện thoại' end,
    case when p_room_id is distinct from v_profile.room_id then 'Phòng' end);
  v_now := clock_timestamp();
  update public.profiles set full_name = v_name,phone = v_phone,room_id = p_room_id,updated_at = v_now
    where id = p_account_id returning * into v_profile;
  insert into public.request_history(entity_type,entity_id,action,actor_id,note,occurred_at)
  values('profile',p_account_id,'admin_account_updated',v_admin,v_note,v_now);
  return dormfix_private.account_summary(v_profile) || jsonb_build_object('changed',true);
end $$;

create function public.complete_change_password() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_initial bytea;
  v_current bytea;
begin
  if v_uid is null then raise exception using errcode = '28000', message = 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where id = v_uid for update;
  if not found or v_profile.status <> 'active' then
    raise exception using errcode = '42501', message = 'ACCOUNT_ACCESS_DENIED';
  end if;
  if not v_profile.must_change_password then return public.get_my_profile(); end if;

  select fingerprint into v_initial from dormfix_private.initial_password_gates where account_id = v_uid;
  select sha256(convert_to(u.encrypted_password,'UTF8')) into v_current
    from auth.users u where u.id = v_uid and nullif(u.encrypted_password,'') is not null;
  if v_initial is null or v_current is null or v_current = v_initial then
    raise exception using errcode = 'P0001', message = 'PASSWORD_CHANGE_NOT_VERIFIED';
  end if;

  update public.profiles set must_change_password = false,updated_at = clock_timestamp() where id = v_uid;
  delete from dormfix_private.initial_password_gates where account_id = v_uid;
  return public.get_my_profile();
end $$;

revoke all on function dormfix_private.account_summary(public.profiles),
  dormfix_private.account_phone(text),dormfix_private.lock_account_room(public.app_role,uuid),
  dormfix_private.provision_account(),dormfix_private.prevent_account_email_change()
  from public,anon,authenticated,service_role;
revoke all on function public.admin_get_account(text),
  public.admin_prepare_account_provision(text,text,text,text,text,uuid),
  public.admin_cancel_account_provision(uuid),public.admin_update_account(uuid,text,text,uuid),
  public.complete_change_password() from public,anon;
grant execute on function public.admin_get_account(text),
  public.admin_prepare_account_provision(text,text,text,text,text,uuid),
  public.admin_cancel_account_provision(uuid),public.admin_update_account(uuid,text,text,uuid),
  public.complete_change_password() to authenticated;

commit;
