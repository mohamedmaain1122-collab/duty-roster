-- Run once in Supabase: SQL Editor > New query > paste > Run
-- NOTE: this REPLACES the earlier version's tables (staff, shifts, assignments, etc.).

drop table if exists allocations, leaves, slots, staff, rosters, settings, assignments, shifts cascade;

create table if not exists profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  is_admin boolean not null default false
);

-- First person to sign up becomes admin; everyone after is view-only
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, is_admin) values (new.id, new.email, not exists (select 1 from profiles));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create or replace function is_admin() returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;

create table rosters (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort int not null default 0
);

create table staff (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  role text,                                   -- optional title, e.g. Manager (used when a row requires a role)
  roster_id uuid references rosters on delete set null,   -- change this to move someone to another roster
  email text,                                  -- links a login to this person for "My shifts"
  active boolean not null default true
);

-- One row of the board (e.g. one of the four "Main Reception" rows)
create table slots (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null references rosters on delete cascade,
  section text not null,                       -- heading, e.g. Day shift
  kind text not null check (kind in ('day','evening','night','cover','off')),
  station text not null,                       -- e.g. Main Reception
  start_time time,
  end_time time,
  role text,                                   -- optional: only staff with this role can be auto-filled here
  sort int not null default 0
);

create table allocations (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null references rosters on delete cascade,
  slot_id uuid not null references slots on delete cascade,
  staff_id uuid not null references staff on delete cascade,
  day date not null,
  unique (slot_id, day)
);
create index on allocations (roster_id, day);
create index on allocations (staff_id, day);

create table leaves (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff on delete cascade,
  day date not null,
  note text,
  unique (staff_id, day)
);

create table settings (
  id int primary key default 1 check (id = 1),
  max_consec int not null default 5,
  min_rest int not null default 11
);
insert into settings (id) values (1);

-- Security: everyone signed in can read, only admins can change
alter table profiles enable row level security;
drop policy if exists "own or admin read" on profiles;
drop policy if exists "admin update" on profiles;
create policy "own or admin read" on profiles for select using (id = auth.uid() or is_admin());
create policy "admin update" on profiles for update using (is_admin());

do $$ declare t text; begin
  foreach t in array array['rosters','staff','slots','allocations','leaves','settings'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy "read" on %I for select to authenticated using (true)', t);
    execute format('create policy "admin write" on %I for all to authenticated using (is_admin()) with check (is_admin())', t);
  end loop;
end $$;

-- ===== Seed: your two rosters, copied from OPD_Duty_Roster.pdf =====
create function _add(r uuid, sec text, k text, st text, s time, e time, n int default 1) returns void language plpgsql as $$
declare i int;
begin
  for i in 1..n loop
    insert into slots (roster_id, section, kind, station, start_time, end_time, sort)
    values (r, sec, k, st, s, e, (select coalesce(max(sort), 0) + 1 from slots where roster_id = r));
  end loop;
end $$;

do $$
declare h uuid; c uuid; i int;
begin
  insert into rosters (name, sort) values ('Health Care Administration', 1) returning id into h;
  insert into rosters (name, sort) values ('Clinical Assistant', 2) returning id into c;

  -- Health Care Administration
  perform _add(h,'Day shift','day','Floor Manager','08:00','16:00');
  perform _add(h,'Day shift','day','Reception Manager','08:00','16:00');
  perform _add(h,'Day shift','day','Room Manager','08:00','16:00');
  perform _add(h,'Day shift','day','Main Reception','07:30','15:30',4);
  perform _add(h,'Day shift','day','Er reception','07:30','15:30',2);
  perform _add(h,'Day shift','day','Lab Reception','07:30','15:30');
  perform _add(h,'Scheduled calls & covering duties','cover','ER & Lab Break Covering','12:00','12:45');
  perform _add(h,'Scheduled calls & covering duties','cover','ER & Lab Break Covering','12:45','13:30');
  perform _add(h,'Scheduled calls & covering duties','cover','Reception Call Duty','15:30','18:00');
  perform _add(h,'Scheduled calls & covering duties','cover','Reception Call Duty','18:00','20:30');
  perform _add(h,'Scheduled calls & covering duties','cover','Reception Call Duty','20:30','23:00');
  perform _add(h,'Evening shift','evening','Floor Manager','08:00','16:00');
  perform _add(h,'Evening shift','evening','Floor Assistant','08:00','16:00');
  perform _add(h,'Evening shift','evening','Main Reception','07:30','15:30',3);
  perform _add(h,'Evening shift','evening','Er reception','07:30','15:30',2);
  perform _add(h,'Evening shift','cover','ER Break Covering','19:00','19:45');
  perform _add(h,'Night shift','night','ER Reception','23:30','07:30',2);
  perform _add(h,'Night shift','night','On Call CRO','23:30','08:00');
  perform _add(h,'Staff on leave & off','off','Staff on leave & off',null,null,5);

  -- Clinical Assistant
  for i in 1..14 loop
    if i <> 6 then perform _add(c,'Day shift','day','Consultation Room '||i,'08:00','16:00'); end if;
  end loop;
  perform _add(c,'Day shift','day','Scan Room','08:00','16:00');
  perform _add(c,'Day shift','day','ENT Room','08:00','16:00');
  perform _add(c,'Day shift','day','Dental Consultation','08:00','16:00');
  perform _add(c,'Day shift','day','Dental Procedure 1','08:00','16:00');
  perform _add(c,'Day shift','day','Dental Procedure 2','08:00','16:00');
  perform _add(c,'Scheduled calls & covering duties','cover','Schedule call 1','16:00','18:00');
  perform _add(c,'Scheduled calls & covering duties','cover','Schedule call 1','18:00','19:00');
  perform _add(c,'Scheduled calls & covering duties','cover','Schedule call 1','20:00','22:00');
  perform _add(c,'Scheduled calls & covering duties','cover','Schedule call 2','16:00','18:00');
  perform _add(c,'Scheduled calls & covering duties','cover','Schedule call 2','18:00','19:00');
  perform _add(c,'Scheduled calls & covering duties','cover','Schedule call 2','20:00','22:00');
  for i in 1..14 loop
    if i <> 6 then perform _add(c,'Evening shift','evening','Consultation Room '||i,'16:00','22:00'); end if;
  end loop;
  perform _add(c,'Evening shift','evening','Scan Room','16:00','22:00');
  perform _add(c,'Evening shift','evening','ENT Room','16:00','22:00');
  perform _add(c,'Evening shift','cover','General Break Covering','19:00','20:00');
  perform _add(c,'Staff on leave & off','off','Staff on leave & off',null,null,4);
end $$;

drop function _add(uuid, text, text, text, time, time, int);
