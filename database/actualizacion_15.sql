-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 15
-- Módulo 6 limitado a Alas 1 y 2 + soporte del Mapa interactivo.

-- Preservar cualquier ubicación anterior inválida antes de retirarla del campo activo.
alter table public.people add column if not exists legacy_location text;
alter table public.area_people add column if not exists legacy_location text;
alter table public.library_records add column if not exists legacy_location text;
alter table public.instrument_loan_records add column if not exists legacy_location text;
alter table public.inventory_items add column if not exists legacy_location text;

update public.people set legacy_location=coalesce(legacy_location,location),location=null
where location in ('MÓDULO 6 - ALA 3','MÓDULO 6 - ALA 4');
update public.area_people set legacy_location=coalesce(legacy_location,location),location=null
where location in ('MÓDULO 6 - ALA 3','MÓDULO 6 - ALA 4');
update public.library_records set legacy_location=coalesce(legacy_location,module),module=null
where module in ('MÓDULO 6 - ALA 3','MÓDULO 6 - ALA 4');
update public.instrument_loan_records set legacy_location=coalesce(legacy_location,location),location=null
where location in ('MÓDULO 6 - ALA 3','MÓDULO 6 - ALA 4');
update public.inventory_items set legacy_location=coalesce(legacy_location,location),location=null
where location in ('MÓDULO 6 - ALA 3','MÓDULO 6 - ALA 4');

-- Nueva regla común: Módulos 1 a 5 admiten Alas 1 a 4; Módulo 6 solo Alas 1 y 2.
alter table public.people drop constraint if exists people_location_allowed;
alter table public.people add constraint people_location_allowed check(
  location is null or location ~ '^MÓDULO [1-5] - ALA [1-4]$' or location ~ '^MÓDULO 6 - ALA [1-2]$'
) not valid;

alter table public.area_people drop constraint if exists area_people_location_allowed;
alter table public.area_people add constraint area_people_location_allowed check(
  location is null or location ~ '^MÓDULO [1-5] - ALA [1-4]$' or location ~ '^MÓDULO 6 - ALA [1-2]$'
) not valid;

alter table public.library_records drop constraint if exists library_records_valid_location;
alter table public.library_records add constraint library_records_valid_location check(
  module is null or module ~ '^MÓDULO [1-5] - ALA [1-4]$' or module ~ '^MÓDULO 6 - ALA [1-2]$'
) not valid;

alter table public.instrument_loan_records drop constraint if exists instrument_loan_records_location_check;
alter table public.instrument_loan_records drop constraint if exists instrument_loan_records_valid_location;
alter table public.instrument_loan_records add constraint instrument_loan_records_valid_location check(
  location is null or location ~ '^MÓDULO [1-5] - ALA [1-4]$' or location ~ '^MÓDULO 6 - ALA [1-2]$'
) not valid;

alter table public.inventory_items drop constraint if exists inventory_items_location_check;
alter table public.inventory_items drop constraint if exists inventory_items_valid_location;
alter table public.inventory_items add constraint inventory_items_valid_location check(
  location is null or location ~ '^MÓDULO [1-5] - ALA [1-4]$' or location ~ '^MÓDULO 6 - ALA [1-2]$'
) not valid;

