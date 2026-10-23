-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 08
-- Estados y archivo de Actividades. Estados independientes para PPLs en el Área.

alter table public.activities add column if not exists status text not null default 'activa';
alter table public.activities add column if not exists archived boolean not null default false;
alter table public.activities add column if not exists archived_at timestamptz;

alter table public.activities drop constraint if exists activities_status_allowed;
alter table public.activities add constraint activities_status_allowed
check (status in ('activa','finalizada'));

create index if not exists activities_status_archive_idx
on public.activities(archived,status,created_at desc);

alter table public.area_people add column if not exists deleted_at timestamptz;

-- Antes de esta actualización, active=false significaba que el registro había
-- sido eliminado. Se preservan esas bajas y desde ahora INACTIVO será un estado.
update public.area_people
set deleted_at=coalesce(deleted_at,updated_at,now())
where active=false and deleted_at is null;

create index if not exists area_people_deleted_idx
on public.area_people(deleted_at,area_role,active);

