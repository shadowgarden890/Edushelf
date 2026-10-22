-- Lets the admin archive approved materials instead of deleting them.
-- Archived materials are hidden from students (the materials select
-- policy only shows 'approved' ones to them) and can be restored.

-- Drop any earlier check on materials.status, whatever it was named.
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
  check (status in ('pending', 'approved', 'rejected', 'archived'));
