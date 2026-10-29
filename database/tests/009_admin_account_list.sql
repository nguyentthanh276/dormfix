-- DF-028/029/030: role gate, Admin exclusion, search, combined filters, pagination.
begin;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $$ begin
  perform * from public.admin_list_accounts();
  raise exception 'FAIL: missing identity accepted';
exception when insufficient_privilege then null;
end $$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='ADMIN001'), true);
set local role authenticated;
do $$ declare v_count integer; begin
  select count(*) into v_count from public.admin_list_accounts();
  if exists(select 1 from public.admin_list_accounts() where role='admin') then raise exception 'FAIL: admin listed'; end if;
  if (select count(*) from public.admin_list_accounts(p_query=>'sv001')) < 1 then raise exception 'FAIL: identity search'; end if;
  if (select count(*) from public.admin_list_accounts(p_role=>'student',p_status=>'active')) <> v_count then
    -- Existing demo seed has one active student; filters must apply together.
    if v_count = 0 or exists(select 1 from public.admin_list_accounts(p_role=>'student',p_status=>'active') where role <> 'student' or status <> 'active') then
      raise exception 'FAIL: combined filters';
    end if;
  end if;
  if (select count(*) from public.admin_list_accounts(p_limit=>1)) > 1 then raise exception 'FAIL: page limit'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='SV001'), true);
set local role authenticated;
do $$ begin
  perform * from public.admin_list_accounts();
  raise exception 'FAIL: non-admin access accepted';
exception when insufficient_privilege then null;
end $$;
reset role;
rollback;
select 'PASS: account listing role gate, Admin exclusion, search, filters and pagination' as result;
