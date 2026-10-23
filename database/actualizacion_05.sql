-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 05
-- Prontuarios numéricos y especialidades de Monitores.

alter table public.area_people
add column if not exists specialty text;

-- Mantener la especialidad en mayúsculas también si se carga fuera de la app.
create or replace function public.force_uppercase_fields()
returns trigger language plpgsql as $$
declare
  payload jsonb := to_jsonb(new);
  field_name text;
  field_value text;
begin
  for field_name, field_value in
    select key, value
    from jsonb_each_text(payload)
    where value is not null and key = any(array[
      'full_name','identifier','last_name','first_name','location','notes',
      'name','instructor','schedule','description','title','author','isbn',
      'code','condition','return_condition','specialty'
    ])
  loop
    payload := jsonb_set(payload,array[field_name],to_jsonb(upper(field_value)));
  end loop;
  new := jsonb_populate_record(new,payload);
  return new;
end;
$$;

alter table public.people
drop constraint if exists people_identifier_numeric;
alter table public.people
add constraint people_identifier_numeric
check (identifier ~ '^[0-9]+$') not valid;

alter table public.area_people
drop constraint if exists area_people_identifier_numeric;
alter table public.area_people
add constraint area_people_identifier_numeric
check (identifier ~ '^[0-9]+$') not valid;

alter table public.area_people
drop constraint if exists area_people_specialty_allowed;
alter table public.area_people
add constraint area_people_specialty_allowed check (
  (area_role = 'FAJINERO' and specialty is null)
  or
  (area_role = 'MONITOR' and specialty in (
    'MUSICA','RADIO','PRODUCCIÓN','BARBERÍA','EMPRENDEDURISMO'
  ))
) not valid;

-- Completar primero la especialidad de Monitores anteriores que figure como
-- SIN ESPECIFICAR en la app. Los nuevos Monitores ya exigirán una opción.
