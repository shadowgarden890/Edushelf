-- =====================================================================
-- Alert every admin when a student or faculty member sends a new
-- "Forgot password" request (the request comes from the login screen,
-- before anyone is signed in, so the server creates the notification).
--
-- Requires 20261023000000_admin_recovery_password.sql. Safe to re-run.
-- =====================================================================

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
  -- Admins log in with their recovery password instead.
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
    -- Repeats only bump the existing request; admins aren't alerted again.
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

  insert into public.notifications
    (recipient_id, sender_id, title, body, type, is_read)
  select a.id_number, v_user.id_number,
         'New Password Request',
         v_user.full_name || ' (' || v_user.id_number || ') forgot their '
           || 'password. Reset it in Users > Password Requests.',
         'admin_password', false
  from public.users a
  where a.role = 'admin';

  return 'submitted';
end;
$$;
