-- =====================================================================
-- Live updates: make sure every table the app watches is published to
-- Supabase Realtime, so badges and lists update without restarting the
-- app (e.g. a notification marked as read, a handled password request).
--
-- Safe to re-run: tables already published are skipped.
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'notifications', 'materials', 'permissions', 'users',
    'password_reset_requests', 'activity_logs'
  ]
  loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t)
       and not exists (
         select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public' and tablename = t)
    then
      execute format(
        'alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- Lists every table that now sends live updates (for checking).
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'
order by tablename;
