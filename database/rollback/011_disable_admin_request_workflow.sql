-- Disable the DF-045/046 RPC surface without dropping functions or changing data.
begin;
revoke all on function public.admin_request_active_technicians() from public, anon, authenticated;
revoke all on function public.admin_assign_request(uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_reject_request(uuid, text) from public, anon, authenticated;
commit;
