-- =====================================================================
-- Row Level Security for materials, notifications, permissions and
-- activity_logs. Before this, anyone holding the app's publishable key
-- (which ships inside the APK) could read - and possibly change - these
-- tables without logging in. Now every row is checked against who is
-- signed in and their role.
--
-- Safe to re-run. Earlier policies on these tables are replaced.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers: who is signed in (security definer, so they work inside
-- policies without extra permissions).
-- ---------------------------------------------------------------------
create or replace function public.current_id_number()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select id_number from public.users where auth_id = auth.uid();
$$;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.users where auth_id = auth.uid();
$$;

create or replace function public.current_department()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select department from public.users where auth_id = auth.uid();
$$;

revoke all on function public.current_id_number() from public, anon;
revoke all on function public.current_user_role() from public, anon;
revoke all on function public.current_department() from public, anon;
grant execute on function public.current_id_number() to authenticated;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.current_department() to authenticated;

-- Remove whatever policies these tables had before (likely "allow all").
do $$
declare p record;
begin
  for p in
    select tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('materials', 'notifications', 'permissions',
                        'activity_logs')
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end;
$$;

alter table public.materials     enable row level security;
alter table public.notifications enable row level security;
alter table public.permissions   enable row level security;
alter table public.activity_logs enable row level security;

-- Nothing for signed-out visitors on these tables.
revoke all on public.materials, public.notifications, public.permissions,
              public.activity_logs from anon;

-- ---------------------------------------------------------------------
-- MATERIALS
-- Students and faculty see approved materials; faculty also see their
-- own uploads (any status); admins see and manage everything.
-- ---------------------------------------------------------------------
create policy "Read approved, own uploads, or everything as admin"
  on public.materials for select to authenticated
  using (
    status = 'approved'
    or uploaded_by = public.current_id_number()
    or public.is_admin()
  );

create policy "Faculty upload their own materials for review"
  on public.materials for insert to authenticated
  with check (
    public.is_admin()
    or (public.current_user_role() = 'instructor'
        and uploaded_by = public.current_id_number()
        and status = 'pending')
  );

create policy "Only admins approve or revise materials"
  on public.materials for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Only admins delete materials"
  on public.materials for delete to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- NOTIFICATIONS
-- You see and mark your own; you can only send in your own name.
-- (Server functions, e.g. forgot-password alerts, bypass this safely.)
-- ---------------------------------------------------------------------
create policy "Read your own notifications"
  on public.notifications for select to authenticated
  using (recipient_id = public.current_id_number());

create policy "Send notifications only as yourself"
  on public.notifications for insert to authenticated
  with check (sender_id = public.current_id_number());

create policy "Mark your own notifications as read"
  on public.notifications for update to authenticated
  using (recipient_id = public.current_id_number())
  with check (recipient_id = public.current_id_number());

create policy "Delete your own notifications"
  on public.notifications for delete to authenticated
  using (recipient_id = public.current_id_number());

-- ---------------------------------------------------------------------
-- PERMISSIONS (syllabus access requests)
-- Students see and (re)submit only their own requests and can never
-- approve themselves; admins see and decide everything.
-- ---------------------------------------------------------------------
create policy "Students read their own requests; admins read all"
  on public.permissions for select to authenticated
  using (student_id = public.current_id_number() or public.is_admin());

create policy "Students request access for themselves"
  on public.permissions for insert to authenticated
  with check (student_id = public.current_id_number()
              and status = 'pending');

create policy "Students can only resubmit (back to pending)"
  on public.permissions for update to authenticated
  using (student_id = public.current_id_number())
  with check (student_id = public.current_id_number()
              and status = 'pending');

create policy "Admins approve, deny or ask for revision"
  on public.permissions for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Only admins delete requests"
  on public.permissions for delete to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- ACTIVITY LOGS (reading activity)
-- Students log and see only their own; faculty see their department;
-- admins see all. Nobody edits or deletes history.
-- ---------------------------------------------------------------------
create policy "Read own, department (faculty) or all (admin)"
  on public.activity_logs for select to authenticated
  using (
    student_id = public.current_id_number()
    or public.is_admin()
    or (public.current_user_role() = 'instructor'
        and department = public.current_department())
  );

create policy "Log your own activity"
  on public.activity_logs for insert to authenticated
  with check (student_id = public.current_id_number());

-- ---------------------------------------------------------------------
-- Check: run as a signed-out visitor these now return nothing.
-- ---------------------------------------------------------------------
select tablename, count(*) as policies
from pg_policies
where schemaname = 'public'
  and tablename in ('materials', 'notifications', 'permissions',
                    'activity_logs')
group by tablename
order by tablename;
