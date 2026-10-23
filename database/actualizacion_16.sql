-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 16
-- Doble función en PPLs del área, una jornada por Actividad,
-- nuevas ubicaciones de PPLs e Inventario sin ubicación.

-- 1. Una misma PPL puede ser MONITOR y FAJINERO simultáneamente.
alter table public.area_people add column if not exists is_monitor boolean not null default false;
alter table public.area_people add column if not exists is_fajinero boolean not null default false;

update public.area_people
set is_monitor=(area_role='MONITOR'),
    is_fajinero=(area_role='FAJINERO')
where not is_monitor and not is_fajinero;

alter table public.area_people drop constraint if exists area_people_has_role;
alter table public.area_people add constraint area_people_has_role
check(is_monitor or is_fajinero) not valid;

alter table public.area_people drop constraint if exists area_people_specialty_allowed;
alter table public.area_people add constraint area_people_specialty_allowed check(
  (is_monitor and specialty is not null and specialty in ('MUSICA','RADIO','PRODUCCIÓN','BARBERÍA','EMPRENDEDURISMO'))
  or (not is_monitor and specialty is null)
) not valid;

create index if not exists area_people_functions_idx
on public.area_people(is_monitor,is_fajinero,active,deleted_at);

-- 2. Las PPLs también pueden figurar en ADMISIÓN o SIN UBICACIÓN ACTUAL.
alter table public.people drop constraint if exists people_location_allowed;
alter table public.people add constraint people_location_allowed check(
  location is null
  or location ~ '^MÓDULO [1-5] - ALA [1-4]$'
  or location ~ '^MÓDULO 6 - ALA [1-2]$'
  or location in ('ADMISIÓN','SIN UBICACIÓN ACTUAL')
) not valid;

alter table public.area_people drop constraint if exists area_people_location_allowed;
alter table public.area_people add constraint area_people_location_allowed check(
  location is null
  or location ~ '^MÓDULO [1-5] - ALA [1-4]$'
  or location ~ '^MÓDULO 6 - ALA [1-2]$'
  or location in ('ADMISIÓN','SIN UBICACIÓN ACTUAL')
) not valid;

-- 3. Cada Actividad queda asociada a un solo día y horario.
-- Si una actividad anterior tenía varios días, cada horario adicional se
-- convierte en otra actividad, conservando sus datos e integrantes.
do $$
declare
  grouped record;
  extra_schedule record;
  cloned_activity_id bigint;
begin
  for grouped in
    select activity_id,min(id) as retained_schedule_id
    from public.activity_schedules
    group by activity_id
    having count(*)>1
  loop
    for extra_schedule in
      select id from public.activity_schedules
      where activity_id=grouped.activity_id and id<>grouped.retained_schedule_id
      order by id
    loop
      insert into public.activities(
        workshop_id,title,activity_date,location,notes,created_by,
        status,archived,archived_at,instructor,capacity,description
      )
      select workshop_id,title,activity_date,location,notes,created_by,
             status,archived,archived_at,instructor,capacity,description
      from public.activities where id=grouped.activity_id
      returning id into cloned_activity_id;

      insert into public.activity_participants(activity_id,person_id)
      select cloned_activity_id,person_id
      from public.activity_participants
      where activity_id=grouped.activity_id
      on conflict do nothing;

      update public.activity_schedules
      set activity_id=cloned_activity_id
      where id=extra_schedule.id;
    end loop;
  end loop;
end;
$$;

create unique index if not exists activity_schedules_one_per_activity_idx
on public.activity_schedules(activity_id);

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
  if jsonb_array_length(p_schedules)<>1 then raise exception 'LA ACTIVIDAD DEBE TENER UN ÚNICO DÍA Y HORARIO'; end if;
  if exists(
    select 1 from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time time,end_time time)
    where item.start_time is null or item.end_time is null or item.end_time<=item.start_time
  ) then raise exception 'LOS HORARIOS DE LA ACTIVIDAD NO SON VÁLIDOS'; end if;

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
  if jsonb_array_length(p_schedules)<>1 then raise exception 'LA ACTIVIDAD DEBE TENER UN ÚNICO DÍA Y HORARIO'; end if;
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

grant execute on function public.create_cultural_activity(text,text,integer,text,text,jsonb,jsonb) to authenticated;
grant execute on function public.update_cultural_activity(bigint,text,text,integer,text,text,jsonb,jsonb) to authenticated;

-- 4. Inventario sin ubicación. El dato anterior se conserva en legacy_location.
update public.inventory_items
set legacy_location=coalesce(legacy_location,location)
where location is not null;

alter table public.inventory_items drop constraint if exists inventory_items_location_check;
alter table public.inventory_items drop constraint if exists inventory_items_valid_location;
alter table public.inventory_items drop column if exists location;

create or replace function public.force_uppercase_cultural_assets() returns trigger language plpgsql as $$
begin
  if tg_table_name='instrument_loan_records' then
    new.instrument_name=upper(new.instrument_name);new.details=upper(new.details);
    new.ppl_name=upper(new.ppl_name);new.location=upper(new.location);new.renewal=upper(new.renewal);
  else
    new.category=upper(new.category);new.name=upper(new.name);new.condition=upper(new.condition);
    new.notes=upper(new.notes);
  end if;
  return new;
end;
$$;

drop trigger if exists force_uppercase_inventory_items on public.inventory_items;
create trigger force_uppercase_inventory_items
before insert or update on public.inventory_items
for each row execute function public.force_uppercase_cultural_assets();
