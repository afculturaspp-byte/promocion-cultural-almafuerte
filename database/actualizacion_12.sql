-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 12
-- Edición completa y reactivación de Actividades.

create or replace function public.update_cultural_activity(
  p_activity_id bigint,
  p_title text,
  p_instructor text default null,
  p_capacity integer default null,
  p_location text default null,
  p_description text default null,
  p_schedules jsonb default '[]'::jsonb
) returns bigint language plpgsql security definer set search_path=public as $$
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if jsonb_array_length(p_schedules)=0 then raise exception 'DEBÉS CARGAR AL MENOS UN DÍA Y HORARIO'; end if;
  if exists(
    select 1 from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time)
    where item.start_time is null or item.end_time is null or item.end_time<=item.start_time
  ) then raise exception 'LOS HORARIOS DE LA ACTIVIDAD NO SON VÁLIDOS'; end if;
  if (
    select count(*)<>count(distinct upper(item.day_of_week))
    from jsonb_to_recordset(p_schedules) as item(day_of_week text)
  ) then raise exception 'CADA DÍA PUEDE CARGARSE UNA SOLA VEZ'; end if;

  update public.activities
  set title=upper(p_title),instructor=upper(p_instructor),capacity=p_capacity,
      location=upper(p_location),description=upper(p_description),updated_at=now()
  where id=p_activity_id and archived=false;

  if not found then raise exception 'ACTIVIDAD NO ENCONTRADA O ARCHIVADA'; end if;

  delete from public.activity_schedules where activity_id=p_activity_id;
  insert into public.activity_schedules(activity_id,day_of_week,start_time,end_time)
  select p_activity_id,upper(item.day_of_week),item.start_time,item.end_time
  from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time);

  return p_activity_id;
end;
$$;

grant execute on function public.update_cultural_activity(bigint,text,text,integer,text,text,jsonb) to authenticated;

