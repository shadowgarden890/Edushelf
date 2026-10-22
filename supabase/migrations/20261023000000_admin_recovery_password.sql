-- =====================================================================
-- Admin recovery password ("master key").
--
-- An admin's FIRST password is their permanent recovery password. If an
-- admin forgets their current password, they simply log in with the
-- recovery password - no request to another admin. It never expires and
-- is never one-time.
--
-- Requires 20261022000000_follow_flowcharts.sql. Safe to re-run.
-- =====================================================================

-- bcrypt hashes of each admin's recovery password. No policies: nobody
-- can read this table from the app.
create table if not exists public.admin_recovery_keys (
  auth_id    uuid primary key references auth.users (id) on delete cascade,
  key_hash   text not null,
  created_at timestamptz not null default now()
);
alter table public.admin_recovery_keys enable row level security;

-- Existing admins: the password they have now becomes their recovery
-- password (already bcrypt-hashed by Supabase Auth).
insert into public.admin_recovery_keys (auth_id, key_hash)
select u.auth_id, a.encrypted_password
from public.users u
join auth.users a on a.id = u.auth_id
where u.role = 'admin' and coalesce(a.encrypted_password, '') <> ''
on conflict (auth_id) do nothing;

-- An admin's first password is permanent, so they're never forced to
-- replace it.
update public.users set must_change_password = false where role = 'admin';

-- ---------------------------------------------------------------------
-- Account creation: admin accounts keep their first password as the
-- recovery password; students and faculty still get a temporary one.
-- ---------------------------------------------------------------------
create or replace function public.admin_create_user(
  p_id_number text,
  p_full_name text,
  p_password  text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := trim(coalesce(p_full_name, ''));
  v_uid  uuid;
begin
  if not public.is_admin() then
    raise exception 'Only admins can create accounts' using errcode = '42501';
  end if;
  if v_name = '' then raise exception 'Full name is required'; end if;
  if length(v_name) > 120 then raise exception 'Full name is too long'; end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;

  v_uid := public._edushelf_create_login(
    p_id_number, v_name,
    extensions.crypt(p_password, extensions.gen_salt('bf')));

  if public._edushelf_id_role(p_id_number) = 'admin' then
    insert into public.admin_recovery_keys (auth_id, key_hash)
    values (v_uid, extensions.crypt(p_password, extensions.gen_salt('bf')))
    on conflict (auth_id) do update set key_hash = excluded.key_hash;
  else
    update public.users set must_change_password = true where auth_id = v_uid;
  end if;

  return v_uid;
end;
$$;

-- ---------------------------------------------------------------------
-- Public (login screen): if p_password is the admin's recovery password,
-- it becomes their current password again and the app signs them in.
-- Returns true only for an admin ID with the correct recovery password.
-- Rate-limited against guessing: 5 tries per network per 15 minutes.
-- ---------------------------------------------------------------------
create or replace function public.admin_recover_login(
  p_id_number text,
  p_password  text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   text := upper(trim(coalesce(p_id_number, '')));
  v_auth uuid;
  v_hash text;
begin
  if public._edushelf_id_role(v_id) is distinct from 'admin'
     or coalesce(p_password, '') = '' then
    return false;
  end if;

  if public._edushelf_rate_limited('admin_recovery', 5, 50) then
    return false;
  end if;

  select u.auth_id, k.key_hash into v_auth, v_hash
  from public.users u
  join public.admin_recovery_keys k on k.auth_id = u.auth_id
  where u.id_number = v_id;

  if v_hash is null
     or v_hash <> extensions.crypt(p_password, v_hash) then
    return false;
  end if;

  -- The master key opens the padlock: log in with it again.
  update auth.users set encrypted_password = v_hash, updated_at = now()
  where id = v_auth;
  update public.users set must_change_password = false where auth_id = v_auth;
  return true;
end;
$$;

-- ---------------------------------------------------------------------
-- Forgot-password requests are for students and faculty only. Admins use
-- their recovery password instead, so their requests are ignored (with
-- the same reply as always, revealing nothing).
-- ---------------------------------------------------------------------
create or replace function public.request_password_reset(
  p_id_number text,
  p_full_name text,
  p_note      text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     text := upper(trim(coalesce(p_id_number, '')));
  v_name   text := lower(regexp_replace(trim(coalesce(p_full_name, '')),
                                        '\s+', ' ', 'g'));
  v_note   text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_user   record;
  v_req_id uuid;
begin
  if v_id = '' or v_name = '' or length(v_id) > 30
     or length(v_name) > 120 then
    return 'submitted';
  end if;
  if public._edushelf_id_role(v_id) = 'admin' then
    return 'submitted';
  end if;

  if public._edushelf_rate_limited('reset', 5, 200) then
    return 'rate_limited';
  end if;

  select auth_id, id_number, full_name into v_user
  from public.users
  where id_number = v_id
    and lower(regexp_replace(trim(full_name), '\s+', ' ', 'g')) = v_name
    and auth_id is not null;
  if not found then
    return 'submitted';
  end if;

  perform pg_advisory_xact_lock(hashtext('edushelf-reset:' || v_user.auth_id));

  select id into v_req_id
  from public.password_reset_requests
  where user_auth_id = v_user.auth_id and status = 'pending'
  order by created_at
  limit 1;

  if found then
    update public.password_reset_requests
    set request_count = request_count + 1,
        last_requested_at = now(),
        note = coalesce(v_note, note)
    where id = v_req_id
      and last_requested_at < now() - interval '5 minutes';
    return 'submitted';
  end if;

  insert into public.password_reset_requests
    (user_auth_id, id_number, full_name, note, contact)
  values (
    v_user.auth_id, v_user.id_number, v_user.full_name, v_note,
    (select contact from public.user_contacts where auth_id = v_user.auth_id)
  );

  return 'submitted';
end;
$$;

-- ---------------------------------------------------------------------
-- PERMISSIONS
-- ---------------------------------------------------------------------
revoke all on function public.admin_recover_login(text, text) from public;
grant execute on function public.admin_recover_login(text, text)
  to anon, authenticated;
