-- ACTUALIZACIÓN 03 · PPLs, UBICACIONES Y PPLs EN EL ÁREA
-- Ejecutar en Supabase > SQL Editor después de las actualizaciones anteriores.

-- 1. Restringir las nuevas ubicaciones a 6 módulos con 4 alas cada uno.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='people_location_allowed' and conrelid='public.people'::regclass
  ) then
    alter table public.people add constraint people_location_allowed check (
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

-- 2. PPLs que cumplen funciones dentro del Área de Promoción Cultural.
create table if not exists public.area_people (
  id bigint generated always as identity primary key,
  person_id bigint not null unique references public.people(id),
  area_role text not null check(area_role in ('MONITOR','FAJINERO')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists area_people_role_idx on public.area_people(area_role,active);

-- 3. Mayúsculas, fecha de actualización y auditoría.
drop trigger if exists force_uppercase_area_people on public.area_people;
create trigger force_uppercase_area_people
before insert or update on public.area_people
for each row execute function public.force_uppercase_fields();

drop trigger if exists set_area_people_updated on public.area_people;
create trigger set_area_people_updated
before update on public.area_people
for each row execute function public.set_updated_at();

drop trigger if exists audit_area_people on public.area_people;
create trigger audit_area_people
after insert or update or delete on public.area_people
for each row execute function public.audit_change();

-- 4. Seguridad.
alter table public.area_people enable row level security;

drop policy if exists area_people_read on public.area_people;
drop policy if exists area_people_insert on public.area_people;
drop policy if exists area_people_update on public.area_people;
drop policy if exists area_people_delete_admin on public.area_people;

create policy area_people_read on public.area_people
for select to authenticated using(public.is_active_user());
create policy area_people_insert on public.area_people
for insert to authenticated with check(public.is_active_user());
create policy area_people_update on public.area_people
for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy area_people_delete_admin on public.area_people
for delete to authenticated using(public.is_admin());

grant select,insert,update,delete on public.area_people to authenticated;
grant usage,select on sequence public.area_people_id_seq to authenticated;

