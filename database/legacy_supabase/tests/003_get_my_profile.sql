-- SQL Editor only. Assertions execute with real database roles and JWT-sub simulation.
-- The entire test is rolled back; no demo account changes are persisted.
begin;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$ begin
  perform public.get_my_profile();
  raise exception 'FAIL: anon may call profile RPC';
exception when insufficient_privilege then null;
end $$;
reset role;
set local role authenticated;
do $$ begin
  perform public.get_my_profile();
  raise exception 'FAIL: missing identity accepted';
exception when invalid_authorization_specification then null;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000099', true);
set local role authenticated;
do $$ begin
  perform public.get_my_profile();
  raise exception 'FAIL: missing profile accepted';
exception when no_data_found then null;
end $$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='ADMIN001'), true);
set local role authenticated;
do $$ declare v jsonb := public.get_my_profile(); begin
  if v->>'email' is distinct from 'admin@example.com' or v->>'role' is distinct from 'admin'
     or v->>'can_access' is distinct from 'true' then raise exception 'FAIL: admin profile'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='SV001'), true);
set local role authenticated;
do $$ declare v jsonb := public.get_my_profile(); begin
  if v->>'email' is distinct from 'student@example.com' or v->>'role' is distinct from 'student'
     or v->>'must_change_password' is distinct from 'true' or v->>'can_access' is distinct from 'false'
     or v->'room'->>'code' is distinct from 'DEMO-A101' then raise exception 'FAIL: gated student profile'; end if;
  if exists (select 1 from public.incident_categories) then raise exception 'FAIL: gated student sees business data'; end if;
  begin
    update public.profiles set must_change_password=false where id=auth.uid();
    raise exception 'FAIL: client may clear password gate';
  exception when insufficient_privilege then null;
  end;
  begin
    perform email from public.profiles;
    raise exception 'FAIL: direct email column access';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='KTV001'), true);
set local role authenticated;
do $$ declare v jsonb := public.get_my_profile(); begin
  if v->>'email' is distinct from 'technican@example.com' or v->>'role' is distinct from 'technician'
     or v->>'can_access' is distinct from 'false' or v->>'must_change_password' is distinct from 'true'
     or v->'room' is distinct from 'null'::jsonb then raise exception 'FAIL: technician profile'; end if;
end $$;
reset role;
update public.profiles set status='locked' where identity_code='SV001';
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='SV001'), true);
set local role authenticated;
do $$ declare v jsonb := public.get_my_profile(); begin
  if v->>'status' is distinct from 'locked' or v->>'can_access' is distinct from 'false' or v ? 'email'
     or public.current_active_role() is not null then raise exception 'FAIL: locked user'; end if;
end $$;
reset role;
update public.profiles set status='revoked' where identity_code='SV001';
set local role authenticated;
do $$ declare v jsonb := public.get_my_profile(); begin
  if v->>'status' is distinct from 'revoked' or v->>'can_access' is distinct from 'false' or v ? 'email'
     or public.current_active_role() is not null then raise exception 'FAIL: revoked user'; end if;
end $$;
reset role;
rollback;
select 'PASS: profile roles, anon, missing identity/profile, password gate, locked/revoked, column privacy; all changes rolled back' as result;
