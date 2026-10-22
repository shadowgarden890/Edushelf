-- =====================================================================
-- Changes to match the system flowcharts.
--
--  * Accounts are created by the admin only: the public "request an
--    account" function is removed (forgot-password requests stay).
--  * Syllabus permission requests carry the student's academic
--    information, and the admin can ask for a revision.
--  * Rejected materials keep the admin's revision notes.
--
-- Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. No more account requests from the login screen.
-- ---------------------------------------------------------------------
drop function if exists public.request_account(text, text, text, text);
drop function if exists public.admin_approve_account_request(uuid, text);
drop function if exists public.admin_reject_account_request(uuid, text);

-- ---------------------------------------------------------------------
-- 2. Permission requests: academic information + revision loop.
--    status: pending -> approved | denied | revision -> (resubmit) pending
-- ---------------------------------------------------------------------
alter table public.permissions
  add column if not exists year_level      text,
  add column if not exists section         text,
  add column if not exists subject_code    text,
  add column if not exists instructor_name text,
  add column if not exists reason          text,
  add column if not exists admin_note      text,
  add column if not exists updated_at      timestamptz default now();

-- Allow the new 'revision' status (replaces any earlier status check).
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.permissions'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.permissions drop constraint %I',
                   c.conname);
  end loop;
end;
$$;

alter table public.permissions
  add constraint permissions_status_check
  check (status in ('pending', 'approved', 'denied', 'revision'));

-- ---------------------------------------------------------------------
-- 3. Materials: the admin's notes when sending a material back.
-- ---------------------------------------------------------------------
alter table public.materials
  add column if not exists revision_notes text;
