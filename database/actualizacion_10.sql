-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 10
-- Hora de finalización para cada día programado de una Actividad.

alter table public.activity_schedules
add column if not exists end_time time;

-- Conserva los horarios existentes asignándoles inicialmente una duración de una hora.
update public.activity_schedules
set end_time=least(start_time + interval '1 hour',time '17:00')
where end_time is null;

alter table public.activity_schedules
alter column end_time set not null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='activity_schedules_valid_range'
      and conrelid='public.activity_schedules'::regclass
  ) then
    alter table public.activity_schedules
    add constraint activity_schedules_valid_range
    check(end_time>start_time and end_time<=time '17:00');
  end if;
end;
$$;

create or replace function public.create_cultural_activity(
  p_title text,
  p_instructor text default null,
  p_capacity integer default null,
  p_location text default null,
  p_description text default null,
  p_schedules jsonb default '[]'::jsonb
) returns bigint language plpgsql security definer set search_path=public as $$
declare new_activity_id bigint;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if jsonb_array_length(p_schedules)=0 then raise exception 'DEBÉS CARGAR AL MENOS UN DÍA Y HORARIO'; end if;
  if exists(
    select 1 from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time)
    where item.end_time<=item.start_time
  ) then raise exception 'LA HORA DE FINALIZACIÓN DEBE SER POSTERIOR A LA DE COMIENZO'; end if;

  insert into public.activities(workshop_id,title,activity_date,location,created_by,status,archived,instructor,capacity,description)
  values(null,upper(p_title),current_date,upper(p_location),auth.uid(),'activa',false,upper(p_instructor),p_capacity,upper(p_description))
  returning id into new_activity_id;

  insert into public.activity_schedules(activity_id,day_of_week,start_time,end_time)
  select new_activity_id,upper(item.day_of_week),item.start_time,item.end_time
  from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time);

  return new_activity_id;
end;
$$;

grant execute on function public.create_cultural_activity(text,text,integer,text,text,jsonb) to authenticated;
