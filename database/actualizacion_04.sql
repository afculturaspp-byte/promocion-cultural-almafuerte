-- ACTUALIZACIÓN 04 · CURSANTES Y PPLs EN EL ÁREA INDEPENDIENTES
-- Ejecutar en Supabase > SQL Editor después de actualizacion_03.sql.

-- Agregar datos propios a PPLs en el Área.
alter table public.area_people add column if not exists identifier text;
alter table public.area_people add column if not exists last_name text;
alter table public.area_people add column if not exists first_name text;
alter table public.area_people add column if not exists location text;

-- Preservar los datos de las asignaciones que ya existían vinculadas a Cursantes.
update public.area_people area
set
  identifier=coalesce(area.identifier,person.identifier),
  last_name=coalesce(area.last_name,person.last_name),
  first_name=coalesce(area.first_name,person.first_name),
  location=coalesce(area.location,person.location)
from public.people person
where area.person_id=person.id
  and (area.identifier is null or area.last_name is null or area.first_name is null);

-- Desde ahora ambas listas son independientes.
alter table public.area_people alter column person_id drop not null;
alter table public.area_people alter column identifier set not null;
alter table public.area_people alter column last_name set not null;
alter table public.area_people alter column first_name set not null;

create unique index if not exists area_people_identifier_unique
on public.area_people(identifier);

-- Limitar también las ubicaciones de PPLs en el Área a los 6 módulos y sus 4 alas.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='area_people_location_allowed' and conrelid='public.area_people'::regclass
  ) then
    alter table public.area_people add constraint area_people_location_allowed check (
      location is null or location in (
        'MÓDULO 1 - ALA 1','MÓDULO 1 - ALA 2','MÓDULO 1 - ALA 3','MÓDULO 1 - ALA 4',
        'MÓDULO 2 - ALA 1','MÓDULO 2 - ALA 2','MÓDULO 2 - ALA 3','MÓDULO 2 - ALA 4',
        'MÓDULO 3 - ALA 1','MÓDULO 3 - ALA 2','MÓDULO 3 - ALA 3','MÓDULO 3 - ALA 4',
        'MÓDULO 4 - ALA 1','MÓDULO 4 - ALA 2','MÓDULO 4 - ALA 3','MÓDULO 4 - ALA 4',
        'MÓDULO 5 - ALA 1','MÓDULO 5 - ALA 2','MÓDULO 5 - ALA 3','MÓDULO 5 - ALA 4',
        'MÓDULO 6 - ALA 1','MÓDULO 6 - ALA 2','MÓDULO 6 - ALA 3','MÓDULO 6 - ALA 4'
      )
    ) not valid;
  end if;
end $$;

-- Recrear el trigger para garantizar mayúsculas en los nuevos campos.
drop trigger if exists force_uppercase_area_people on public.area_people;
create trigger force_uppercase_area_people
before insert or update on public.area_people
for each row execute function public.force_uppercase_fields();

