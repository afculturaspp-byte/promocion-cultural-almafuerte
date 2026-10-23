-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 13
-- Integrantes cargados directamente al crear o editar una Actividad.

create or replace function public.create_cultural_activity(
  p_title text,
  p_instructor text default null,
  p_capacity integer default null,
  p_location text default null,
  p_description text default null,
  p_schedules jsonb default '[]'::jsonb,
  p_participants jsonb default '[]'::jsonb
) returns bigint language plpgsql security definer set search_path=public as $$
declare
  new_activity_id bigint;
  participant record;
  person_key bigint;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if jsonb_array_length(p_schedules)=0 then raise exception 'DEBÉS CARGAR AL MENOS UN DÍA Y HORARIO'; end if;

  insert into public.activities(workshop_id,title,activity_date,location,created_by,status,archived,instructor,capacity,description)
  values(null,upper(p_title),current_date,upper(p_location),auth.uid(),'activa',false,upper(p_instructor),null,upper(p_description))
  returning id into new_activity_id;

  insert into public.activity_schedules(activity_id,day_of_week,start_time,end_time)
  select new_activity_id,upper(item.day_of_week),item.start_time,item.end_time
  from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time);

  for participant in
    select * from jsonb_to_recordset(p_participants)
    as item(identifier text,last_name text,first_name text,location text)
  loop
    if participant.identifier !~ '^[0-9]+$' then raise exception 'EL PRONTUARIO DEBE SER NUMÉRICO'; end if;
    insert into public.people(identifier,last_name,first_name,location,active)
    values(participant.identifier,upper(participant.last_name),upper(participant.first_name),upper(participant.location),true)
    on conflict(identifier) do update set last_name=excluded.last_name,first_name=excluded.first_name,location=excluded.location,active=true
    returning id into person_key;
    insert into public.activity_participants(activity_id,person_id)
    values(new_activity_id,person_key) on conflict(activity_id,person_id) do nothing;
  end loop;

  return new_activity_id;
end;
$$;

grant execute on function public.create_cultural_activity(text,text,integer,text,text,jsonb,jsonb) to authenticated;

create or replace function public.update_cultural_activity(
  p_activity_id bigint,
  p_title text,
  p_instructor text default null,
  p_capacity integer default null,
  p_location text default null,
  p_description text default null,
  p_schedules jsonb default '[]'::jsonb,
  p_participants jsonb default '[]'::jsonb
) returns bigint language plpgsql security definer set search_path=public as $$
declare
  participant record;
  person_key bigint;
  participant_ids bigint[] := '{}'::bigint[];
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if jsonb_array_length(p_schedules)=0 then raise exception 'DEBÉS CARGAR AL MENOS UN DÍA Y HORARIO'; end if;
  if exists(
    select 1 from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time)
    where item.start_time is null or item.end_time is null or item.end_time<=item.start_time
  ) then raise exception 'LOS HORARIOS DE LA ACTIVIDAD NO SON VÁLIDOS'; end if;

  update public.activities
  set title=upper(p_title),instructor=upper(p_instructor),capacity=null,
      location=upper(p_location),description=upper(p_description),updated_at=now()
  where id=p_activity_id and archived=false;
  if not found then raise exception 'ACTIVIDAD NO ENCONTRADA O ARCHIVADA'; end if;

  delete from public.activity_schedules where activity_id=p_activity_id;
  insert into public.activity_schedules(activity_id,day_of_week,start_time,end_time)
  select p_activity_id,upper(item.day_of_week),item.start_time,item.end_time
  from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time);

  for participant in
    select * from jsonb_to_recordset(p_participants)
    as item(identifier text,last_name text,first_name text,location text)
  loop
    if participant.identifier !~ '^[0-9]+$' then raise exception 'EL PRONTUARIO DEBE SER NUMÉRICO'; end if;
    insert into public.people(identifier,last_name,first_name,location,active)
    values(participant.identifier,upper(participant.last_name),upper(participant.first_name),upper(participant.location),true)
    on conflict(identifier) do update set last_name=excluded.last_name,first_name=excluded.first_name,location=excluded.location,active=true
    returning id into person_key;
    participant_ids:=array_append(participant_ids,person_key);
    insert into public.activity_participants(activity_id,person_id)
    values(p_activity_id,person_key) on conflict(activity_id,person_id) do nothing;
  end loop;

  delete from public.activity_participants
  where activity_id=p_activity_id and not(person_id=any(participant_ids));

  return p_activity_id;
end;
$$;

grant execute on function public.update_cultural_activity(bigint,text,text,integer,text,text,jsonb,jsonb) to authenticated;

