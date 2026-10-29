-- Disable the DF-043/044 read RPC surface without dropping functions or changing data.
begin;
revoke all on function public.admin_request_filter_options() from public, anon, authenticated;
revoke all on function public.admin_list_requests(public.repair_status, uuid, uuid, uuid, text, timestamptz, timestamptz, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_get_request(uuid) from public, anon, authenticated;
commit;
