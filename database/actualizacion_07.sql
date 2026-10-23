-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 07
-- Programación por actividad, calendario semanal y eliminación lógica de talleres.

create table if not exists public.activity_schedules (
  id bigint generated always as identity primary key,
  activity_id bigint not null references public.activities(id) on delete cascade,
  day_of_week text not null check (day_of_week in ('LUNES','MARTES','MIÉRCOLES','JUEVES','VIERNES')),
  start_time time not null check (start_time between time '08:00' and time '16:00'),
  created_at timestamptz not null default now(),
  unique(activity_id,day_of_week)
);

create index if not exists activity_schedules_day_time_idx
on public.activity_schedules(day_of_week,start_time);

alter table public.activity_schedules enable row level security;
drop policy if exists activity_schedules_read on public.activity_schedules;
drop policy if exists activity_schedules_insert on public.activity_schedules;
drop policy if exists activity_schedules_update on public.activity_schedules;
drop policy if exists activity_schedules_delete on public.activity_schedules;
create policy activity_schedules_read on public.activity_schedules for select to authenticated using(public.is_active_user());
create policy activity_schedules_insert on public.activity_schedules for insert to authenticated with check(public.is_active_user());
create policy activity_schedules_update on public.activity_schedules for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy activity_schedules_delete on public.activity_schedules for delete to authenticated using(public.is_active_user());

grant select,insert,update,delete on public.activity_schedules to authenticated;
grant usage,select on sequence public.activity_schedules_id_seq to authenticated;

drop trigger if exists audit_activity_schedules on public.activity_schedules;
create trigger audit_activity_schedules after insert or update or delete on public.activity_schedules
for each row execute function public.audit_change();

create or replace function public.create_activity_with_schedules(
  p_workshop_id bigint,
  p_location text,
  p_notes text default null,
  p_schedules jsonb default '[]'::jsonb
) returns bigint
language plpgsql
security definer
set search_path=public
as $$
declare
  new_activity_id bigint;
  workshop_name text;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if jsonb_array_length(p_schedules)=0 then raise exception 'DEBÉS CARGAR AL MENOS UN DÍA Y HORARIO'; end if;

  select name into workshop_name from public.workshops
  where id=p_workshop_id and status='activo';
  if workshop_name is null then raise exception 'TALLER NO ENCONTRADO O INACTIVO'; end if;

  insert into public.activities(workshop_id,title,activity_date,location,notes,created_by)
  values(p_workshop_id,upper(workshop_name),current_date,upper(p_location),upper(p_notes),auth.uid())
  returning id into new_activity_id;

  insert into public.activity_schedules(activity_id,day_of_week,start_time)
  select new_activity_id,upper(item.day_of_week),item.start_time::time
  from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time text);

  insert into public.activity_participants(activity_id,person_id)
  select new_activity_id,e.person_id
  from public.enrollments e
  where e.workshop_id=p_workshop_id and e.active=true;

  return new_activity_id;
end;
$$;

grant execute on function public.create_activity_with_schedules(bigint,text,text,jsonb) to authenticated;
