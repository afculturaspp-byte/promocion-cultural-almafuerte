-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 06
-- Actividades con nombre del taller y lugares permitidos.

alter table public.activities
drop constraint if exists activities_location_allowed;
alter table public.activities
add constraint activities_location_allowed check (
  location is not null and
  location in ('SALA DE ENSAYO','SALA DE RADIO','CABINA DE RADIO','SALON','SUM')
) not valid;

update public.activities activity
set title=upper(workshop.name)
from public.workshops workshop
where activity.workshop_id=workshop.id
  and activity.title is distinct from upper(workshop.name);

create or replace function public.create_activity(
  p_workshop_id bigint,
  p_title text,
  p_activity_date date,
  p_location text default null,
  p_notes text default null
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

  select name into workshop_name
  from public.workshops
  where id=p_workshop_id;

  if workshop_name is null then raise exception 'TALLER NO ENCONTRADO'; end if;

  insert into public.activities(workshop_id,title,activity_date,location,notes,created_by)
  values(p_workshop_id,upper(workshop_name),p_activity_date,upper(p_location),upper(p_notes),auth.uid())
  returning id into new_activity_id;

  insert into public.activity_participants(activity_id,person_id)
  select new_activity_id,e.person_id
  from public.enrollments e
  where e.workshop_id=p_workshop_id and e.active=true;

  return new_activity_id;
end;
$$;

grant execute on function public.create_activity(bigint,text,date,text,text) to authenticated;
