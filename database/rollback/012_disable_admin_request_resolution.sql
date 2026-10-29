-- Disable the DF-047/048 RPC surface without dropping functions or changing data.
begin;
revoke all on function public.admin_transfer_request(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.admin_confirm_revoked_student_request(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_request_rework_revoked_student_request(uuid, text) from public, anon, authenticated;
commit;
