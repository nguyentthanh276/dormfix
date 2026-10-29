-- DF-028/029/030: Admin-only account listing with AND filters and paging.
begin;

create function public.admin_normalize_search(p_value text) returns text
language sql immutable strict set search_path = '' as $$
  select translate(lower(p_value),
    'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ',
    repeat('a', 17) || repeat('e', 11) || repeat('i', 5) ||
    repeat('o', 17) || repeat('u', 11) || repeat('y', 5) || 'd');
$$;

create function public.admin_list_accounts(
  p_query text default null,
  p_role public.app_role default null,
  p_status public.account_status default null,
  p_offset integer default 0,
  p_limit integer default 20
) returns table(full_name text, identity_code text, role text, status text)
language plpgsql stable security definer set search_path = '' as $$
declare v_query text := public.admin_normalize_search(coalesce(trim(p_query), ''));
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'
      and p.status = 'active' and not p.must_change_password
  ) then raise insufficient_privilege using message = 'Admin access required'; end if;
  if p_role is not null and p_role not in ('student', 'technician') then
    raise invalid_parameter_value using message = 'Unsupported account role';
  end if;
  if p_offset < 0 or p_limit < 1 or p_limit > 100 then
    raise invalid_parameter_value using message = 'Invalid pagination';
  end if;
  return query select p.full_name, p.identity_code, p.role::text, p.status::text
    from public.profiles p
    where p.role in ('student', 'technician')
      and (p_role is null or p.role = p_role)
      and (p_status is null or p.status = p_status)
      and (v_query = '' or public.admin_normalize_search(p.full_name) like '%' || v_query || '%'
        or public.admin_normalize_search(p.identity_code) like '%' || v_query || '%')
    order by p.full_name, p.identity_code offset p_offset limit p_limit;
end $$;

revoke all on function public.admin_normalize_search(text) from public, anon, authenticated;
revoke all on function public.admin_list_accounts(text, public.app_role, public.account_status, integer, integer) from public, anon;
grant execute on function public.admin_list_accounts(text, public.app_role, public.account_status, integer, integer) to authenticated;
commit;
