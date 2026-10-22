-- =====================================================================
-- Request-based accounts and password resets.
--
--  * Users REQUEST an account from the login screen and choose their own
--    password. The admin checks the request against school records and
--    approves it - no login details have to be sent to anyone.
--  * "Forgot password" works the same way: the user picks the new
--    password, the admin approves.
--  * Admins can still create accounts / import a CSV; those get a
--    temporary password that must be changed on first login.
--
-- Requires 20261019000000_admin_managed_accounts.sql. Safe to re-run.
-- The email domain below must match AuthService.authEmailDomain.
-- =====================================================================

-- =====================================================================
-- SHARED HELPERS (internal; not callable from the app)
-- =====================================================================

alter table public.users
  add column if not exists must_change_password boolean not null default false;

-- Role for an ID number, or null if the format is invalid
-- (same rules as UserSession.parseId and handle_new_auth_user).
create or replace function public._edushelf_id_role(p_id text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(upper(trim(coalesce(p_id, ''))), '-');
begin
  if array_length(v_parts, 1) = 2 and v_parts[1] = 'ADMIN' then
    return 'admin';
  end if;
  if array_length(v_parts, 1) = 3
     and v_parts[1] in ('IT', 'BA', 'AC', 'OA') then
    if v_parts[2] = 'T' then return 'instructor'; end if;
    if v_parts[2] ~ '^[0-9]{2}$' then return 'student'; end if;
  end if;
  return null;
end;
$$;

-- Creates the login (auth user + identity). The handle_new_auth_user
-- trigger validates the ID and creates the profile row.
create or replace function public._edushelf_create_login(
  p_id_number          text,
  p_full_name          text,
  p_encrypted_password text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    text := upper(trim(p_id_number));
  v_email text := lower(v_id) || '@edushelf.app';
  v_uid   uuid := gen_random_uuid();
begin
  if exists (select 1 from auth.users where email = v_email)
     or exists (select 1 from public.users where id_number = v_id) then
    raise exception 'ID already registered: %', v_id;
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_uid,
    'authenticated', 'authenticated', v_email,
    p_encrypted_password,
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('id_number', v_id, 'full_name', trim(p_full_name)),
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
    'email', null, now(), now()
  );

  return v_uid;
end;
$$;

-- Every public request (valid or not), only for rate limiting.
create table if not exists public.request_attempts (
  id         bigint generated always as identity primary key,
  kind       text not null,
  client_ip  text not null,
  created_at timestamptz not null default now()
);
create index if not exists request_attempts_kind_ip_time
  on public.request_attempts (kind, client_ip, created_at);
create index if not exists request_attempts_time
  on public.request_attempts (created_at);
alter table public.request_attempts enable row level security;

-- True when the caller is over a limit; otherwise records the attempt.
-- Limits: p_per_ip attempts per network per 15 minutes, and p_global
-- attempts per 10 minutes for the whole school.
create or replace function public._edushelf_rate_limited(
  p_kind   text,
  p_per_ip integer,
  p_global integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ip text := coalesce(nullif(trim(split_part(
    current_setting('request.headers', true)::json ->> 'x-forwarded-for',
    ',', 1)), ''), 'unknown');
begin
  delete from public.request_attempts
  where created_at < now() - interval '1 day';

  if (select count(*) from public.request_attempts
      where kind = p_kind and client_ip = v_ip
        and created_at > now() - interval '15 minutes') >= p_per_ip
     or (select count(*) from public.request_attempts
         where kind = p_kind
           and created_at > now() - interval '10 minutes') >= p_global then
    return true;
  end if;

  insert into public.request_attempts (kind, client_ip) values (p_kind, v_ip);
  return false;
end;
$$;

-- Passwords chosen in requests, bcrypt-hashed. No policies: nobody can
-- read this table from the app, not even admins.
create table if not exists public.request_passwords (
  request_id    uuid primary key,
  password_hash text not null
);
alter table public.request_passwords enable row level security;

-- =====================================================================
-- ADMIN-CREATED ACCOUNTS (temporary password, must change on login)
-- =====================================================================
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

  update public.users set must_change_password = true where auth_id = v_uid;
  return v_uid;
end;
$$;

create or replace function public.admin_update_user(
  p_auth_id      uuid,
  p_full_name    text,
  p_new_password text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := trim(coalesce(p_full_name, ''));
begin
  if not public.is_admin() then
    raise exception 'Only admins can edit accounts' using errcode = '42501';
  end if;
  if v_name = '' then raise exception 'Full name is required'; end if;
  if not exists (select 1 from public.users where auth_id = p_auth_id) then
    raise exception 'Account not found';
  end if;

  update public.users set full_name = v_name where auth_id = p_auth_id;
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
                           || jsonb_build_object('full_name', v_name),
      updated_at = now()
  where id = p_auth_id;

  if p_new_password is not null then
    if length(p_new_password) < 6 then
      raise exception 'Password must be at least 6 characters';
    end if;
    update auth.users
    set encrypted_password =
          extensions.crypt(p_new_password, extensions.gen_salt('bf')),
        updated_at = now()
    where id = p_auth_id;
    update public.users set must_change_password = true
    where auth_id = p_auth_id;
  end if;
end;
$$;

-- Called by the app right after the user sets their own password.
create or replace function public.complete_password_change()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.users set must_change_password = false
  where auth_id = auth.uid();
$$;

-- Bulk creation: [{"id_number","full_name","password"}], max 100 per call.
-- Returns one result per row; a bad row doesn't stop the others.
create or replace function public.admin_create_users_bulk(p_users jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r       jsonb;
  results jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only admins can create accounts' using errcode = '42501';
  end if;
  if jsonb_typeof(p_users) <> 'array' then
    raise exception 'Expected a list of accounts';
  end if;
  if jsonb_array_length(p_users) > 100 then
    raise exception 'At most 100 accounts per batch';
  end if;

  for r in select * from jsonb_array_elements(p_users)
  loop
    begin
      perform public.admin_create_user(
        r ->> 'id_number', r ->> 'full_name', r ->> 'password');
      results := results || jsonb_build_object(
        'id_number', upper(trim(r ->> 'id_number')), 'ok', true);
    exception when others then
      results := results || jsonb_build_object(
        'id_number', upper(trim(coalesce(r ->> 'id_number', ''))),
        'ok', false, 'error', sqlerrm);
    end;
  end loop;
  return results;
end;
$$;

-- =====================================================================
-- ACCOUNT REQUESTS
-- =====================================================================
create table if not exists public.account_requests (
  id                uuid primary key default gen_random_uuid(),
  id_number         text not null,
  full_name         text not null,
  role              text not null,
  contact           text,
  note              text,
  status            text not null default 'pending'
                      check (status in ('pending', 'approved', 'rejected')),
  reject_reason     text,
  request_count     integer not null default 1,
  created_at        timestamptz not null default now(),
  last_requested_at timestamptz not null default now(),
  resolved_at       timestamptz,
  resolved_by       uuid references auth.users (id) on delete set null
);
create index if not exists account_requests_status_created
  on public.account_requests (status, created_at);
create index if not exists account_requests_id_status
  on public.account_requests (id_number, status);

-- =====================================================================
-- PASSWORD RESET REQUESTS
-- =====================================================================
create table if not exists public.password_reset_requests (
  id                uuid primary key default gen_random_uuid(),
  user_auth_id      uuid not null references auth.users (id) on delete cascade,
  id_number         text not null,
  full_name         text not null,
  note              text,
  status            text not null default 'pending'
                      check (status in ('pending', 'resolved', 'dismissed')),
  request_count     integer not null default 1,
  created_at        timestamptz not null default now(),
  last_requested_at timestamptz not null default now(),
  resolved_at       timestamptz,
  resolved_by       uuid references auth.users (id) on delete set null
);
create index if not exists password_reset_requests_status_created
  on public.password_reset_requests (status, created_at);
create index if not exists password_reset_requests_user_status
  on public.password_reset_requests (user_auth_id, status);

-- Admins can read requests (never the passwords); all writes go through
-- the functions below.
alter table public.account_requests enable row level security;
alter table public.password_reset_requests enable row level security;

drop policy if exists "Admins can read account requests"
  on public.account_requests;
create policy "Admins can read account requests"
  on public.account_requests for select
  to authenticated using (public.is_admin());

drop policy if exists "Admins can read reset requests"
  on public.password_reset_requests;
create policy "Admins can read reset requests"
  on public.password_reset_requests for select
  to authenticated using (public.is_admin());

-- Live updates for the admin's request lists.
do $$
declare t text;
begin
  foreach t in array array['account_requests', 'password_reset_requests']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = t
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- =====================================================================
-- PUBLIC FUNCTIONS (login screen, not signed in)
-- =====================================================================

-- Request a student or faculty account. Returns 'submitted', 'invalid_id',
-- 'invalid_password', 'invalid' or 'rate_limited'.
-- Never reveals whether the ID already has an account.
create or replace function public.request_account(
  p_id_number text,
  p_full_name text,
  p_password  text,
  p_contact   text default null,
  p_note      text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      text := upper(trim(coalesce(p_id_number, '')));
  v_name    text := regexp_replace(trim(coalesce(p_full_name, '')),
                                   '\s+', ' ', 'g');
  v_role    text := public._edushelf_id_role(p_id_number);
  v_contact text := nullif(left(trim(coalesce(p_contact, '')), 100), '');
  v_note    text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_req     record;
  v_new_id  uuid;
begin
  -- Admin accounts are only created by admins.
  if v_role is null or v_role = 'admin' or length(v_id) > 30 then
    return 'invalid_id';
  end if;
  if v_name = '' or length(v_name) > 120 then return 'invalid'; end if;
  -- bcrypt only uses the first 72 bytes.
  if length(coalesce(p_password, '')) < 6
     or octet_length(p_password) > 72 then
    return 'invalid_password';
  end if;

  if public._edushelf_rate_limited('account', 5, 200) then
    return 'rate_limited';
  end if;

  -- Housekeeping: passwords of closed requests are kept 30 days (so the
  -- login screen can say "not approved"), then deleted.
  delete from public.request_passwords p
  using public.account_requests r
  where p.request_id = r.id and r.status <> 'pending'
    and r.resolved_at < now() - interval '30 days';

  -- Requests for the same ID are handled one at a time.
  perform pg_advisory_xact_lock(hashtext('edushelf-account:' || v_id));

  if exists (select 1 from public.users where id_number = v_id) then
    return 'submitted';
  end if;

  -- Same person sending again (same password): merge into their request.
  select r.id, r.last_requested_at into v_req
  from public.account_requests r
  join public.request_passwords p on p.request_id = r.id
  where r.id_number = v_id and r.status = 'pending'
    and p.password_hash = extensions.crypt(p_password, p.password_hash)
  limit 1;

  if found then
    update public.account_requests
    set request_count = request_count + 1,
        last_requested_at = now(),
        full_name = v_name,
        contact = coalesce(v_contact, contact),
        note = coalesce(v_note, note)
    where id = v_req.id
      and last_requested_at < now() - interval '5 minutes';
    return 'submitted';
  end if;

  -- Different requests for one ID are kept apart (so nobody can replace
  -- someone else's request) and capped at 3 for the admin to compare.
  if (select count(*) from public.account_requests
      where id_number = v_id and status = 'pending') >= 3 then
    return 'submitted';
  end if;

  insert into public.account_requests
    (id_number, full_name, role, contact, note)
  values (v_id, v_name, v_role, v_contact, v_note)
  returning id into v_new_id;

  insert into public.request_passwords (request_id, password_hash)
  values (v_new_id, extensions.crypt(p_password, extensions.gen_salt('bf')));

  return 'submitted';
end;
$$;

-- Forgot password: the user chooses the new password. Returns
-- 'submitted', 'invalid_password', or 'rate_limited'. Never reveals
-- whether the ID exists.
create or replace function public.request_password_reset(
  p_id_number    text,
  p_full_name    text,
  p_new_password text,
  p_note         text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   text := upper(trim(coalesce(p_id_number, '')));
  v_name text := lower(regexp_replace(trim(coalesce(p_full_name, '')),
                                      '\s+', ' ', 'g'));
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_user record;
  v_req  record;
  v_new_id uuid;
begin
  if length(coalesce(p_new_password, '')) < 6
     or octet_length(p_new_password) > 72 then
    return 'invalid_password';
  end if;
  if v_id = '' or v_name = '' or length(v_id) > 30
     or length(v_name) > 120 then
    return 'submitted';
  end if;

  if public._edushelf_rate_limited('reset', 5, 200) then
    return 'rate_limited';
  end if;

  -- Name must match too, so knowing someone's ID isn't enough.
  select auth_id, id_number, full_name into v_user
  from public.users
  where id_number = v_id
    and lower(regexp_replace(trim(full_name), '\s+', ' ', 'g')) = v_name
    and auth_id is not null;
  if not found then
    return 'submitted';
  end if;

  perform pg_advisory_xact_lock(hashtext('edushelf-reset:' || v_user.auth_id));

  select r.id into v_req
  from public.password_reset_requests r
  join public.request_passwords p on p.request_id = r.id
  where r.user_auth_id = v_user.auth_id and r.status = 'pending'
    and p.password_hash = extensions.crypt(p_new_password, p.password_hash)
  limit 1;

  if found then
    update public.password_reset_requests
    set request_count = request_count + 1,
        last_requested_at = now(),
        note = coalesce(v_note, note)
    where id = v_req.id
      and last_requested_at < now() - interval '5 minutes';
    return 'submitted';
  end if;

  if (select count(*) from public.password_reset_requests
      where user_auth_id = v_user.auth_id and status = 'pending') >= 3 then
    return 'submitted';
  end if;

  insert into public.password_reset_requests
    (user_auth_id, id_number, full_name, note)
  values (v_user.auth_id, v_user.id_number, v_user.full_name, v_note)
  returning id into v_new_id;

  insert into public.request_passwords (request_id, password_hash)
  values (v_new_id,
          extensions.crypt(p_new_password, extensions.gen_salt('bf')));

  return 'submitted';
end;
$$;

-- Used after a failed login to explain why. Only answers when the
-- password matches the one in a request, so it reveals nothing to
-- someone guessing IDs. Returns 'account_pending', 'account_rejected',
-- 'reset_pending', 'none' or 'rate_limited'.
create or replace function public.check_request_status(
  p_id_number text,
  p_password  text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text := upper(trim(coalesce(p_id_number, '')));
  v_status text;
begin
  if v_id = '' or coalesce(p_password, '') = '' then return 'none'; end if;
  if public._edushelf_rate_limited('status', 10, 500) then
    return 'rate_limited';
  end if;

  select case r.status when 'pending' then 'account_pending'
                       else 'account_rejected' end
  into v_status
  from public.account_requests r
  join public.request_passwords p on p.request_id = r.id
  where r.id_number = v_id
    and r.status in ('pending', 'rejected')
    and p.password_hash = extensions.crypt(p_password, p.password_hash)
  order by (r.status = 'pending') desc, r.created_at desc
  limit 1;
  if found then return v_status; end if;

  if exists (
    select 1
    from public.password_reset_requests r
    join public.request_passwords p on p.request_id = r.id
    where r.id_number = v_id and r.status = 'pending'
      and p.password_hash = extensions.crypt(p_password, p.password_hash)
  ) then
    return 'reset_pending';
  end if;

  return 'none';
end;
$$;

-- =====================================================================
-- ADMIN ACTIONS ON REQUESTS (each locks the request row, so two admins
-- can't handle the same request)
-- =====================================================================
create or replace function public.admin_approve_account_request(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req  public.account_requests;
  v_hash text;
begin
  if not public.is_admin() then
    raise exception 'Only admins can manage accounts' using errcode = '42501';
  end if;

  select * into v_req from public.account_requests
  where id = p_request_id for update;
  if not found or v_req.status <> 'pending' then
    raise exception 'Request already handled';
  end if;

  select password_hash into v_hash from public.request_passwords
  where request_id = p_request_id;
  if v_hash is null then
    raise exception 'Request is missing its password';
  end if;

  -- Uses the password the user chose, so nothing has to be sent to them.
  perform public._edushelf_create_login(v_req.id_number, v_req.full_name, v_hash);

  update public.account_requests
  set status = 'approved', resolved_at = now(), resolved_by = auth.uid()
  where id = p_request_id;
  delete from public.request_passwords where request_id = p_request_id;

  -- Any other open requests for this ID can't be right anymore.
  update public.account_requests
  set status = 'rejected', resolved_at = now(), resolved_by = auth.uid(),
      reject_reason = 'Another request for this ID was approved'
  where id_number = v_req.id_number and status = 'pending';

  return jsonb_build_object(
    'id_number', v_req.id_number, 'full_name', v_req.full_name);
end;
$$;

create or replace function public.admin_reject_account_request(
  p_request_id uuid,
  p_reason     text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can manage accounts' using errcode = '42501';
  end if;

  update public.account_requests
  set status = 'rejected', resolved_at = now(), resolved_by = auth.uid(),
      reject_reason = nullif(left(trim(coalesce(p_reason, '')), 200), '')
  where id = p_request_id and status = 'pending';
  if not found then
    raise exception 'Request already handled';
  end if;
end;
$$;

-- Approve a reset. By default the user's chosen password is applied;
-- pass p_temp_password to set a temporary one instead (must be changed
-- on next login).
create or replace function public.admin_resolve_password_request(
  p_request_id    uuid,
  p_temp_password text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req  public.password_reset_requests;
  v_hash text;
  v_name text;
begin
  if not public.is_admin() then
    raise exception 'Only admins can manage accounts' using errcode = '42501';
  end if;

  select * into v_req from public.password_reset_requests
  where id = p_request_id for update;
  if not found or v_req.status <> 'pending' then
    raise exception 'Request already handled';
  end if;

  select full_name into v_name from public.users
  where auth_id = v_req.user_auth_id;
  if not found then
    raise exception 'Account not found';
  end if;

  if p_temp_password is null then
    select password_hash into v_hash from public.request_passwords
    where request_id = p_request_id;
    if v_hash is null then
      raise exception 'Request is missing its password';
    end if;
    update auth.users set encrypted_password = v_hash, updated_at = now()
    where id = v_req.user_auth_id;
    update public.users set must_change_password = false
    where auth_id = v_req.user_auth_id;
  else
    perform public.admin_update_user(v_req.user_auth_id, v_name, p_temp_password);
  end if;

  update public.password_reset_requests
  set status = 'resolved', resolved_at = now(), resolved_by = auth.uid()
  where id = p_request_id;
  delete from public.request_passwords where request_id = p_request_id;

  -- Other open requests for this account are no longer needed.
  update public.password_reset_requests
  set status = 'dismissed', resolved_at = now(), resolved_by = auth.uid()
  where user_auth_id = v_req.user_auth_id and status = 'pending';

  return jsonb_build_object('id_number', v_req.id_number, 'full_name', v_name);
end;
$$;

create or replace function public.admin_dismiss_password_request(
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can manage accounts' using errcode = '42501';
  end if;

  update public.password_reset_requests
  set status = 'dismissed', resolved_at = now(), resolved_by = auth.uid()
  where id = p_request_id and status = 'pending';
  if not found then
    raise exception 'Request already handled';
  end if;
  delete from public.request_passwords where request_id = p_request_id;
end;
$$;

-- =====================================================================
-- PERMISSIONS
-- Supabase lets anon/authenticated run new functions by default, so
-- each one is locked down explicitly.
-- =====================================================================
revoke all on function public._edushelf_id_role(text)
  from public, anon, authenticated;
revoke all on function public._edushelf_create_login(text, text, text)
  from public, anon, authenticated;
revoke all on function public._edushelf_rate_limited(text, integer, integer)
  from public, anon, authenticated;

revoke all on function public.admin_create_user(text, text, text)
  from public, anon;
revoke all on function public.admin_update_user(uuid, text, text)
  from public, anon;
revoke all on function public.complete_password_change() from public, anon;
revoke all on function public.admin_create_users_bulk(jsonb) from public, anon;
revoke all on function public.admin_approve_account_request(uuid)
  from public, anon;
revoke all on function public.admin_reject_account_request(uuid, text)
  from public, anon;
revoke all on function public.admin_resolve_password_request(uuid, text)
  from public, anon;
revoke all on function public.admin_dismiss_password_request(uuid)
  from public, anon;

grant execute on function public.admin_create_user(text, text, text)
  to authenticated;
grant execute on function public.admin_update_user(uuid, text, text)
  to authenticated;
grant execute on function public.complete_password_change() to authenticated;
grant execute on function public.admin_create_users_bulk(jsonb)
  to authenticated;
grant execute on function public.admin_approve_account_request(uuid)
  to authenticated;
grant execute on function public.admin_reject_account_request(uuid, text)
  to authenticated;
grant execute on function public.admin_resolve_password_request(uuid, text)
  to authenticated;
grant execute on function public.admin_dismiss_password_request(uuid)
  to authenticated;

grant execute on function public.request_account(text, text, text, text, text)
  to anon, authenticated;
grant execute on function public.request_password_reset(text, text, text, text)
  to anon, authenticated;
grant execute on function public.check_request_status(text, text)
  to anon, authenticated;
