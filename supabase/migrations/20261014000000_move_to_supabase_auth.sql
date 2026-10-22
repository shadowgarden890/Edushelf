-- =====================================================================
-- Move Edushelf login from the plaintext `users.password` column to
-- Supabase Auth.
--
-- BEFORE RUNNING:
--   1. Back up the `users` table (Table Editor -> Export to CSV).
--   2. Dashboard -> Authentication -> Sign In / Providers -> Email:
--      turn OFF "Confirm email". Login IDs map to internal addresses
--      (<id>@edushelf.app) that have no real mailbox.
--
-- Run steps 1-5 in the SQL editor, test logging in with an existing
-- account in the app, then run step 6.
--
-- The email domain below must match AuthService.authEmailDomain.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Link profiles to auth users
-- ---------------------------------------------------------------------
alter table public.users
  add column if not exists auth_id uuid unique
    references auth.users (id) on delete cascade;

alter table public.users alter column password drop not null;

-- Fails if two rows already share an id_number; clean those up first.
create unique index if not exists users_id_number_key
  on public.users (id_number);

-- ---------------------------------------------------------------------
-- 2. Create a profile row whenever someone signs up.
--    Role/department come from the ID number server-side (mirrors
--    UserSession.parseId) so clients can't pick their own role.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    text := upper(trim(coalesce(new.raw_user_meta_data ->> 'id_number', '')));
  v_name  text := trim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  v_parts text[] := string_to_array(v_id, '-');
  v_role  text;
  v_dept  text;
begin
  -- Step 3 links existing profiles itself.
  if current_setting('edushelf.migrating', true) = 'on' then
    return new;
  end if;

  if array_length(v_parts, 1) = 2 and v_parts[1] = 'ADMIN' then
    v_role := 'admin';
    v_dept := 'ALL';
  elsif array_length(v_parts, 1) = 3 then
    v_dept := case v_parts[1]
      when 'IT' then 'BSIT'
      when 'BA' then 'BSBA'
      when 'AC' then 'BSA'
      when 'OA' then 'BSOA'
    end;
    if v_dept is not null then
      if v_parts[2] = 'T' then
        v_role := 'instructor';
      elsif v_parts[2] ~ '^[0-9]{2}$' then
        v_role := 'student';
      end if;
    end if;
  end if;

  if v_role is null then
    raise exception 'Invalid ID format: %', v_id;
  end if;

  if exists (select 1 from public.users where id_number = v_id) then
    raise exception 'ID already registered: %', v_id;
  end if;

  insert into public.users (auth_id, id_number, full_name, role, department)
  values (new.id, v_id, v_name, v_role, v_dept);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Deleting a profile (admin dashboard) also deletes the login.
create or replace function public.handle_deleted_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.auth_id is not null then
    delete from auth.users where id = old.auth_id;
  end if;
  return old;
end;
$$;

drop trigger if exists on_profile_deleted on public.users;
create trigger on_profile_deleted
  after delete on public.users
  for each row execute function public.handle_deleted_profile();

-- ---------------------------------------------------------------------
-- 3. Move existing accounts into Supabase Auth (passwords get bcrypt-
--    hashed; users keep logging in with the same ID and password).
-- ---------------------------------------------------------------------
do $$
declare
  r       record;
  v_uid   uuid;
  v_email text;
begin
  perform set_config('edushelf.migrating', 'on', true);

  for r in
    select * from public.users
    where auth_id is null and password is not null
  loop
    v_email := lower(trim(r.id_number)) || '@edushelf.app';

    select id into v_uid from auth.users where email = v_email;

    if v_uid is null then
      v_uid := gen_random_uuid();

      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
      ) values (
        '00000000-0000-0000-0000-000000000000', v_uid,
        'authenticated', 'authenticated', v_email,
        extensions.crypt(trim(r.password), extensions.gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('id_number', r.id_number, 'full_name', r.full_name),
        now(), now(),
        '', '', '', ''
      );

      insert into auth.identities (
        id, user_id, provider_id, identity_data, provider,
        last_sign_in_at, created_at, updated_at
      ) values (
        gen_random_uuid(), v_uid, v_uid::text,
        jsonb_build_object('sub', v_uid::text, 'email', v_email,
                           'email_verified', true),
        'email', now(), now(), now()
      );
    end if;

    update public.users set auth_id = v_uid where id = r.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Row Level Security on users
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users
    where auth_id = auth.uid() and role = 'admin'
  );
$$;

alter table public.users enable row level security;

-- Remove any earlier (likely anon-wide) policies on this table.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'users'
  loop
    execute format('drop policy %I on public.users', p.policyname);
  end loop;
end;
$$;

create policy "Signed-in users can read profiles"
  on public.users for select
  to authenticated
  using (true);

create policy "Admins can delete profiles"
  on public.users for delete
  to authenticated
  using (public.is_admin());

-- No insert/update policies: rows are created by the signup trigger.

-- ---------------------------------------------------------------------
-- 5. Check: every row should now have auth_id set.
-- ---------------------------------------------------------------------
select id_number, auth_id is not null as migrated
from public.users
order by migrated, id_number;

-- ---------------------------------------------------------------------
-- 6. AFTER confirming logins work in the app, delete the plaintext
--    passwords for good:
-- ---------------------------------------------------------------------
-- alter table public.users drop column password;
