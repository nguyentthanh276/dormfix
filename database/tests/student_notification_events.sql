-- Owner-run DF-017 regression. Synthetic passwordless users and all fixture
-- mutations are rolled back. Apply the notification-events migration first.
begin;

create temporary table student_event_ids (
  key text primary key, id uuid not null default gen_random_uuid()
) on commit drop;
insert into student_event_ids(key) values
 ('student'),('other_student'),('admin'),('tech'),('new_tech'),('room'),('category'),
 ('assigned'),('rejected'),('existing'),('atomic'),('non_admin_update'),('result');
grant select on student_event_ids to authenticated,anon;
do $$ begin
  execute format('grant usage on schema %I to authenticated,anon',
    (select nspname from pg_namespace where oid = pg_my_temp_schema()));
end $$;

create function pg_temp.se_id(p_key text) returns uuid language sql stable as $$
  select id from student_event_ids where key = p_key;
$$;

create function pg_temp.se_expect_error(p_sql text, p_state text, p_message text default null)
returns void language plpgsql as $$
declare v_state text; v_message text;
begin
  begin execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state <> p_state or (p_message is not null and v_message <> p_message) then
      raise exception 'FAIL: expected % %, got % %',p_state,p_message,v_state,v_message;
    end if;
    return;
  end;
  raise exception 'FAIL: expected % %',p_state,p_message;
end $$;
grant execute on function pg_temp.se_id(text),pg_temp.se_expect_error(text,text,text)
to authenticated,anon;

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated',id::text||'@student-event.invalid',now(),now(),now()
from student_event_ids where key in ('student','other_student','admin','tech','new_tech');
insert into public.rooms(id,code,building)
values(pg_temp.se_id('room'),'SE-'||pg_temp.se_id('room')::text,'Student event building');
insert into public.incident_categories(id,name)
values(pg_temp.se_id('category'),'SE-'||pg_temp.se_id('category')::text);
insert into public.profiles(id,identity_code,full_name,email,phone,role,room_id,must_change_password)
select id,'SE-'||id::text,'Student event '||key,id::text||'@student-event.invalid','0900000000',
  case when key='admin' then 'admin'::public.app_role
    when key in ('tech','new_tech') then 'technician'::public.app_role
    else 'student'::public.app_role end,
  case when key in ('student','other_student') then pg_temp.se_id('room') end,false
from student_event_ids where key in ('student','other_student','admin','tech','new_tech');
insert into public.repair_requests(id,student_id,room_id,room_code_snapshot,building_snapshot,
 category_id,category_name_snapshot,title,description,status,assigned_technician_id)
select id,pg_temp.se_id('student'),pg_temp.se_id('room'),'Student event room','Student event building',
  pg_temp.se_id('category'),'Student event category','Private request title','Private request content',
  case when key='existing' then 'assigned'::public.repair_status else 'pending'::public.repair_status end,
  case when key='existing' then pg_temp.se_id('tech') end
from student_event_ids where key in ('assigned','rejected','existing','atomic','non_admin_update');

do $$ begin
  if has_function_privilege('anon','public._notify_student_admin_request_event()','EXECUTE')
    or has_function_privilege('authenticated','public._notify_student_admin_request_event()','EXECUTE')
    or not exists(select 1 from pg_proc p
      where p.oid='public._notify_student_admin_request_event()'::regprocedure
        and p.prosecdef and 'search_path=""'=any(p.proconfig))
    or has_table_privilege('authenticated','public.notifications','INSERT')
    or has_table_privilege('authenticated','public.notifications','UPDATE')
    or has_table_privilege('authenticated','public.notifications','DELETE') then
    raise exception 'FAIL: trigger exposure or notification table write privileges';
  end if;
end $$;

-- Confirm seed/maintenance writes outside an active Admin session do not emit
-- student events. The status trigger is also ineligible on INSERT.
select set_config('request.jwt.claim.sub','',true);
update public.repair_requests set status='rejected' where id=pg_temp.se_id('non_admin_update');

select set_config('request.jwt.claim.sub',pg_temp.se_id('admin')::text,true);
set local role authenticated;
select public.admin_assign_request(pg_temp.se_id('assigned'),pg_temp.se_id('tech'));
select public.admin_reject_request(pg_temp.se_id('rejected'),'Private reason');
select pg_temp.se_expect_error(
  'select public.admin_assign_request(pg_temp.se_id(''assigned''),pg_temp.se_id(''tech''))','P0001');
select pg_temp.se_expect_error(
  'select public.admin_reject_request(pg_temp.se_id(''rejected''),''Retry'')','P0001');

-- Roll back a real successful Admin write from a subtransaction. This must
-- also roll back the generated student event and Admin history.
do $$ begin
  begin
    perform public.admin_reject_request(pg_temp.se_id('atomic'),'Rollback reason');
    raise exception using errcode='P7000',message='Rollback fixture';
  exception when sqlstate 'P7000' then
    null;
  end;
end $$;
reset role;

-- Exercise the trigger with an explicit no-op status write carrying Admin JWT.
update public.repair_requests set status=status
where id in (pg_temp.se_id('assigned'),pg_temp.se_id('rejected'),pg_temp.se_id('existing'));

do $$ begin
  if (select count(*) from public.notifications n where n.recipient_id=pg_temp.se_id('student')
      and n.request_id=pg_temp.se_id('assigned') and n.event_type='assigned'
      and n.message='Yêu cầu sửa chữa đã được phân công.' and n.read_at is null)<>1
    or (select count(*) from public.notifications n where n.recipient_id=pg_temp.se_id('student')
      and n.request_id=pg_temp.se_id('rejected') and n.event_type='rejected'
      and n.message='Yêu cầu sửa chữa đã bị từ chối.' and n.read_at is null)<>1
    or (select count(*) from public.notifications n where n.recipient_id=pg_temp.se_id('tech')
      and n.request_id=pg_temp.se_id('assigned') and n.event_type='assigned')<>1
    or exists(select 1 from public.notifications n
      where n.request_id in (pg_temp.se_id('existing'),pg_temp.se_id('atomic'),pg_temp.se_id('non_admin_update')))
    or not exists(select 1 from public.repair_requests r
      where r.id=pg_temp.se_id('atomic') and r.status='pending')
    or exists(select 1 from public.request_history h where h.request_id=pg_temp.se_id('atomic')) then
    raise exception 'FAIL: exact Admin events, generic content, KTV event, no duplicate/backfill, or atomic rollback';
  end if;
end $$;

-- Transfer is the existing KTV event only. The subsequent real technician
-- result submission must still emit exactly one repair_reported to the student.
set local role authenticated;
select public.admin_transfer_request(pg_temp.se_id('assigned'),pg_temp.se_id('new_tech'),'Private transfer reason');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.se_id('new_tech')::text,true);
set local role authenticated;
select public.technician_start_job(pg_temp.se_id('assigned'),3);
select public.technician_submit_result(pg_temp.se_id('assigned'),4,pg_temp.se_id('result'),'Private result content');
reset role;

do $$ begin
  if (select count(*) from public.notifications n where n.recipient_id=pg_temp.se_id('student')
      and n.request_id=pg_temp.se_id('assigned') and n.event_type='assigned')<>1
    or (select count(*) from public.notifications n where n.recipient_id=pg_temp.se_id('student')
      and n.request_id=pg_temp.se_id('assigned') and n.event_type='repair_reported')<>1
    or (select count(*) from public.notifications n where n.recipient_id=pg_temp.se_id('tech')
      and n.request_id=pg_temp.se_id('assigned') and n.event_type='transferred_out')<>1
    or (select count(*) from public.notifications n where n.recipient_id=pg_temp.se_id('new_tech')
      and n.request_id=pg_temp.se_id('assigned') and n.event_type='transferred_in')<>1 then
    raise exception 'FAIL: transfer/result behavior changed or duplicate student event';
  end if;
end $$;

-- A second student cannot read these rows or create their own notifications.
select set_config('request.jwt.claim.sub',pg_temp.se_id('other_student')::text,true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.notifications where request_id in(pg_temp.se_id('assigned'),pg_temp.se_id('rejected'))) then
    raise exception 'FAIL: notifications exposed to another student';
  end if;
  perform pg_temp.se_expect_error(
    'select public.admin_assign_request(pg_temp.se_id(''atomic''),pg_temp.se_id(''tech''))','42501');
  perform pg_temp.se_expect_error(
    'insert into public.notifications(recipient_id,request_id,event_type,message) values(auth.uid(),pg_temp.se_id(''assigned''),''assigned'',''Forged'')',
    '42501');
end $$;
reset role;

select set_config('request.jwt.claim.sub',pg_temp.se_id('student')::text,true);
set local role authenticated;
do $$ declare v_id uuid; v_first jsonb; v_repeated jsonb; v_all jsonb; begin
  if (select count(*) from public.notifications where recipient_id=auth.uid())<>3
    or exists(select 1 from public.notifications where recipient_id<>auth.uid()) then
    raise exception 'FAIL: student inbox filters';
  end if;
  select id into strict v_id from public.notifications where event_type='assigned';
  v_first := public.student_mark_notification_read(v_id);
  v_repeated := public.student_mark_notification_read(v_id);
  if v_first->>'id' is distinct from v_id::text or v_first->>'read_at' is null
    or v_repeated is distinct from v_first then
    raise exception 'FAIL: mark-one receipt or replay';
  end if;
  v_all := public.student_mark_all_notifications_read();
  if v_all->>'updated_count' is distinct from '2' then
    raise exception 'FAIL: mark-all expected two rows, got %',v_all->>'updated_count';
  end if;
  if exists(select 1 from public.notifications where recipient_id=auth.uid() and read_at is null) then
    raise exception 'FAIL: unread rows remain after mark-all';
  end if;
end $$;
reset role;

update public.profiles set status='locked' where id=pg_temp.se_id('student');
set local role authenticated;
do $$ begin
  if exists(select 1 from public.notifications where request_id in(pg_temp.se_id('assigned'),pg_temp.se_id('rejected'))) then
    raise exception 'FAIL: locked student can still read notifications';
  end if;
  perform pg_temp.se_expect_error('select public.student_mark_all_notifications_read()','42501','STUDENT_ACCESS_DENIED');
end $$;
reset role;

rollback;
select 'PASS: DF-017 Admin assignment/rejection notifications, RLS, rollback and legacy events' as result;
