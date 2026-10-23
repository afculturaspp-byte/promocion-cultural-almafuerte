-- ACTUALIZACIÓN 02 · MAYÚSCULAS + MÓDULO ACTIVIDADES
-- Ejecutar en Supabase > SQL Editor sobre la base ya creada.

-- 1. Convertir a mayúsculas los datos existentes (no modifica correos ni contraseñas).
update public.profiles set full_name=upper(full_name);
update public.people set identifier=upper(identifier),last_name=upper(last_name),first_name=upper(first_name),location=upper(location),notes=upper(notes);
update public.workshops set name=upper(name),instructor=upper(instructor),schedule=upper(schedule),location=upper(location),description=upper(description);
update public.books set title=upper(title),author=upper(author),isbn=upper(isbn),code=upper(code),notes=upper(notes);
update public.instruments set name=upper(name),code=upper(code),condition=upper(condition),notes=upper(notes);

-- 2. Tablas del módulo Actividades.
create table if not exists public.activities (
  id bigint generated always as identity primary key,
  workshop_id bigint not null references public.workshops(id),
  title text not null,
  activity_date date not null default current_date,
  location text,
  notes text,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.activity_participants (
  id bigint generated always as identity primary key,
  activity_id bigint not null references public.activities(id) on delete cascade,
  person_id bigint not null references public.people(id),
  created_at timestamptz not null default now(),
  unique(activity_id,person_id)
);

create index if not exists activities_date_idx on public.activities(activity_date desc);
create index if not exists activity_participants_activity_idx on public.activity_participants(activity_id);

-- 3. Fuerza mayúsculas en las tablas, incluso si se cargan datos fuera de la aplicación.
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
      'code','condition','return_condition'
    ])
  loop
    payload := jsonb_set(payload,array[field_name],to_jsonb(upper(field_value)));
  end loop;
  new := jsonb_populate_record(new,payload);
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['profiles','people','workshops','books','instruments','book_loans','instrument_loans','activities']
  loop
    execute format('drop trigger if exists force_uppercase_%I on public.%I',t,t);
    execute format('create trigger force_uppercase_%I before insert or update on public.%I for each row execute function public.force_uppercase_fields()',t,t);
  end loop;
end $$;

-- 4. Crear una actividad y copiar automáticamente los integrantes activos del taller.
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
declare new_activity_id bigint;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;

  insert into public.activities(workshop_id,title,activity_date,location,notes,created_by)
  values(p_workshop_id,upper(p_title),p_activity_date,upper(p_location),upper(p_notes),auth.uid())
  returning id into new_activity_id;

  insert into public.activity_participants(activity_id,person_id)
  select new_activity_id,e.person_id
  from public.enrollments e
  where e.workshop_id=p_workshop_id and e.active=true;

  return new_activity_id;
end;
$$;

-- 5. Seguridad y auditoría.
alter table public.activities enable row level security;
alter table public.activity_participants enable row level security;

drop policy if exists activities_read on public.activities;
drop policy if exists activities_insert on public.activities;
drop policy if exists activities_update on public.activities;
drop policy if exists activities_delete_admin on public.activities;
create policy activities_read on public.activities for select to authenticated using(public.is_active_user());
create policy activities_insert on public.activities for insert to authenticated with check(public.is_active_user());
create policy activities_update on public.activities for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy activities_delete_admin on public.activities for delete to authenticated using(public.is_admin());

drop policy if exists activity_participants_read on public.activity_participants;
drop policy if exists activity_participants_insert on public.activity_participants;
drop policy if exists activity_participants_update on public.activity_participants;
drop policy if exists activity_participants_delete_admin on public.activity_participants;
create policy activity_participants_read on public.activity_participants for select to authenticated using(public.is_active_user());
create policy activity_participants_insert on public.activity_participants for insert to authenticated with check(public.is_active_user());
create policy activity_participants_update on public.activity_participants for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy activity_participants_delete_admin on public.activity_participants for delete to authenticated using(public.is_admin());

drop trigger if exists set_activities_updated on public.activities;
create trigger set_activities_updated before update on public.activities for each row execute function public.set_updated_at();
drop trigger if exists audit_activities on public.activities;
create trigger audit_activities after insert or update or delete on public.activities for each row execute function public.audit_change();
drop trigger if exists audit_activity_participants on public.activity_participants;
create trigger audit_activity_participants after insert or update or delete on public.activity_participants for each row execute function public.audit_change();

grant select,insert,update,delete on public.activities,public.activity_participants to authenticated;
grant usage,select on sequence public.activities_id_seq,public.activity_participants_id_seq to authenticated;
grant execute on function public.create_activity(bigint,text,date,text,text) to authenticated;
