-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 11
-- Ubicaciones normalizadas en Biblioteca y limpieza del calendario heredado.

-- 1. Conserva el valor original del Excel antes de normalizarlo.
alter table public.library_records
add column if not exists legacy_location text;

update public.library_records
set legacy_location=module
where module is not null
  and module !~ '^MÓDULO [1-6] - ALA [1-4]$'
  and legacy_location is null;

-- Convierte formatos como 1.1, 2.4 o 3. 4 al formato de Ubicación del sistema.
update public.library_records
set module='MÓDULO ' || substring(module from '^\s*([1-6])') ||
           ' - ALA ' || substring(module from '[.\-]\s*([1-4])\s*$')
where module ~ '^\s*[1-6]\s*[.\-]\s*[1-4]\s*$';

-- Las ubicaciones históricas que no corresponden a un Módulo/Ala quedan
-- preservadas en legacy_location, pero se retiran del campo normalizado.
update public.library_records
set module=null
where module is not null
  and module !~ '^MÓDULO [1-6] - ALA [1-4]$';

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='library_records_valid_location'
      and conrelid='public.library_records'::regclass
  ) then
    alter table public.library_records
    add constraint library_records_valid_location
    check(module is null or module ~ '^MÓDULO [1-6] - ALA [1-4]$');
  end if;
end;
$$;

-- 2. Elimina únicamente horarios heredados de los antiguos Talleres.
-- Las Actividades actuales (workshop_id nulo) y sus horarios se conservan.
delete from public.activity_schedules schedule
using public.activities activity
where schedule.activity_id=activity.id
  and activity.workshop_id is not null;

