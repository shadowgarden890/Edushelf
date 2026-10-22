-- =====================================================================
-- Requests no longer carry a password chosen by the user. When the admin
-- approves an account or password request, the admin sets a TEMPORARY
-- password, sends it to the user's contact, and the user must change it
-- on first login.
--
-- Requires 20261020000000_account_and_password_requests.sql. Safe to
-- re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Contact on file (email or phone) for sending temporary passwords.
-- Separate table so only admins can read it - the users table is
-- readable by every signed-in user.
-- ---------------------------------------------------------------------
create table if not exists public.user_contacts (
  auth_id    uuid primary key references auth.users (id) on delete cascade,
  contact    text not null,
  updated_at timestamptz not null default now()
);
alter table public.user_contacts enable row level security;

drop policy if exists "Admins can read contacts" on public.user_contacts;
create policy "Admins can read contacts"
  on public.user_contacts for select
  to authenticated using (public.is_admin());

-- Where a reset's temporary password must be sent (copied from the
-- contact on file, never from what was typed in the request).
alter table public.password_reset_requests
  add column if not exists contact text;

-- The old flow's functions and stored hashes are no longer used.
drop function if exists public.request_account(text, text, text, text, text);
drop function if exists public.request_password_reset(text, text, text, text);
drop function if exists public.check_request_status(text, text);
drop function if exists public.admin_approve_account_request(uuid);
delete from public.request_passwords;

-- ---------------------------------------------------------------------
-- Admin: set or change a user's contact on file.
-- ---------------------------------------------------------------------
create or replace function public.admin_set_contact(
  p_auth_id uuid,
  p_contact text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contact text := nullif(left(trim(coalesce(p_contact, '')), 100), '');
begin
  if not public.is_admin() then
    raise exception 'Only admins can edit accounts' using errcode = '42501';
  end if;

  if v_contact is null then
    delete from public.user_contacts where auth_id = p_auth_id;
  else
    insert into public.user_contacts (auth_id, contact)
    values (p_auth_id, v_contact)
    on conflict (auth_id)
    do update set contact = excluded.contact, updated_at = now();
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Public: request an account (student or faculty).
-- Returns 'submitted', 'invalid_id', 'invalid_contact', 'invalid' or
-- 'rate_limited'. Never reveals whether the ID already has an account.
-- ---------------------------------------------------------------------
create or replace function public.request_account(
  p_id_number text,
  p_full_name text,
  p_contact   text,
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
  v_contact text := trim(coalesce(p_contact, ''));
  v_note    text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_req_id  uuid;
begin
  -- Admin accounts are only created by admins.
  if v_role is null or v_role = 'admin' or length(v_id) > 30 then
    return 'invalid_id';
  end if;
  if v_name = '' or length(v_name) > 120 then return 'invalid'; end if;
  if length(v_contact) < 5 or length(v_contact) > 100 then
    return 'invalid_contact';
  end if;

  if public._edushelf_rate_limited('account', 5, 200) then
    return 'rate_limited';
  end if;

  -- Requests for the same ID are handled one at a time.
  perform pg_advisory_xact_lock(hashtext('edushelf-account:' || v_id));

  if exists (select 1 from public.users where id_number = v_id) then
    return 'submitted';
  end if;

  -- Same person sending again: merge into their request.
  select id into v_req_id
  from public.account_requests
  where id_number = v_id and status = 'pending'
    and lower(full_name) = lower(v_name)
    and lower(coalesce(contact, '')) = lower(v_contact)
  limit 1;

  if found then
    update public.account_requests
    set request_count = request_count + 1,
        last_requested_at = now(),
        note = coalesce(v_note, note)
    where id = v_req_id
      and last_requested_at < now() - interval '5 minutes';
    return 'submitted';
  end if;

  -- Different requests for one ID stay separate (flagged for the admin)
  -- and are capped at 3.
  if (select count(*) from public.account_requests
      where id_number = v_id and status = 'pending') >= 3 then
    return 'submitted';
  end if;

  insert into public.account_requests
    (id_number, full_name, role, contact, note)
  values (v_id, v_name, v_role, v_contact, v_note);

  return 'submitted';
end;
$$;

-- ---------------------------------------------------------------------
-- Public: forgot password. Returns 'submitted' or 'rate_limited'.
-- Never reveals whether the ID exists. One open request per account.
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
-- Admin: approve an account request with a temporary password.
-- Locks the request so two admins can't handle it at once.
-- ---------------------------------------------------------------------
create or replace function public.admin_approve_account_request(
  p_request_id    uuid,
  p_temp_password text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req public.account_requests;
  v_uid uuid;
begin
  if not public.is_admin() then
    raise exception 'Only admins can manage accounts' using errcode = '42501';
  end if;
  if length(coalesce(p_temp_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;

  select * into v_req from public.account_requests
  where id = p_request_id for update;
  if not found or v_req.status <> 'pending' then
    raise exception 'Request already handled';
  end if;

  v_uid := public._edushelf_create_login(
    v_req.id_number, v_req.full_name,
    extensions.crypt(p_temp_password, extensions.gen_salt('bf')));

  update public.users set must_change_password = true where auth_id = v_uid;

  if nullif(trim(coalesce(v_req.contact, '')), '') is not null then
    insert into public.user_contacts (auth_id, contact)
    values (v_uid, trim(v_req.contact))
    on conflict (auth_id)
    do update set contact = excluded.contact, updated_at = now();
  end if;

  update public.account_requests
  set status = 'approved', resolved_at = now(), resolved_by = auth.uid()
  where id = p_request_id;

  -- Any other open requests for this ID can't be right anymore.
  update public.account_requests
  set status = 'rejected', resolved_at = now(), resolved_by = auth.uid(),
      reject_reason = 'Another request for this ID was approved'
  where id_number = v_req.id_number and status = 'pending';

  return jsonb_build_object(
    'id_number', v_req.id_number,
    'full_name', v_req.full_name,
    'contact', v_req.contact);
end;
$$;

-- ---------------------------------------------------------------------
-- Admin: approve a password request with a temporary password.
-- (Same signature as before; the temporary password is now required.)
-- ---------------------------------------------------------------------
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
  v_req     public.password_reset_requests;
  v_name    text;
  v_contact text;
begin
  if not public.is_admin() then
    raise exception 'Only admins can manage accounts' using errcode = '42501';
  end if;
  if length(coalesce(p_temp_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
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

  -- Sets the password and requires a change on next login.
  perform public.admin_update_user(v_req.user_auth_id, v_name, p_temp_password);

  update public.password_reset_requests
  set status = 'resolved', resolved_at = now(), resolved_by = auth.uid()
  where id = p_request_id;

  update public.password_reset_requests
  set status = 'dismissed', resolved_at = now(), resolved_by = auth.uid()
  where user_auth_id = v_req.user_auth_id and status = 'pending';

  select contact into v_contact from public.user_contacts
  where auth_id = v_req.user_auth_id;

  return jsonb_build_object(
    'id_number', v_req.id_number, 'full_name', v_name, 'contact', v_contact);
end;
$$;

-- ---------------------------------------------------------------------
-- PERMISSIONS
-- ---------------------------------------------------------------------
revoke all on function public.admin_set_contact(uuid, text) from public, anon;
revoke all on function public.admin_approve_account_request(uuid, text)
  from public, anon;
revoke all on function public.request_account(text, text, text, text)
  from public;
revoke all on function public.request_password_reset(text, text, text)
  from public;

grant execute on function public.admin_set_contact(uuid, text)
  to authenticated;
grant execute on function public.admin_approve_account_request(uuid, text)
  to authenticated;
grant execute on function public.request_account(text, text, text, text)
  to anon, authenticated;
grant execute on function public.request_password_reset(text, text, text)
  to anon, authenticated;
