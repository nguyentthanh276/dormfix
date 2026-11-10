-- DF-039–042 / DF-049–050: guarded Admin room and incident category workflows.
-- Existing requests keep their room/building/category snapshots.
begin;

create function public._admin_room_summary(p_room public.rooms) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id',p_room.id,'code',p_room.code,'building',p_room.building,'is_active',p_room.is_active,
    'student_count',count(*),
    'profiles',coalesce(jsonb_agg(jsonb_build_object('full_name',p.full_name)
      order by p.full_name,p.id),'[]'::jsonb)
  )
  from public.profiles p
  where p.room_id = p_room.id and p.role = 'student' and p.status in ('active','locked');
$$;

create function public._admin_incident_category_summary(p_category public.incident_categories) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'id',p_category.id,'name',p_category.name,
    'is_active',p_category.is_active,'created_at',p_category.created_at
  );
$$;

create function public.admin_list_rooms() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_rooms jsonb;
begin
  perform public._admin_request_actor();
  select coalesce(jsonb_agg(public._admin_room_summary(r) order by lower(r.code),r.id),'[]'::jsonb)
    into v_rooms from public.rooms r;
  return v_rooms;
end $$;

create function public.admin_list_incident_categories() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_categories jsonb;
begin
  perform public._admin_request_actor();
  select coalesce(jsonb_agg(public._admin_incident_category_summary(c) order by c.created_at,c.id),'[]'::jsonb)
    into v_categories from public.incident_categories c;
  return v_categories;
end $$;

create function public._admin_write_room(
  p_action text,p_room_id uuid,p_code text,p_building text
) returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_code text := nullif(regexp_replace(p_code,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_building text := nullif(regexp_replace(p_building,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_room public.rooms%rowtype;
  v_now timestamptz;
  v_audit_action text;
  v_old_status text;
  v_new_status text;
  v_note text;
  v_constraint text;
begin
  if p_action in ('create','update') and (v_code is null or v_building is null) then
    raise exception using errcode = '22023', message = 'INVALID_ROOM_INPUT';
  end if;

  if p_action <> 'create' then
    select * into v_room from public.rooms where id = p_room_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'ROOM_NOT_FOUND'; end if;

    if (p_action = 'update' and v_room.code = v_code and v_room.building = v_building)
      or (p_action = 'deactivate' and not v_room.is_active) then
      return public._admin_room_summary(v_room) || jsonb_build_object('changed',false);
    end if;
  end if;

  if p_action = 'deactivate' and exists(
    select 1 from public.profiles p
    where p.room_id = p_room_id and p.role = 'student' and p.status in ('active','locked')
  ) then
    -- The room is already locked FOR UPDATE. Any future account assignment,
    -- restore or room-switch RPC must lock/check the destination room FOR SHARE
    -- before writing membership, as the current student request creation does.
    raise exception using errcode = 'P0001', message = 'ROOM_HAS_STUDENTS';
  end if;

  v_now := clock_timestamp();
  case p_action
    when 'create' then
      insert into public.rooms(code,building,created_at,updated_at)
        values(v_code,v_building,v_now,v_now) returning * into v_room;
      v_audit_action := 'admin_room_created';
      v_new_status := 'active';
      v_note := format('%s · %s',v_room.code,v_room.building);
    when 'update' then
      v_audit_action := 'admin_room_updated';
      v_note := format('%s · %s → %s · %s',v_room.code,v_room.building,v_code,v_building);
      update public.rooms set code = v_code,building = v_building,updated_at = v_now
        where id = p_room_id returning * into v_room;
    when 'deactivate' then
      v_audit_action := 'admin_room_deactivated';
      v_old_status := 'active';
      v_new_status := 'inactive';
      v_note := format('%s · %s',v_room.code,v_room.building);
      update public.rooms set is_active = false,updated_at = v_now
        where id = p_room_id returning * into v_room;
  end case;

  insert into public.request_history(entity_type,entity_id,action,actor_id,old_status,new_status,note,occurred_at)
    values('room',v_room.id,v_audit_action,v_admin,v_old_status,v_new_status,v_note,v_now);
  return public._admin_room_summary(v_room) || jsonb_build_object('changed',true);
exception when unique_violation then
  get stacked diagnostics v_constraint = constraint_name;
  if v_constraint = 'rooms_code_unique' then
    raise exception using errcode = '23505', message = 'ROOM_CODE_ALREADY_EXISTS';
  end if;
  raise;
end $$;

create function public._admin_write_incident_category(
  p_action text,p_category_id uuid,p_name text,p_is_active boolean
) returns jsonb language plpgsql volatile set search_path = '' as $$
declare
  v_admin uuid := public._admin_request_actor();
  v_name text := nullif(regexp_replace(p_name,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  v_category public.incident_categories%rowtype;
  v_now timestamptz;
  v_audit_action text;
  v_old_status text;
  v_new_status text;
  v_note text;
  v_constraint text;
begin
  if (p_action in ('create','rename') and v_name is null)
    or (p_action = 'set_active' and p_is_active is null) then
    raise exception using errcode = '22023', message = 'INVALID_CATEGORY_INPUT';
  end if;

  if p_action <> 'create' then
    select * into v_category from public.incident_categories where id = p_category_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'CATEGORY_NOT_FOUND'; end if;
    if (p_action = 'rename' and v_category.name = v_name)
      or (p_action = 'set_active' and v_category.is_active = p_is_active) then
      return public._admin_incident_category_summary(v_category) || jsonb_build_object('changed',false);
    end if;
  end if;

  v_now := clock_timestamp();
  case p_action
    when 'create' then
      insert into public.incident_categories(name,created_at,updated_at)
        values(v_name,v_now,v_now) returning * into v_category;
      v_audit_action := 'admin_category_created';
      v_new_status := 'active';
      v_note := v_category.name;
    when 'rename' then
      v_audit_action := 'admin_category_renamed';
      v_note := format('%s → %s',v_category.name,v_name);
      update public.incident_categories set name = v_name,updated_at = v_now
        where id = p_category_id returning * into v_category;
    when 'set_active' then
      v_audit_action := case when p_is_active then 'admin_category_activated' else 'admin_category_deactivated' end;
      v_old_status := case when v_category.is_active then 'active' else 'inactive' end;
      v_new_status := case when p_is_active then 'active' else 'inactive' end;
      v_note := v_category.name;
      update public.incident_categories set is_active = p_is_active,updated_at = v_now
        where id = p_category_id returning * into v_category;
  end case;

  insert into public.request_history(entity_type,entity_id,action,actor_id,old_status,new_status,note,occurred_at)
    values('category',v_category.id,v_audit_action,v_admin,v_old_status,v_new_status,v_note,v_now);
  return public._admin_incident_category_summary(v_category) || jsonb_build_object('changed',true);
exception when unique_violation then
  get stacked diagnostics v_constraint = constraint_name;
  if v_constraint = 'categories_name_unique' then
    raise exception using errcode = '23505', message = 'CATEGORY_NAME_ALREADY_EXISTS';
  end if;
  raise;
end $$;

create function public.admin_create_room(p_code text,p_building text) returns jsonb
language sql volatile security definer set search_path = '' as $$
  select public._admin_write_room('create',null,p_code,p_building);
$$;

create function public.admin_update_room(p_room_id uuid,p_code text,p_building text) returns jsonb
language sql volatile security definer set search_path = '' as $$
  select public._admin_write_room('update',p_room_id,p_code,p_building);
$$;

create function public.admin_deactivate_room(p_room_id uuid) returns jsonb
language sql volatile security definer set search_path = '' as $$
  select public._admin_write_room('deactivate',p_room_id,null,null);
$$;

create function public.admin_create_incident_category(p_name text) returns jsonb
language sql volatile security definer set search_path = '' as $$
  select public._admin_write_incident_category('create',null,p_name,null);
$$;

create function public.admin_rename_incident_category(p_category_id uuid,p_name text) returns jsonb
language sql volatile security definer set search_path = '' as $$
  select public._admin_write_incident_category('rename',p_category_id,p_name,null);
$$;

create function public.admin_set_incident_category_active(p_category_id uuid,p_is_active boolean) returns jsonb
language sql volatile security definer set search_path = '' as $$
  select public._admin_write_incident_category('set_active',p_category_id,null,p_is_active);
$$;

revoke all on function public._admin_room_summary(public.rooms),
  public._admin_incident_category_summary(public.incident_categories),
  public._admin_write_room(text,uuid,text,text),public._admin_write_incident_category(text,uuid,text,boolean)
  from public,anon,authenticated;

revoke all on function public.admin_list_rooms(),public.admin_create_room(text,text),
  public.admin_update_room(uuid,text,text),public.admin_deactivate_room(uuid),
  public.admin_list_incident_categories(),public.admin_create_incident_category(text),
  public.admin_rename_incident_category(uuid,text),public.admin_set_incident_category_active(uuid,boolean)
  from public,anon;
grant execute on function public.admin_list_rooms(),public.admin_create_room(text,text),
  public.admin_update_room(uuid,text,text),public.admin_deactivate_room(uuid),
  public.admin_list_incident_categories(),public.admin_create_incident_category(text),
  public.admin_rename_incident_category(uuid,text),public.admin_set_incident_category_active(uuid,boolean)
  to authenticated;

commit;
