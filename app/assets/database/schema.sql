-- SQLite schema version 1. Loaded once by LocalDatabase.onCreate.
create table rooms (
  id TEXT PRIMARY KEY NOT NULL,
  code text not null check (length(trim(code)) > 0),
  building text not null check (length(trim(building)) > 0),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
create unique index rooms_code_unique on rooms (lower(trim(code)));

create table profiles (
  id TEXT PRIMARY KEY NOT NULL,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  password_iterations INTEGER NOT NULL CHECK (password_iterations >= 100000),
  identity_code text not null check (length(trim(identity_code)) > 0),
  full_name text not null check (length(trim(full_name)) > 0),
  email text not null check (length(trim(email)) > 0),
  phone text,
  role TEXT NOT NULL CHECK (role IN ('admin','student','technician')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','locked','revoked')),
  room_id TEXT references rooms(id) on delete restrict,
  must_change_password INTEGER NOT NULL DEFAULT 1 CHECK (must_change_password IN (0,1)),
  created_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  check (role = 'admin' or nullif(trim(phone), '') is not null),
  check ((role = 'student' and room_id is not null) or
         (role <> 'student' and room_id is null))
);
create unique index profiles_identity_unique on profiles (lower(trim(identity_code)));
create unique index profiles_email_unique on profiles (lower(trim(email)));
create index profiles_room_idx on profiles (room_id);

create table incident_categories (
  id TEXT PRIMARY KEY NOT NULL,
  name text not null check (length(trim(name)) > 0),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
create unique index categories_name_unique on incident_categories (lower(trim(name)));

create table repair_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_code TEXT UNIQUE,
  student_id TEXT not null references profiles(id) on delete restrict,
  room_id TEXT not null references rooms(id) on delete restrict,
  room_code_snapshot text not null check (length(trim(room_code_snapshot)) > 0),
  building_snapshot text not null check (length(trim(building_snapshot)) > 0),
  category_id TEXT not null references incident_categories(id) on delete restrict,
  category_name_snapshot text not null check (length(trim(category_name_snapshot)) > 0),
  title text not null check (length(trim(title)) > 0),
  description text not null check (length(trim(description)) > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','assigned','in_progress','awaiting_confirmation','awaiting_rework','completed','rejected','cancelled')),
  assigned_technician_id TEXT references profiles(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  created_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  completed_at TEXT,
  check (status not in ('assigned', 'in_progress', 'awaiting_confirmation', 'awaiting_rework')
         or assigned_technician_id is not null)
);
create index requests_student_status_idx on repair_requests (student_id, status);
create index requests_technician_status_idx on repair_requests (assigned_technician_id, status);
create index requests_created_idx on repair_requests (created_at);
create index requests_updated_idx on repair_requests (updated_at);
create index requests_room_idx on repair_requests (room_id);
create index requests_category_idx on repair_requests (category_id);

create table request_assignments (
  id TEXT PRIMARY KEY NOT NULL,
  request_id INTEGER not null references repair_requests(id) on delete restrict,
  technician_id TEXT not null references profiles(id) on delete restrict,
  assigned_by TEXT not null references profiles(id) on delete restrict,
  assigned_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  ended_at TEXT,
  end_reason text,
  transfer_reason text,
  needs_transfer_confirmation INTEGER NOT NULL DEFAULT 0 CHECK (needs_transfer_confirmation IN (0,1)),
  transfer_confirmed_at TEXT,
  
  request_code_snapshot text not null,
  title_snapshot text not null,
  room_code_snapshot text not null,
  check (ended_at is null or ended_at >= assigned_at),
  check (not needs_transfer_confirmation or transfer_confirmed_at is null)
);
create unique index one_current_assignment on request_assignments (request_id)
  where ended_at is null;
create index assignment_technician_idx on request_assignments (technician_id, assigned_at);

create table repair_results (
  id TEXT PRIMARY KEY NOT NULL,
  request_id INTEGER not null references repair_requests(id) on delete restrict,
  assignment_id TEXT not null references request_assignments(id) on delete restrict,
  submitted_by TEXT not null references profiles(id) on delete restrict,
  content text not null check (length(trim(content)) > 0),
  submitted_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  unique (id, request_id)
);
create index result_request_idx on repair_results (request_id, submitted_at);

create table request_feedback (
  id TEXT PRIMARY KEY NOT NULL,
  request_id INTEGER not null references repair_requests(id) on delete restrict,
  kind text not null check (kind in ('rework', 'reopen')),
  reason text not null check (length(trim(reason)) > 0),
  submitted_by TEXT not null references profiles(id) on delete restrict,
  created_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  unique (id, request_id)
);
create index feedback_request_idx on request_feedback (request_id, created_at);

create table request_attachments (
  id TEXT PRIMARY KEY NOT NULL,
  request_id INTEGER not null references repair_requests(id) on delete restrict,
  result_id TEXT,
  feedback_id TEXT,
  storage_path text not null unique check (length(trim(storage_path)) > 0),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes INTEGER not null check (size_bytes > 0 and size_bytes <= 5242880),
  uploaded_by TEXT not null references profiles(id) on delete restrict,
  created_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  check ((result_id IS NOT NULL) + (feedback_id IS NOT NULL) <= 1),
  foreign key (result_id, request_id) references repair_results(id, request_id) on delete restrict,
  foreign key (feedback_id, request_id) references request_feedback(id, request_id) on delete restrict
);
create index attachment_request_idx on request_attachments (request_id);

create table request_history (
  id TEXT PRIMARY KEY NOT NULL,
  request_id INTEGER references repair_requests(id) on delete restrict,
  
  entity_type text not null check (entity_type in ('request', 'profile', 'room', 'category')),
  entity_id TEXT not null,
  action text not null check (length(trim(action)) > 0),
  actor_id TEXT not null references profiles(id) on delete restrict,
  old_status text,
  new_status text,
  note text,
  occurred_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  check ((entity_type = 'request' and request_id = entity_id and request_id is not null)
         or (entity_type <> 'request' and request_id is null))
);
create index history_request_idx on request_history (request_id, occurred_at);
create index history_entity_idx on request_history (entity_type, entity_id, occurred_at);

create table notifications (
  id TEXT PRIMARY KEY NOT NULL,
  recipient_id TEXT not null references profiles(id) on delete restrict,
  request_id INTEGER not null references repair_requests(id) on delete restrict,
  event_type text not null check (event_type in
    ('assigned', 'transferred_in', 'transferred_out', 'cancelled', 'rejected',
     'repair_reported', 'rework_requested', 'completed')),
  
  message text not null,
  created_at TEXT not null DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  read_at TEXT
);
create index notification_recipient_idx on notifications (recipient_id, created_at);


CREATE TRIGGER request_code_after_insert AFTER INSERT ON repair_requests
BEGIN
  UPDATE repair_requests SET request_code = 'DF' || printf('%06d', NEW.id) WHERE id = NEW.id;
END;
CREATE TRIGGER profile_identity_immutable BEFORE UPDATE OF email, identity_code, role ON profiles
WHEN NEW.email <> OLD.email OR NEW.identity_code <> OLD.identity_code OR NEW.role <> OLD.role
BEGIN
  SELECT RAISE(ABORT, 'Identity, email and role are immutable');
END;
