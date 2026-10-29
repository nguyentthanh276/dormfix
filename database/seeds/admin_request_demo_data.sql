-- Development-only demo repair requests for the existing confirmed demo accounts.
-- Idempotent: an existing complete demo set is left unchanged; partial sets abort.
begin;

do $$
declare
  v_admin uuid;
  v_student public.profiles%rowtype;
  v_technician public.profiles%rowtype;
  v_categories uuid[];
  v_category_id uuid;
  v_category_name text;
  v_item record;
  v_request public.repair_requests%rowtype;
  v_assignment_id uuid;
  v_created_at timestamptz;
  v_updated_at timestamptz;
  v_rework_reason text := 'Cần siết lại khớp nối và kiểm tra rò nước.';
begin
  if exists (select 1 from public.repair_requests where title like '[DEMO-ADMIN] %') then
    if (select count(*) from public.repair_requests where title like '[DEMO-ADMIN] %') = 8 then
      raise notice 'Demo request set already exists; no rows inserted.';
      return;
    end if;
    raise exception 'A partial [DEMO-ADMIN] seed exists; inspect it before retrying.';
  end if;

  select id into strict v_admin from public.profiles
  where role = 'admin' and status = 'active' and not must_change_password
  order by created_at limit 1;
  select p.* into strict v_student from public.profiles p
  join public.rooms r on r.id = p.room_id and r.is_active
  where p.role = 'student' and p.status = 'active'
  order by p.created_at limit 1;
  select id into strict v_technician from public.profiles
  where role = 'technician' and status = 'active'
  order by created_at limit 1;
  select array_agg(id order by name) into v_categories
  from public.incident_categories where is_active;
  if coalesce(array_length(v_categories, 1), 0) = 0 then
    raise exception 'No active incident categories are available for demo requests.';
  end if;

  for v_item in
    select * from (values
      (1, 'pending'::public.repair_status, 'Bóng đèn phòng cần thay', 8),
      (2, 'assigned'::public.repair_status, 'Vòi nước đang rò nhẹ', 7),
      (3, 'in_progress'::public.repair_status, 'Ổ cắm điện chập chờn', 6),
      (4, 'awaiting_confirmation'::public.repair_status, 'Cửa tủ bị lệch bản lề', 5),
      (5, 'awaiting_rework'::public.repair_status, 'Vòi sen cần kiểm tra lại', 4),
      (6, 'completed'::public.repair_status, 'Quạt trần đã được sửa', 3),
      (7, 'rejected'::public.repair_status, 'Đề nghị lắp thêm kệ', 2),
      (8, 'cancelled'::public.repair_status, 'Yêu cầu kiểm tra khóa cửa', 1)
    ) as demo(seq, status, title, days_ago)
    order by seq
  loop
    v_category_id := v_categories[((v_item.seq - 1) % array_length(v_categories, 1)) + 1];
    select name into strict v_category_name from public.incident_categories where id = v_category_id;
    v_created_at := now() - make_interval(days => v_item.days_ago);
    v_updated_at := v_created_at + interval '3 hours';

    insert into public.repair_requests (
      student_id, room_id, room_code_snapshot, building_snapshot,
      category_id, category_name_snapshot, title, description, status,
      assigned_technician_id, created_at, updated_at, completed_at
    )
    select v_student.id, room.id, room.code, room.building,
      v_category_id, v_category_name, '[DEMO-ADMIN] ' || v_item.title,
      'Dữ liệu minh họa để xem danh sách, chi tiết và lịch sử yêu cầu.',
      v_item.status,
      case when v_item.status in ('assigned', 'in_progress', 'awaiting_confirmation', 'awaiting_rework', 'completed')
        then v_technician.id else null end,
      v_created_at, v_updated_at,
      case when v_item.status = 'completed' then v_updated_at else null end
    from public.rooms room where room.id = v_student.room_id
    returning * into v_request;

    v_assignment_id := null;
    if v_request.assigned_technician_id is not null then
      insert into public.request_assignments (
        request_id, technician_id, assigned_by, assigned_at,
        request_code_snapshot, title_snapshot, room_code_snapshot
      ) values (
        v_request.id, v_technician.id, v_admin, v_created_at + interval '1 hour',
        v_request.request_code, v_request.title, v_request.room_code_snapshot
      ) returning id into v_assignment_id;
    end if;

    insert into public.request_history (
      request_id, entity_type, entity_id, action, actor_id, new_status, note, occurred_at
    ) values (
      v_request.id, 'request', v_request.id, 'student_created', v_student.id,
      'pending', 'Tạo yêu cầu minh họa.', v_created_at
    );

    if v_item.status in ('assigned', 'in_progress', 'awaiting_confirmation', 'awaiting_rework', 'completed') then
      insert into public.request_history (
        request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at
      ) values (
        v_request.id, 'request', v_request.id, 'admin_assigned', v_admin,
        'pending', 'assigned', v_technician.full_name, v_created_at + interval '1 hour'
      );
    end if;
    if v_item.status in ('in_progress', 'awaiting_confirmation', 'awaiting_rework', 'completed') then
      insert into public.request_history (
        request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at
      ) values (
        v_request.id, 'request', v_request.id, 'technician_started', v_technician.id,
        'assigned', 'in_progress', 'Bắt đầu xử lý minh họa.', v_created_at + interval '2 hours'
      );
    end if;
    if v_item.status in ('awaiting_confirmation', 'awaiting_rework', 'completed') then
      insert into public.repair_results (request_id, assignment_id, submitted_by, content, submitted_at)
      values (v_request.id, v_assignment_id, v_technician.id,
        'Kết quả xử lý minh họa: đã kiểm tra và ghi nhận tình trạng thiết bị.', v_updated_at);
      insert into public.request_history (
        request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at
      ) values (
        v_request.id, 'request', v_request.id, 'technician_submitted_result', v_technician.id,
        'in_progress', 'awaiting_confirmation', 'Đã gửi kết quả minh họa.', v_updated_at
      );
    end if;
    if v_item.status = 'awaiting_rework' then
      insert into public.request_feedback (request_id, kind, reason, submitted_by)
      values (v_request.id, 'rework', v_rework_reason, v_student.id);
      insert into public.request_history (
        request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at
      ) values (
        v_request.id, 'request', v_request.id, 'student_requested_rework', v_student.id,
        'awaiting_confirmation', 'awaiting_rework', v_rework_reason, v_updated_at + interval '1 hour'
      );
    elsif v_item.status = 'completed' then
      insert into public.request_history (
        request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at
      ) values (
        v_request.id, 'request', v_request.id, 'student_confirmed', v_student.id,
        'awaiting_confirmation', 'completed', 'Đã kiểm tra, xác nhận hoàn tất (dữ liệu minh họa).', v_updated_at + interval '1 hour'
      );
    elsif v_item.status = 'rejected' then
      insert into public.request_history (
        request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at
      ) values (
        v_request.id, 'request', v_request.id, 'admin_rejected', v_admin,
        'pending', 'rejected', 'Từ chối minh họa: nội dung đề nghị ngoài phạm vi sửa chữa.', v_updated_at
      );
    elsif v_item.status = 'cancelled' then
      insert into public.request_history (
        request_id, entity_type, entity_id, action, actor_id, old_status, new_status, note, occurred_at
      ) values (
        v_request.id, 'request', v_request.id, 'student_cancelled', v_student.id,
        'pending', 'cancelled', 'Hủy yêu cầu minh họa.', v_updated_at
      );
    end if;
  end loop;
end $$;

commit;
