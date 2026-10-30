-- Undoes the archive feature (20261029): archived materials go back to
-- approved, and the status check no longer allows 'archived'.
-- Safe to run whether or not 20261029 was run.

update public.materials set status = 'approved' where status = 'archived';

-- Drop any check on materials.status, whatever it was named.
do $$
declare
  c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'materials'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%status%'
  loop
    execute format('alter table public.materials drop constraint %I',
                   c.conname);
  end loop;
end $$;

alter table public.materials
  add constraint materials_status_check
  check (status in ('pending', 'approved', 'rejected'));
