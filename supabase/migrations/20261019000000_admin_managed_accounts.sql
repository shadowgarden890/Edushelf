-- =====================================================================
-- Admin-managed accounts: the admin creates every student and faculty
-- account and can edit names / reset passwords. Users cannot sign up.
--
-- Requires 20261014000000_move_to_supabase_auth.sql to have been run.
--
-- AFTER RUNNING: Dashboard -> Authentication -> Sign In / Providers ->
-- "Allow new users to sign up": turn OFF. These functions still work
-- with sign-ups off because they create the login directly.
--
-- The email domain below must match AuthService.authEmailDomain.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Create an account. Role and department come from the ID number (the
-- handle_new_auth_user trigger validates it and creates the profile).
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
  v_id    text := upper(trim(coalesce(p_id_number, '')));
  v_name  text := trim(coalesce(p_full_name, ''));
  v_email text := lower(v_id) || '@edushelf.app';
  v_uid   uuid := gen_random_uuid();
begin
  if not public.is_admin() then
    raise exception 'Only admins can create accounts' using errcode = '42501';
  end if;
  if v_name = '' then
    raise exception 'Full name is required';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
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
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('id_number', v_id, 'full_name', v_name),
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

-- ---------------------------------------------------------------------
-- Edit an account: change the full name and/or reset the password.
-- Pass null for p_new_password to keep the current password.
-- ---------------------------------------------------------------------
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
  if v_name = '' then
    raise exception 'Full name is required';
  end if;
  if not exists (select 1 from public.users where auth_id = p_auth_id) then
    raise exception 'Account not found';
  end if;

  update public.users set full_name = v_name where auth_id = p_auth_id;

  update auth.users
  set raw_user_meta_data =
        coalesce(raw_user_meta_data, '{}'::jsonb)
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
  end if;
end;
$$;

-- Only signed-in users can call these; the functions check for admin.
revoke all on function public.admin_create_user(text, text, text)
  from public, anon;
revoke all on function public.admin_update_user(uuid, text, text)
  from public, anon;
grant execute on function public.admin_create_user(text, text, text)
  to authenticated;
grant execute on function public.admin_update_user(uuid, text, text)
  to authenticated;
