-- SQL Editor test for update_my_phone RPC (DF-006 & DF-019)
begin;

select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$ begin
  perform public.update_my_phone('0912345678');
  raise exception 'FAIL: anon may call update_my_phone';
exception when insufficient_privilege then null;
end $$;
reset role;

set local role authenticated;
do $$ begin
  perform public.update_my_phone('0912345678');
  raise exception 'FAIL: missing identity accepted';
exception when invalid_authorization_specification then null;
end $$;
reset role;

select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='SV001'), true);
set local role authenticated;
do $$ begin
  perform public.update_my_phone('');
  raise exception 'FAIL: empty phone accepted';
exception when sqlstate '22023' then null;
end $$;

do $$ declare v jsonb := public.update_my_phone('0987654321'); begin
  if v->>'phone' is distinct from '0987654321' then
    raise exception 'FAIL: phone not updated in response';
  end if;
  if (select phone from public.profiles where identity_code='SV001') is distinct from '0987654321' then
    raise exception 'FAIL: phone not updated in table';
  end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub', (select id::text from public.profiles where identity_code='KTV001'), true);
set local role authenticated;
do $$ declare v jsonb := public.update_my_phone('0999888777'); begin
  if v->>'phone' is distinct from '0999888777' then
    raise exception 'FAIL: technician phone not updated in response';
  end if;
  if (select phone from public.profiles where identity_code='KTV001') is distinct from '0999888777' then
    raise exception 'FAIL: technician phone not updated in table';
  end if;
end $$;
reset role;

rollback;
select 'PASS: update_my_phone anon/auth checks, empty validation, student & technician update; all changes rolled back' as result;
