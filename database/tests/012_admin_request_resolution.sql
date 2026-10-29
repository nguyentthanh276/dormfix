-- DF-047/048: Admin transfer and revoked-student resolution checks.
-- Run after migrations 010, 011 and 012; all fixture rows roll back.
begin;
create temporary table admin_resolution_fixture(key text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into admin_resolution_fixture(key) values
 ('admin'), ('student_revoked'), ('student_locked'), ('student_active'),
 ('tech_old_locked'), ('tech_old_active'), ('tech_new'), ('room'), ('category'),
 ('in_progress'), ('awaiting_rework'), ('cancelled'), ('confirm_revoked'),
 ('rework_revoked'), ('confirm_locked'), ('confirm_active');
grant select on admin_resolution_fixture to authenticated;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text||'@admin-resolution-test.invalid',now(),now(),now()
from admin_resolution_fixture where key in ('admin','student_revoked','student_locked','student_active',
 'tech_old_locked','tech_old_active','tech_new');
insert into public.rooms(id,code,building) select id,'ADMIN-RES-A101','Test building'
from admin_resolution_fixture where key='room';
insert into public.incident_categories(id,name) select id,'Admin resolution test'
from admin_resolution_fixture where key='category';
insert into public.profiles(id,identity_code,full_name,email,phone,role,status,room_id,must_change_password)
select id,'AR-'||id::text,
 case key when 'admin' then 'Resolution Admin' when 'student_revoked' then 'Revoked Student'
  when 'student_locked' then 'Locked Student' when 'student_active' then 'Active Student'
  when 'tech_old_locked' then 'Old Locked Technician' when 'tech_old_active' then 'Old Active Technician'
  else 'New Technician' end,
 id::text||'@admin-resolution-test.invalid',case when key='admin' then null else '0900000002' end,
 case when key='admin' then 'admin'::public.app_role
  when key like 'student_%' then 'student'::public.app_role else 'technician'::public.app_role end,
 case key when 'student_revoked' then 'revoked'::public.account_status
  when 'student_locked' then 'locked'::public.account_status
  when 'tech_old_locked' then 'locked'::public.account_status else 'active'::public.account_status end,
 case when key like 'student_%' then (select id from admin_resolution_fixture where key='room') end,
 false
from admin_resolution_fixture where key in ('admin','student_revoked','student_locked','student_active',
 'tech_old_locked','tech_old_active','tech_new');

insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id)
select f.id,
 (select id from admin_resolution_fixture where key=case
   when f.key in ('confirm_revoked','rework_revoked') then 'student_revoked'
   when f.key='confirm_locked' then 'student_locked'
   when f.key='confirm_active' then 'student_active' else 'student_active' end),
 (select id from admin_resolution_fixture where key='room'),'ADMIN-RES-A101','Test building',
 (select id from admin_resolution_fixture where key='category'),'Admin resolution test',
 'Fixture '||f.key,'Fixture description',
 case f.key when 'in_progress' then 'in_progress'::public.repair_status
  when 'awaiting_rework' then 'awaiting_rework'::public.repair_status
  when 'cancelled' then 'cancelled'::public.repair_status
  else 'awaiting_confirmation'::public.repair_status end,
 (select id from admin_resolution_fixture where key=case
   when f.key='in_progress' then 'tech_old_locked'
   when f.key='awaiting_rework' then 'tech_old_active'
   else 'tech_old_active' end)
from admin_resolution_fixture f where key in ('in_progress','awaiting_rework','cancelled',
 'confirm_revoked','rework_revoked','confirm_locked','confirm_active');
insert into public.request_assignments(request_id,technician_id,assigned_by,assigned_at,
 request_code_snapshot,title_snapshot,room_code_snapshot)
select r.id,r.assigned_technician_id,(select id from admin_resolution_fixture where key='admin'),
 now()-interval '1 hour',r.request_code,r.title,r.room_code_snapshot
from public.repair_requests r where r.id in (select id from admin_resolution_fixture
 where key in ('in_progress','awaiting_rework','cancelled','confirm_revoked','rework_revoked','confirm_locked','confirm_active'));

select set_config('request.jwt.claim.sub',(select id::text from admin_resolution_fixture where key='admin'),true);
set local role authenticated;
do $$ declare v_id uuid; v_error boolean; begin
  v_id := (select id from admin_resolution_fixture where key='in_progress');
  perform public.admin_transfer_request(v_id,(select id from admin_resolution_fixture where key='tech_new'),'Điều phối nhân lực');
  if (select status from public.repair_requests where id=v_id) <> 'in_progress'
    or (select assigned_technician_id from public.repair_requests where id=v_id) <> (select id from admin_resolution_fixture where key='tech_new')
    or not exists(select 1 from jsonb_array_elements(public.admin_get_request(v_id)->'assignments') as a(item)
      where item->>'technician_id'=(select id::text from admin_resolution_fixture where key='tech_old_locked')
        and item->>'ended_at' is not null and item->>'end_reason'='Điều phối nhân lực') then
    raise exception 'FAIL DF-047: transfer status, current assignment, old locked technician history or confirmation gate';
  end if;
  v_error := false;
  begin perform public.admin_transfer_request(v_id,(select id from admin_resolution_fixture where key='tech_new'),'Lặp lại');
  exception when sqlstate '22023' then v_error := true; end;
  if not v_error then raise exception 'FAIL DF-047: same current technician accepted'; end if;

  v_id := (select id from admin_resolution_fixture where key='awaiting_rework');
  v_error := false;
  begin perform public.admin_transfer_request(v_id,(select id from admin_resolution_fixture where key='tech_new'),'   ');
  exception when sqlstate '22023' then v_error := true; end;
  if not v_error or (select assigned_technician_id from public.repair_requests where id=v_id) <> (select id from admin_resolution_fixture where key='tech_old_active') then
    raise exception 'FAIL DF-047: empty reason accepted or changed assignment';
  end if;
  perform public.admin_transfer_request(v_id,(select id from admin_resolution_fixture where key='tech_new'),'Bàn giao sửa lại');
  if (select status from public.repair_requests where id=v_id) <> 'awaiting_rework'
    or (select assigned_technician_id from public.repair_requests where id=v_id) <> (select id from admin_resolution_fixture where key='tech_new') then
    raise exception 'FAIL DF-047: rework status or continue gate changed incorrectly';
  end if;
  v_error := false;
  begin perform public.admin_transfer_request((select id from admin_resolution_fixture where key='cancelled'),
    (select id from admin_resolution_fixture where key='tech_new'),'Hủy');
  exception when sqlstate 'P0001' then v_error := true; end;
  if not v_error or (select status from public.repair_requests where id=(select id from admin_resolution_fixture where key='cancelled')) <> 'cancelled' then
    raise exception 'FAIL DF-047: cancelled request accepted or changed';
  end if;
  raise notice 'PASS DF-047: eligible transfers, reason, former locked KTV, same-KTV rejection, cancelled rejection and status-specific confirmation';

  v_id := (select id from admin_resolution_fixture where key='confirm_revoked');
  v_error := false;
  begin perform public.admin_confirm_revoked_student_request(v_id,'   ');
  exception when sqlstate '22023' then v_error := true; end;
  if not v_error then raise exception 'FAIL DF-048: blank completion note accepted'; end if;
  perform public.admin_confirm_revoked_student_request(v_id,'Đã kiểm tra hoàn tất');
  if (select status from public.repair_requests where id=v_id) <> 'completed'
    or not exists(select 1 from public.request_history where request_id=v_id and new_status='completed' and note='Đã kiểm tra hoàn tất') then
    raise exception 'FAIL DF-048: revoked student completion or audit note missing';
  end if;

  v_id := (select id from admin_resolution_fixture where key='rework_revoked');
  perform public.admin_request_rework_revoked_student_request(v_id,'Cần khắc phục thêm');
  if (select status from public.repair_requests where id=v_id) <> 'awaiting_rework'
    or (select assigned_technician_id from public.repair_requests where id=v_id) <> (select id from admin_resolution_fixture where key='tech_old_active')
    or not exists(select 1 from public.request_history where request_id=v_id and new_status='awaiting_rework' and note='Cần khắc phục thêm') then
    raise exception 'FAIL DF-048: rework status, assigned KTV or history incorrect';
  end if;
  v_error := false;
  begin perform public.admin_confirm_revoked_student_request((select id from admin_resolution_fixture where key='confirm_locked'),'Ghi chú');
  exception when sqlstate 'P0001' then v_error := true; end;
  if not v_error then raise exception 'FAIL DF-048: locked student was handled by Admin'; end if;
  v_error := false;
  begin perform public.admin_request_rework_revoked_student_request((select id from admin_resolution_fixture where key='confirm_active'),'Lý do');
  exception when sqlstate 'P0001' then v_error := true; end;
  if not v_error then raise exception 'FAIL DF-048: active student was handled by Admin'; end if;
  raise notice 'PASS DF-048: revoked-only recheck, required notes, completion/rework history and technician retention';
end $$;
reset role;

select set_config('request.jwt.claim.sub',(select id::text from admin_resolution_fixture where key='tech_old_active'),true);
set local role authenticated;
do $$ declare v_denied boolean := false; begin
  begin
    perform public.technician_get_job((select id from admin_resolution_fixture where key='awaiting_rework'));
  exception when sqlstate 'P0002' then v_denied := true;
  end;
  if not v_denied then raise exception 'FAIL DF-047: former technician retained job operation access'; end if;
  raise notice 'PASS DF-047: former technician cannot read/operate the transferred request through the legacy RPC';
end $$;
reset role;

select set_config('request.jwt.claim.sub',(select id::text from admin_resolution_fixture where key='tech_new'),true);
set local role authenticated;
do $$ declare v_job jsonb; begin
  v_job := public.technician_get_job((select id from admin_resolution_fixture where key='in_progress'));
  if v_job->'workflow'->>'can_confirm_transfer' <> 'true'
    or v_job->'workflow'->>'can_submit_result' <> 'false' then
    raise exception 'FAIL compatibility: transferred in-progress KTV is not required to confirm continuation';
  end if;
  v_job := public.technician_get_job((select id from admin_resolution_fixture where key='awaiting_rework'));
  if v_job->'workflow'->>'can_continue' <> 'true' then
    raise exception 'FAIL compatibility: transferred rework KTV is not required to continue';
  end if;
  perform public.technician_continue_job((select id from admin_resolution_fixture where key='awaiting_rework'),2);
  if (select status from public.repair_requests where id=(select id from admin_resolution_fixture where key='awaiting_rework')) <> 'in_progress' then
    raise exception 'FAIL compatibility: new KTV could not continue rework';
  end if;
  raise notice 'PASS compatibility: existing technician_continue_job accepts the new assignment and retains required start step';
end $$;
reset role;
rollback;
select 'PASS: DF-047/048 transactional rollback fixtures removed' as result;
