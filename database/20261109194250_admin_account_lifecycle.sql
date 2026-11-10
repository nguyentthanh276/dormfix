-- DF-035–038. Account status, Auth sessions and audit change atomically.
begin;

create table dormfix_private.account_session_fences (
  account_id uuid primary key references public.profiles(id) on delete cascade,
  valid_after timestamptz not null,
  prior_ban_until timestamptz,
  dormfix_ban_until timestamptz
);
alter table dormfix_private.account_session_fences enable row level security;

create table dormfix_private.password_reset_requests (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null unique references public.profiles(id) on delete cascade,
  admin_id uuid not null,
  expected_status public.account_status not null,
  prior_fingerprint bytea not null check (octet_length(prior_fingerprint) = 32),
  expires_at timestamptz not null
);
create index password_reset_requests_expiry_idx on dormfix_private.password_reset_requests(expires_at);
alter table dormfix_private.password_reset_requests enable row level security;
revoke all on dormfix_private.account_session_fences,dormfix_private.password_reset_requests
  from public,anon,authenticated,service_role;

-- Only accounts affected by a lifecycle action need a session lookup. The
-- creation timestamp also rejects a pre-action sign-in that commits late.
create function public.dormfix_session_is_current() returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v_account uuid := auth.uid();
  v_session text := auth.jwt()->>'session_id';
  v_valid_after timestamptz;
begin
  if v_account is null then return false; end if;
  select valid_after into v_valid_after
    from dormfix_private.account_session_fences where account_id = v_account;
  if not found then return true; end if;
  if v_session is null or v_session !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    then return false; end if;
  return exists (
    select 1 from auth.sessions
    where id = v_session::uuid and user_id = v_account and created_at >= v_valid_after
  );
end $$;

create function public.dormfix_verify_session() returns void
language plpgsql stable set search_path = '' as $$
begin
  if current_user = 'authenticated' and not public.dormfix_session_is_current() then
    raise exception using errcode = '28000', message = 'ACCOUNT_SESSION_REVOKED';
  end if;
end $$;

revoke all on function public.dormfix_session_is_current() from public,anon;
grant execute on function public.dormfix_session_is_current() to authenticated;
revoke all on function public.dormfix_verify_session() from public;
grant execute on function public.dormfix_verify_session() to anon,authenticated,service_role;

-- PostgREST has one pre-request hook. Fail rather than replace another hook.
do $$ begin
  if exists (
    select 1 from pg_catalog.pg_db_role_setting s
    cross join lateral unnest(s.setconfig) c(value)
    where s.setrole = 'authenticator'::regrole
      and (s.setdatabase = 0 or s.setdatabase = (
        select oid from pg_catalog.pg_database where datname = current_database()
      ))
      and c.value like 'pgrst.db_pre_request=%'
  ) then
    raise exception 'PostgREST already has a pre-request hook';
  end if;
end $$;
alter role authenticator set pgrst.db_pre_request = 'public.dormfix_verify_session';
notify pgrst, 'reload config';

-- Storage does not run the Data API hook. Restrict all existing policies
-- for DormFix's private bucket without granting access to any extra objects.
create policy repair_images_current_session on storage.objects as restrictive
for all to authenticated
using (bucket_id <> 'repair-images' or (select public.dormfix_session_is_current()))
with check (bucket_id <> 'repair-images' or (select public.dormfix_session_is_current()));

create function public.admin_change_account_status(
  p_account_id uuid,p_expected_status public.account_status,p_action text,
  p_reason text default null,p_room_id uuid default null
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_profile public.profiles%rowtype;
  v_old_status public.account_status;
  v_target_status public.account_status;
  v_room_id uuid;
  v_reason text := nullif(regexp_replace(p_reason,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_ban_until timestamptz;
  v_prior_ban timestamptz;
  v_dormfix_ban timestamptz;
  v_now timestamptz;
begin
  -- GoTrue updates the Auth user before the password reset trigger locks
  -- profiles. Keep that lock order for status changes too.
  if p_account_id = v_admin then
    raise exception using errcode = 'P0002', message = 'ACCOUNT_NOT_FOUND';
  end if;
  select banned_until into v_ban_until from auth.users where id = p_account_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'ACCOUNT_NOT_FOUND'; end if;
  select * into v_profile from public.profiles
    where id = p_account_id and role in ('student','technician') for update;
  if not found then raise exception using errcode = 'P0002', message = 'ACCOUNT_NOT_FOUND'; end if;
  v_old_status := v_profile.status;
  if v_old_status is distinct from p_expected_status then
    raise exception using errcode = 'P0001', message = 'ACCOUNT_STATUS_CHANGED';
  end if;

  v_target_status := case
    when p_action = 'lock' and v_old_status = 'active' then 'locked'::public.account_status
    when p_action = 'unlock' and v_old_status = 'locked' then 'active'::public.account_status
    when p_action = 'revoke' and v_old_status in ('active','locked') then 'revoked'::public.account_status
    when p_action = 'restore' and v_old_status = 'revoked' then 'active'::public.account_status
  end;
  if v_target_status is null then
    raise exception using errcode = 'P0001', message = 'ACCOUNT_STATUS_CHANGED';
  end if;
  if p_action in ('lock','revoke') and v_reason is null then
    raise exception using errcode = '22023', message = 'ACCOUNT_REASON_REQUIRED';
  end if;
  if char_length(v_reason) > 500 then
    raise exception using errcode = '22023', message = 'ACCOUNT_REASON_TOO_LONG';
  end if;
  if exists (select 1 from dormfix_private.password_reset_requests
    where account_id = p_account_id and expires_at > clock_timestamp()) then
    raise exception using errcode = 'P0001', message = 'ACCOUNT_RESET_IN_PROGRESS';
  end if;

  v_room_id := v_profile.room_id;
  if p_action = 'restore' then
    perform dormfix_private.lock_account_room(v_profile.role,p_room_id);
    v_room_id := p_room_id;
  elsif p_room_id is not null then
    raise exception using errcode = '22023', message = 'INVALID_ACCOUNT_INPUT';
  end if;

  -- The assignment/transfer writers lock the destination profile FOR SHARE.
  -- Checking the current assignee here avoids taking locks in reverse order.
  if p_action in ('lock','revoke') and v_profile.role = 'technician' and exists (
    select 1 from public.repair_requests where assigned_technician_id = p_account_id
      and status in ('assigned','in_progress','awaiting_confirmation','awaiting_rework')
  ) then
    raise exception using errcode = 'P0001', message = 'ACCOUNT_HAS_OPEN_JOBS';
  end if;

  select prior_ban_until,dormfix_ban_until into v_prior_ban,v_dormfix_ban
    from dormfix_private.account_session_fences where account_id = p_account_id;
  v_now := clock_timestamp();
  if v_target_status <> 'active' then
    if v_dormfix_ban is null or v_ban_until is distinct from v_dormfix_ban then
      v_prior_ban := v_ban_until;
      -- Use a finite timestamp compatible with GoTrue. Preserve any longer
      -- independent Auth ban and restore it when DormFix unblocks the account.
      v_dormfix_ban := greatest(v_ban_until,v_now + interval '100 years');
      update auth.users set banned_until = v_dormfix_ban where id = p_account_id;
    end if;
  else
    if v_dormfix_ban is not null and v_ban_until = v_dormfix_ban then
      update auth.users set banned_until = v_prior_ban where id = p_account_id;
    end if;
    v_prior_ban := null;
    v_dormfix_ban := null;
  end if;

  delete from auth.sessions where user_id = p_account_id;
  insert into dormfix_private.account_session_fences
    (account_id,valid_after,prior_ban_until,dormfix_ban_until)
  values (p_account_id,v_now,v_prior_ban,v_dormfix_ban)
  on conflict (account_id) do update set valid_after = excluded.valid_after,
    prior_ban_until = excluded.prior_ban_until,dormfix_ban_until = excluded.dormfix_ban_until;

  update public.profiles set status = v_target_status,room_id = v_room_id,updated_at = v_now
    where id = p_account_id returning * into v_profile;
  insert into public.request_history(entity_type,entity_id,action,actor_id,old_status,new_status,note,occurred_at)
    values ('profile',p_account_id,'admin_account_' || case p_action
      when 'lock' then 'locked' when 'unlock' then 'unlocked'
      when 'revoke' then 'revoked' else 'restored' end,
      v_admin,v_old_status::text,v_target_status::text,v_reason,v_now);
  return dormfix_private.account_summary(v_profile) || jsonb_build_object('changed',true);
end $$;

create function public.admin_prepare_password_reset(
  p_account_id uuid,p_expected_status public.account_status
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_profile public.profiles%rowtype;
  v_prior_fingerprint bytea;
  v_id uuid;
  v_now timestamptz;
begin
  select * into v_profile from public.profiles
    where id = p_account_id and role in ('student','technician') for update;
  if not found then raise exception using errcode = 'P0002', message = 'ACCOUNT_NOT_FOUND'; end if;
  if v_profile.status is distinct from p_expected_status or v_profile.status = 'revoked' then
    raise exception using errcode = 'P0001', message = 'ACCOUNT_STATUS_CHANGED';
  end if;
  select sha256(convert_to(encrypted_password,'UTF8')) into v_prior_fingerprint
    from auth.users where id = p_account_id and nullif(encrypted_password,'') is not null;
  if not found then raise exception using errcode = 'P0002', message = 'ACCOUNT_NOT_FOUND'; end if;

  v_now := clock_timestamp();
  delete from dormfix_private.password_reset_requests where expires_at <= v_now;
  insert into dormfix_private.password_reset_requests(account_id,admin_id,expected_status,prior_fingerprint,expires_at)
    values (p_account_id,v_admin,p_expected_status,v_prior_fingerprint,v_now + interval '2 minutes')
    on conflict (account_id) do nothing returning id into v_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'ACCOUNT_RESET_IN_PROGRESS';
  end if;
  return jsonb_build_object('reset_id',v_id,'account_id',p_account_id,'identity_code',v_profile.identity_code);
end $$;

create function public.admin_cancel_password_reset(p_reset_id uuid) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare v_admin uuid := public._admin_request_actor();
begin
  delete from dormfix_private.password_reset_requests where id = p_reset_id and admin_id = v_admin;
  return found;
end $$;

-- GoTrue's Admin PUT updates the hash and revokes sessions before writing
-- server-owned app_metadata, within the same transaction. A trigger failure
-- rolls back the credential as well as the profile and audit.
create function dormfix_private.finish_password_reset() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_reset dormfix_private.password_reset_requests%rowtype;
  v_profile public.profiles%rowtype;
  v_reset_id text := new.raw_app_meta_data->>'dormfix_password_reset_id';
  v_fingerprint bytea;
  v_now timestamptz;
begin
  if v_reset_id is null or v_reset_id !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' then
    raise exception using errcode = '22023', message = 'INVALID_PASSWORD_RESET';
  end if;

  select * into v_profile from public.profiles
    where id = new.id and role in ('student','technician') for update;
  if not found then raise exception using errcode = '22023', message = 'INVALID_PASSWORD_RESET'; end if;
  delete from dormfix_private.password_reset_requests
    where id = v_reset_id::uuid and account_id = new.id and expires_at > clock_timestamp()
    returning * into v_reset;
  if not found or v_reset.expected_status is distinct from v_profile.status or v_profile.status = 'revoked'
      or nullif(new.encrypted_password,'') is null then
    raise exception using errcode = '22023', message = 'INVALID_PASSWORD_RESET';
  end if;
  v_fingerprint := sha256(convert_to(new.encrypted_password,'UTF8'));
  if v_fingerprint = v_reset.prior_fingerprint then
    raise exception using errcode = '22023', message = 'INVALID_PASSWORD_RESET';
  end if;
  perform 1 from public.profiles where id = v_reset.admin_id and role = 'admin'
    and status = 'active' and not must_change_password for share;
  if not found then raise exception using errcode = '42501', message = 'ADMIN_ACCESS_DENIED'; end if;

  v_now := clock_timestamp();
  insert into dormfix_private.initial_password_gates(account_id,fingerprint)
    values (new.id,v_fingerprint) on conflict (account_id)
    do update set fingerprint = excluded.fingerprint;
  insert into dormfix_private.account_session_fences(account_id,valid_after) values (new.id,v_now)
    on conflict (account_id) do update set valid_after = excluded.valid_after;
  update public.profiles set must_change_password = true,updated_at = v_now where id = new.id;
  insert into public.request_history(entity_type,entity_id,action,actor_id,old_status,new_status,occurred_at)
    values ('profile',new.id,'admin_account_password_reset',v_reset.admin_id,
      v_profile.status::text,v_profile.status::text,v_now);

  update auth.users set raw_app_meta_data = raw_app_meta_data - 'dormfix_password_reset_id'
    where id = new.id;
  return new;
end $$;

create trigger dormfix_finish_password_reset after update of raw_app_meta_data on auth.users
for each row when (new.raw_app_meta_data ? 'dormfix_password_reset_id')
execute function dormfix_private.finish_password_reset();

-- Recheck the fence after acquiring the profile lock, including when this
-- request began before a concurrent account reset committed.
create or replace function public.complete_change_password() returns jsonb
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
  if not public.dormfix_session_is_current() then
    raise exception using errcode = '28000', message = 'ACCOUNT_SESSION_REVOKED';
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

revoke all on function dormfix_private.finish_password_reset() from public,anon,authenticated,service_role;
revoke all on function public.admin_change_account_status(uuid,public.account_status,text,text,uuid),
  public.admin_prepare_password_reset(uuid,public.account_status),public.admin_cancel_password_reset(uuid)
  from public,anon;
grant execute on function public.admin_change_account_status(uuid,public.account_status,text,text,uuid),
  public.admin_prepare_password_reset(uuid,public.account_status),public.admin_cancel_password_reset(uuid)
  to authenticated;
notify pgrst, 'reload schema';
commit;
