-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 20
-- Préstamos vinculados a Monitores, eliminación auditada y ubicaciones sincronizadas.

alter table public.instrument_loan_records
add column if not exists area_person_id bigint
references public.area_people(id) on delete restrict;

create index if not exists instrument_loan_records_area_person_idx
on public.instrument_loan_records(area_person_id);

-- Admite todas las ubicaciones que puede tener actualmente un Monitor.
alter table public.instrument_loan_records drop constraint if exists instrument_loan_records_location_check;
alter table public.instrument_loan_records drop constraint if exists instrument_loan_records_valid_location;
alter table public.instrument_loan_records add constraint instrument_loan_records_valid_location check(
  location is null
  or location ~ '^MÓDULO [1-5] - ALA [1-4]$'
  or location ~ '^MÓDULO 6 - ALA [1-2]$'
  or location in ('ADMISIÓN','SIN UBICACIÓN ACTUAL')
) not valid;

create or replace function public.sync_instrument_loan_monitor()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  selected_monitor record;
begin
  if new.area_person_id is null then
    return new;
  end if;

  select last_name,first_name,location into selected_monitor
  from public.area_people
  where id=new.area_person_id
    and is_monitor=true
    and deleted_at is null;

  if not found then
    raise exception 'LA PPL SELECCIONADA NO ES UN MONITOR';
  end if;

  new.ppl_name=upper(selected_monitor.last_name||', '||selected_monitor.first_name);
  new.location=upper(selected_monitor.location);
  return new;
end;
$$;

drop trigger if exists sync_instrument_loan_monitor on public.instrument_loan_records;
create trigger sync_instrument_loan_monitor
before insert or update of area_person_id on public.instrument_loan_records
for each row execute function public.sync_instrument_loan_monitor();

-- La política vigente permite que Operadores y Administradores eliminen
-- préstamos. El trigger audit_instrument_loan_records conserva quién lo hizo.
