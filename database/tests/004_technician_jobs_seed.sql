-- OPTIONAL MANUAL DEMO SEED, NOT A MIGRATION AND NOT AUTO-DEPLOYED.
-- Persists four assigned jobs only when an operator explicitly runs this file.
-- Requires the existing ADMIN001 / SV001 / KTV001 demo profiles from 002.
-- Does not create Auth users, change passwords/status/gates, or upload fake images.
begin;
do $$
declare
  v_admin uuid;
  v_student public.profiles%rowtype;
  v_technician public.profiles%rowtype;
  v_room public.rooms%rowtype;
  v_category public.incident_categories%rowtype;
  v_status public.repair_status;
  v_request public.repair_requests%rowtype;
  v_assignment uuid;
  v_created timestamptz;
  v_index integer := 0;
begin
  select id into strict v_admin from public.profiles
  where lower(trim(identity_code)) = 'admin001' and role = 'admin' and status = 'active';
  select * into strict v_student from public.profiles
  where lower(trim(identity_code)) = 'sv001' and role = 'student' and status = 'active';
  select * into strict v_technician from public.profiles
  where lower(trim(identity_code)) = 'ktv001' and role = 'technician' and status = 'active';
  select * into strict v_room from public.rooms where id = v_student.room_id and is_active;
  select * into v_category from public.incident_categories where is_active
  order by (lower(trim(name)) = 'điện') desc, name, id limit 1;
  if not found then raise exception 'DEMO_SEED_REQUIRES_ACTIVE_CATEGORY'; end if;
  if exists (select 1 from public.repair_requests where title like '[DF020 DEMO] %') then
    raise exception 'DEMO_SEED_ALREADY_EXISTS: inspect existing demo requests; this seed does not overwrite data';
  end if;
  if v_technician.must_change_password then
    raise notice 'KTV001 still requires a password change. This seed preserves that gate; use the safe server flow before testing in Flutter.';
  end if;

  foreach v_status in array array['assigned', 'awaiting_rework', 'completed', 'cancelled']::public.repair_status[] loop
    v_index := v_index + 1;
    v_created := now() - (5 - v_index) * interval '1 day';
    insert into public.repair_requests
     (student_id, room_id, room_code_snapshot, building_snapshot, category_id,
      category_name_snapshot, title, description, status, assigned_technician_id,
      version, created_at, updated_at, completed_at)
    values
     (v_student.id, v_room.id, v_room.code, v_room.building, v_category.id, v_category.name,
      '[DF020 DEMO] ' || case v_status when 'assigned' then 'Đèn phòng không sáng'
        when 'awaiting_rework' then 'Ổ điện cần kiểm tra lại'
        when 'completed' then 'Đã thay bóng đèn' else 'Sinh viên đã hủy yêu cầu' end,
      'Dữ liệu demo Sprint 1 để kiểm tra danh sách và chi tiết công việc. Không phải sự cố thực tế.',
      v_status, v_technician.id,
      case v_status when 'assigned' then 2 when 'cancelled' then 3 else 5 end,
      v_created, v_created + case v_status when 'assigned' then interval '10 minutes'
        when 'cancelled' then interval '20 minutes' else interval '40 minutes' end,
      case when v_status = 'completed' then v_created + interval '40 minutes' end)
    returning * into v_request;
    insert into public.request_assignments
     (request_id, technician_id, assigned_by, assigned_at,
      request_code_snapshot, title_snapshot, room_code_snapshot)
    values (v_request.id, v_technician.id, v_admin, v_created + interval '10 minutes',
      v_request.request_code, v_request.title, v_request.room_code_snapshot)
    returning id into v_assignment;
    insert into public.request_history
     (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, occurred_at)
    values
     (v_request.id, 'request', v_request.id, 'created', v_student.id, null, 'pending', v_created),
     (v_request.id, 'request', v_request.id, 'assigned', v_admin, 'pending', 'assigned', v_created + interval '10 minutes');
    if v_status in ('awaiting_rework', 'completed') then
      insert into public.repair_results (request_id, assignment_id, submitted_by, content, submitted_at)
      values (v_request.id, v_assignment, v_technician.id,
        'Đã kiểm tra, thay linh kiện và thử hoạt động. Kết quả mẫu để kiểm tra màn hình chi tiết.',
        v_created + interval '30 minutes');
      insert into public.request_history
       (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, occurred_at)
      values
       (v_request.id, 'request', v_request.id, 'started', v_technician.id, 'assigned', 'in_progress', v_created + interval '20 minutes'),
       (v_request.id, 'request', v_request.id, 'repair_reported', v_technician.id, 'in_progress', 'awaiting_confirmation', v_created + interval '30 minutes');
      if v_status = 'awaiting_rework' then
        insert into public.request_feedback (request_id, kind, reason, submitted_by, created_at)
        values (v_request.id, 'rework', 'Ổ điện vẫn chập chờn, nhờ kiểm tra lại.', v_student.id, v_created + interval '40 minutes');
        insert into public.request_history
         (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
        values (v_request.id, 'request', v_request.id, 'rework_requested', v_student.id,
          'awaiting_confirmation', 'awaiting_rework', 'Ổ điện vẫn chập chờn, nhờ kiểm tra lại.', v_created + interval '40 minutes');
      else
        insert into public.request_history
         (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, occurred_at)
        values (v_request.id, 'request', v_request.id, 'completed', v_student.id,
          'awaiting_confirmation', 'completed', v_created + interval '40 minutes');
      end if;
    elsif v_status = 'cancelled' then
      insert into public.request_history
       (request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at)
      values (v_request.id, 'request', v_request.id, 'cancelled', v_student.id,
        'assigned', 'cancelled', 'Sinh viên không còn nhu cầu sửa chữa.', v_created + interval '20 minutes');
    end if;
  end loop;
end $$;
commit;

select request_code, title, status, updated_at from public.repair_requests
where title like '[DF020 DEMO] %' order by updated_at desc, id desc;
