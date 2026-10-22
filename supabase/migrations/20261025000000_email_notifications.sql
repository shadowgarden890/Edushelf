-- =====================================================================
-- Email notifications (via Brevo, free plan: 300 emails/day).
--
-- Every row added to public.notifications is also emailed to that user,
-- if their contact on file (public.user_contacts) is an email address.
-- Sending happens in the background (pg_net), so a failed email never
-- blocks the app.
--
-- SETUP (once, in the SQL Editor, with YOUR values - don't save them in
-- this file or share them in chats):
--
--   select vault.create_secret('xkeysib-YOUR-BREVO-API-KEY', 'brevo_api_key');
--   select vault.create_secret('your.verified.sender@gmail.com', 'brevo_sender_email');
--
-- Until both secrets exist, nothing is emailed (the app works as before).
--
-- Requires 20261024000000_password_request_alerts.sql. Safe to re-run.
-- =====================================================================

create extension if not exists pg_net;

-- One row per email attempt: keeps us under the free daily limit and
-- shows what was sent.
create table if not exists public.email_log (
  id              bigint generated always as identity primary key,
  notification_id uuid,
  recipient       text not null,
  subject         text,
  request_id      bigint,
  created_at      timestamptz not null default now()
);
create index if not exists email_log_created on public.email_log (created_at);
alter table public.email_log enable row level security;

drop policy if exists "Admins can read the email log" on public.email_log;
create policy "Admins can read the email log"
  on public.email_log for select
  to authenticated using (public.is_admin());

create or replace function public._edushelf_email_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email   text;
  v_key     text;
  v_sender  text;
  v_subject text := 'Edushelf: ' || coalesce(new.title, 'Notification');
  v_request bigint;
begin
  -- The recipient's email on file (phone numbers are skipped).
  select c.contact into v_email
  from public.users u
  join public.user_contacts c on c.auth_id = u.auth_id
  where u.id_number = new.recipient_id
    and c.contact ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$';
  if v_email is null then
    return new;
  end if;

  -- Stay under Brevo's free plan (300/day).
  if (select count(*) from public.email_log
      where created_at > now() - interval '1 day') >= 280 then
    return new;
  end if;

  select decrypted_secret into v_key
  from vault.decrypted_secrets where name = 'brevo_api_key';
  select decrypted_secret into v_sender
  from vault.decrypted_secrets where name = 'brevo_sender_email';
  if v_key is null or v_sender is null then
    return new; -- email not set up yet
  end if;

  select net.http_post(
    url := 'https://api.brevo.com/v3/smtp/email',
    headers := jsonb_build_object(
      'api-key', v_key,
      'Content-Type', 'application/json',
      'accept', 'application/json'),
    body := jsonb_build_object(
      'sender', jsonb_build_object('name', 'Edushelf', 'email', v_sender),
      'to', jsonb_build_array(jsonb_build_object('email', v_email)),
      'subject', v_subject,
      'textContent',
        coalesce(new.body, '') || E'\n\n'
        || 'Open the Edushelf app for details.' || E'\n'
        || '(This is an automatic message from Edushelf.)')
  ) into v_request;

  insert into public.email_log (notification_id, recipient, subject, request_id)
  values (new.id, v_email, v_subject, v_request);

  return new;
exception when others then
  -- Never let an email problem block the notification itself.
  return new;
end;
$$;

revoke all on function public._edushelf_email_notification()
  from public, anon, authenticated;

drop trigger if exists email_on_notification on public.notifications;
create trigger email_on_notification
  after insert on public.notifications
  for each row execute function public._edushelf_email_notification();
