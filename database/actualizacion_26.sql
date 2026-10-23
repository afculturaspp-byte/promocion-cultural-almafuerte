-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 26
-- Anotaciones del calendario y bajas individuales de PPLs desde Asistencia.

create table if not exists public.calendar_annotations(
  id bigint generated always as identity primary key,
  body text not null check (length(trim(body)) > 0),
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);
alter table public.calendar_annotations enable row level security;
drop policy if exists calendar_annotations_read on public.calendar_annotations;
drop policy if exists calendar_annotations_insert on public.calendar_annotations;
create policy calendar_annotations_read on public.calendar_annotations for select to authenticated using(public.is_active_user());
create policy calendar_annotations_insert on public.calendar_annotations for insert to authenticated with check(public.is_active_user() and created_by=auth.uid());
grant select,insert on public.calendar_annotations to authenticated;
grant usage,select on sequence public.calendar_annotations_id_seq to authenticated;

create table if not exists public.individual_removal_tickets(
  id bigint generated always as identity primary key,
  activity_id bigint not null references public.activities(id),
  person_id bigint not null references public.people(id),
  activity_title text not null,
  person_identifier text not null,
  person_last_name text not null,
  person_first_name text not null,
  person_location text,
  reason text not null check(reason in ('VOLUNTARIA','PROBLEMAS DE CONVIVENCIA','TRASLADO','SANCIÓN')),
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);
alter table public.individual_removal_tickets enable row level security;
drop policy if exists individual_removal_tickets_read on public.individual_removal_tickets;
create policy individual_removal_tickets_read on public.individual_removal_tickets for select to authenticated using(public.is_active_user());
grant select on public.individual_removal_tickets to authenticated;
grant usage,select on sequence public.individual_removal_tickets_id_seq to authenticated;

create or replace function public.require_activity_administrator()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if current_setting('app.individual_attendance_removal',true)='true' and tg_table_name='activity_participants' and tg_op='DELETE' then return old; end if;
  if not public.is_admin() then raise exception 'SOLO UN ADMINISTRADOR PUEDE MODIFICAR ACTIVIDADES'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.register_individual_activity_removal(
  p_activity_id bigint,
  p_person_id bigint,
  p_reason text
) returns void
language plpgsql security definer set search_path=public
as $$
declare person_row record; activity_row record; normalized_reason text:=upper(trim(p_reason));
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if normalized_reason not in ('VOLUNTARIA','PROBLEMAS DE CONVIVENCIA','TRASLADO','SANCIÓN') then raise exception 'SELECCIONÁ UN MOTIVO DE BAJA VÁLIDO'; end if;
  select p.id,p.identifier,p.last_name,p.first_name,p.location into person_row from public.activity_participants ap join public.people p on p.id=ap.person_id where ap.activity_id=p_activity_id and ap.person_id=p_person_id;
  if not found then raise exception 'LA PPL NO FORMA PARTE DE ESTA ACTIVIDAD'; end if;
  select id,title into activity_row from public.activities where id=p_activity_id and archived=false;
  if not found then raise exception 'ACTIVIDAD NO ENCONTRADA O ARCHIVADA'; end if;
  insert into public.individual_removal_tickets(activity_id,person_id,activity_title,person_identifier,person_last_name,person_first_name,person_location,reason,created_by)
  values(activity_row.id,person_row.id,upper(activity_row.title),person_row.identifier,upper(person_row.last_name),upper(person_row.first_name),upper(person_row.location),normalized_reason,auth.uid());
  perform set_config('app.individual_attendance_removal','true',true);
  delete from public.activity_participants where activity_id=p_activity_id and person_id=p_person_id;
end;
$$;
revoke all on function public.register_individual_activity_removal(bigint,bigint,text) from public;
grant execute on function public.register_individual_activity_removal(bigint,bigint,text) to authenticated;
notify pgrst, 'reload schema';
