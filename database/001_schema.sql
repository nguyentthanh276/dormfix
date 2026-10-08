-- DormFix: schema and baseline read permissions for a NEW Supabase project.
-- Run once in SQL Editor. No passwords, service-role keys, or Auth users here.
-- Workflow writes and account administration require subsequent server functions.
begin;

create type public.app_role as enum ('admin', 'student', 'technician');
create type public.account_status as enum ('active', 'locked', 'revoked');
create type public.repair_status as enum (
  'pending', 'assigned', 'in_progress', 'awaiting_confirmation',
  'awaiting_rework', 'completed', 'rejected', 'cancelled'
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null check (length(trim(code)) > 0),
  building text not null check (length(trim(building)) > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index rooms_code_unique on public.rooms (lower(trim(code)));

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  identity_code text not null check (length(trim(identity_code)) > 0),
  full_name text not null check (length(trim(full_name)) > 0),
  email text not null check (length(trim(email)) > 0),
  phone text,
  role public.app_role not null,
  status public.account_status not null default 'active',
  room_id uuid references public.rooms(id) on delete restrict,
  must_change_password boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (role = 'admin' or nullif(trim(phone), '') is not null),
  check ((role = 'student' and room_id is not null) or
         (role <> 'student' and room_id is null))
);
create unique index profiles_identity_unique on public.profiles (lower(trim(identity_code)));
create unique index profiles_email_unique on public.profiles (lower(trim(email)));
create index profiles_room_idx on public.profiles (room_id);

create table public.incident_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index categories_name_unique on public.incident_categories (lower(trim(name)));

create table public.repair_requests (
  id uuid primary key default gen_random_uuid(),
  request_number bigint generated always as identity unique,
  -- A sequence is increasing but can have gaps after a rollback.
  request_code text generated always as
    ('DF' || case when length(request_number::text) < 6
      then lpad(request_number::text, 6, '0') else request_number::text end) stored unique,
  student_id uuid not null references public.profiles(id) on delete restrict,
  room_id uuid not null references public.rooms(id) on delete restrict,
  room_code_snapshot text not null check (length(trim(room_code_snapshot)) > 0),
  building_snapshot text not null check (length(trim(building_snapshot)) > 0),
  category_id uuid not null references public.incident_categories(id) on delete restrict,
  category_name_snapshot text not null check (length(trim(category_name_snapshot)) > 0),
  title text not null check (length(trim(title)) > 0),
  description text not null check (length(trim(description)) > 0),
  status public.repair_status not null default 'pending',
  assigned_technician_id uuid references public.profiles(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  check (status not in ('assigned', 'in_progress', 'awaiting_confirmation', 'awaiting_rework')
         or assigned_technician_id is not null)
);
create index requests_student_status_idx on public.repair_requests (student_id, status);
create index requests_technician_status_idx on public.repair_requests (assigned_technician_id, status);
create index requests_created_idx on public.repair_requests (created_at);
create index requests_updated_idx on public.repair_requests (updated_at);
create index requests_room_idx on public.repair_requests (room_id);
create index requests_category_idx on public.repair_requests (category_id);

create table public.request_assignments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.repair_requests(id) on delete restrict,
  technician_id uuid not null references public.profiles(id) on delete restrict,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  ended_at timestamptz,
  end_reason text,
  transfer_reason text,
  needs_transfer_confirmation boolean not null default false,
  transfer_confirmed_at timestamptz,
  -- Snapshot fields are the ONLY former-job details the old technician can read.
  request_code_snapshot text not null,
  title_snapshot text not null,
  room_code_snapshot text not null,
  check (ended_at is null or ended_at >= assigned_at),
  check (not needs_transfer_confirmation or transfer_confirmed_at is null)
);
create unique index one_current_assignment on public.request_assignments (request_id)
  where ended_at is null;
create index assignment_technician_idx on public.request_assignments (technician_id, assigned_at);

create table public.repair_results (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.repair_requests(id) on delete restrict,
  assignment_id uuid not null references public.request_assignments(id) on delete restrict,
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  content text not null check (length(trim(content)) > 0),
  submitted_at timestamptz not null default now(),
  unique (id, request_id)
);
create index result_request_idx on public.repair_results (request_id, submitted_at);

create table public.request_feedback (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.repair_requests(id) on delete restrict,
  kind text not null check (kind in ('rework', 'reopen')),
  reason text not null check (length(trim(reason)) > 0),
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, request_id)
);
create index feedback_request_idx on public.request_feedback (request_id, created_at);

create table public.request_attachments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.repair_requests(id) on delete restrict,
  result_id uuid,
  feedback_id uuid,
  storage_path text not null unique check (length(trim(storage_path)) > 0),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 5242880),
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (num_nonnulls(result_id, feedback_id) <= 1),
  foreign key (result_id, request_id) references public.repair_results(id, request_id) on delete restrict,
  foreign key (feedback_id, request_id) references public.request_feedback(id, request_id) on delete restrict
);
create index attachment_request_idx on public.request_attachments (request_id);

create table public.request_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.repair_requests(id) on delete restrict,
  -- Also records account/room/category administration without adding another table.
  entity_type text not null check (entity_type in ('request', 'profile', 'room', 'category')),
  entity_id uuid not null,
  action text not null check (length(trim(action)) > 0),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  old_status text,
  new_status text,
  note text,
  occurred_at timestamptz not null default now(),
  check ((entity_type = 'request' and request_id = entity_id and request_id is not null)
         or (entity_type <> 'request' and request_id is null))
);
create index history_request_idx on public.request_history (request_id, occurred_at);
create index history_entity_idx on public.request_history (entity_type, entity_id, occurred_at);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  request_id uuid not null references public.repair_requests(id) on delete restrict,
  event_type text not null check (event_type in
    ('assigned', 'transferred_in', 'transferred_out', 'cancelled', 'rejected',
     'repair_reported', 'rework_requested', 'completed')),
  -- Content must be a generic event message, never photos or detailed results.
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notification_recipient_idx on public.notifications (recipient_id, created_at);

-- Keep role/status checks in database; caller cannot choose its own identity.
create function public.current_active_role() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid() and status = 'active'
    and not must_change_password;
$$;
create function public.current_student_room() returns uuid
language sql stable security definer set search_path = '' as $$
  select room_id from public.profiles where id = auth.uid() and role = 'student'
    and status = 'active' and not must_change_password;
$$;
create function public.can_read_request(p_request_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.repair_requests r
    join public.profiles p on p.id = auth.uid() and p.status = 'active'
      and not p.must_change_password
    where r.id = p_request_id and (
      p.role = 'admin' or (p.role = 'student' and r.student_id = p.id)
      or (p.role = 'technician' and r.assigned_technician_id = p.id)
    )
  );
$$;
revoke all on function public.current_active_role() from public, anon;
revoke all on function public.can_read_request(uuid) from public, anon;
revoke all on function public.current_student_room() from public, anon;
grant execute on function public.current_active_role() to authenticated;
grant execute on function public.can_read_request(uuid) to authenticated;
grant execute on function public.current_student_room() to authenticated;

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.incident_categories enable row level security;
alter table public.repair_requests enable row level security;
alter table public.request_assignments enable row level security;
alter table public.repair_results enable row level security;
alter table public.request_feedback enable row level security;
alter table public.request_attachments enable row level security;
alter table public.request_history enable row level security;
alter table public.notifications enable row level security;

revoke all on public.profiles, public.rooms, public.incident_categories,
 public.repair_requests, public.request_assignments, public.repair_results,
 public.request_feedback, public.request_attachments, public.request_history,
 public.notifications from anon, authenticated;

-- Do not expose counterpart email, room, role or account-management flags.
grant select (id, full_name, phone) on public.profiles to authenticated;
create policy profile_contact_read on public.profiles for select to authenticated using (
 public.current_active_role() is not null and (
 id = auth.uid() or public.current_active_role() = 'admin'
 or exists (select 1 from public.repair_requests r where
   (r.student_id = auth.uid() and r.assigned_technician_id = profiles.id)
   or (r.assigned_technician_id = auth.uid() and r.student_id = profiles.id))
 )
);
-- Full own/Admin profile reads require a server endpoint, not broad table grants.
grant select on public.rooms, public.incident_categories, public.repair_requests,
 public.repair_results, public.request_feedback, public.request_attachments,
 public.request_history, public.notifications to authenticated;
create policy rooms_read on public.rooms for select to authenticated using (
 public.current_active_role() = 'admin' or
 (public.current_active_role() = 'student' and id = public.current_student_room())
);
create policy categories_read on public.incident_categories for select to authenticated
 using (public.current_active_role() is not null);
create policy requests_read on public.repair_requests for select to authenticated
 using (public.can_read_request(id));
create policy results_read on public.repair_results for select to authenticated
 using (public.can_read_request(request_id));
create policy feedback_read on public.request_feedback for select to authenticated
 using (public.can_read_request(request_id));
create policy attachments_read on public.request_attachments for select to authenticated
 using (public.can_read_request(request_id));
create policy history_read on public.request_history for select to authenticated
 using (public.current_active_role() = 'admin' or public.can_read_request(request_id));
create policy notifications_read on public.notifications for select to authenticated
 using (recipient_id = auth.uid() and public.current_active_role() is not null);

-- Former technicians read only the five agreed summary fields plus technical IDs.
grant select (id, request_id, technician_id, request_code_snapshot, title_snapshot,
 room_code_snapshot, assigned_at, ended_at) on public.request_assignments to authenticated;
create policy assignments_read on public.request_assignments for select to authenticated using (
 public.current_active_role() = 'admin' or
 (public.current_active_role() = 'technician' and technician_id = auth.uid())
);

insert into public.incident_categories (name) values ('Điện'), ('Nước'), ('Nội thất'), ('Khác');
-- No client writes, Storage policies, or auth users are enabled by this migration.
commit;
