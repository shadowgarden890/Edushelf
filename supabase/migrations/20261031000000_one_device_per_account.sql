-- =====================================================================
-- One device per account. Signing in claims the account for this
-- device; a second device is refused while the first is in use.
-- "In use" means the app is open and checking in (every 2 minutes);
-- after 10 minutes without a check-in (app closed, phone lost) the
-- account is free again. Logging out frees it at once, and the admin
-- can free it from Edit Account.
-- Safe to re-run.
-- =====================================================================

alter table public.users
  add column if not exists active_device_id text,
  add column if not exists active_device_name text,
  add column if not exists active_seen_at timestamptz;

-- Claims the signed-in user's account for this device.
-- Returns {"ok": true} or {"ok": false, "device": ..., "seen_at": ...}.
create or replace function public.claim_device(
  p_device_id text,
  p_device_name text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u record;
begin
  select id_number, active_device_id, active_device_name, active_seen_at
    into u
    from public.users
   where id_number = public.current_id_number()
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_profile');
  end if;

  if u.active_device_id is not null
     and u.active_device_id <> p_device_id
     and u.active_seen_at > now() - interval '10 minutes' then
    return jsonb_build_object(
      'ok', false,
      'device', u.active_device_name,
      'seen_at', u.active_seen_at);
  end if;

  update public.users
     set active_device_id = p_device_id,
         active_device_name = p_device_name,
         active_seen_at = now()
   where id_number = u.id_number;

  return jsonb_build_object('ok', true);
end;
$$;

-- Keeps the claim alive. False when this device no longer holds the
-- account (another device took over, or the admin signed it out).
create or replace function public.device_heartbeat(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.users
     set active_seen_at = now()
   where id_number = public.current_id_number()
     and active_device_id = p_device_id;
  return found;
end;
$$;

-- Frees the account when this device logs out.
create or replace function public.release_device(p_device_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.users
     set active_device_id = null,
         active_device_name = null,
         active_seen_at = null
   where id_number = public.current_id_number()
     and active_device_id = p_device_id;
end;
$$;

-- Admin: frees an account (e.g. a lost phone). That device is signed
-- out the next time it checks in.
create or replace function public.admin_release_device(p_id_number text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can do this.';
  end if;
  update public.users
     set active_device_id = null,
         active_device_name = null,
         active_seen_at = null
   where id_number = upper(trim(p_id_number));
end;
$$;

revoke all on function public.claim_device(text, text) from public, anon;
revoke all on function public.device_heartbeat(text) from public, anon;
revoke all on function public.release_device(text) from public, anon;
revoke all on function public.admin_release_device(text) from public, anon;
grant execute on function public.claim_device(text, text) to authenticated;
grant execute on function public.device_heartbeat(text) to authenticated;
grant execute on function public.release_device(text) to authenticated;
grant execute on function public.admin_release_device(text) to authenticated;
