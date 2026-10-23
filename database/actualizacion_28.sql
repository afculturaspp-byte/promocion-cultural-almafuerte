-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 28
-- Operadores: alta, baja y cambio de PPLs dentro de actividades.
-- La edición de las actividades, jornadas y horarios continúa limitada a Administración.

create or replace function public.require_activity_administrator()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if tg_table_name='activity_participants' and (
    current_setting('app.individual_attendance_removal',true)='true'
    or current_setting('app.activity_participant_management',true)='true'
  ) then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  if not public.is_admin() then raise exception 'SOLO UN ADMINISTRADOR PUEDE MODIFICAR ACTIVIDADES'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.add_activity_participant(
  p_activity_id bigint,p_identifier text,p_last_name text,p_first_name text,p_location text,p_notes text default null
) returns bigint language plpgsql security definer set search_path=public
as $$
declare person_key bigint;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if p_identifier !~ '^[0-9]+$' then raise exception 'EL PRONTUARIO DEBE SER NUMÉRICO'; end if;
  insert into public.people(identifier,last_name,first_name,location,notes,active)
  values(p_identifier,upper(p_last_name),upper(p_first_name),upper(p_location),upper(p_notes),true)
  on conflict(identifier) do update set last_name=excluded.last_name,first_name=excluded.first_name,location=excluded.location,notes=coalesce(excluded.notes,public.people.notes),active=true
  returning id into person_key;
  perform set_config('app.activity_participant_management','true',true);
  insert into public.activity_participants(activity_id,person_id) values(p_activity_id,person_key)
  on conflict(activity_id,person_id) do nothing;
  return person_key;
end;
$$;

create or replace function public.transfer_activity_participant(
  p_from_activity_id bigint,p_to_activity_id bigint,p_person_id bigint
) returns void language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if p_from_activity_id=p_to_activity_id then raise exception 'SELECCIONÁ UNA ACTIVIDAD DIFERENTE'; end if;
  if not exists(select 1 from public.activity_participants where activity_id=p_from_activity_id and person_id=p_person_id) then raise exception 'LA PPL NO FORMA PARTE DE LA ACTIVIDAD DE ORIGEN'; end if;
  if not exists(select 1 from public.activities where id=p_to_activity_id and status='activa' and archived=false) then raise exception 'LA ACTIVIDAD DE DESTINO NO ESTÁ DISPONIBLE'; end if;
  perform set_config('app.activity_participant_management','true',true);
  insert into public.activity_participants(activity_id,person_id) values(p_to_activity_id,p_person_id) on conflict(activity_id,person_id) do nothing;
  delete from public.activity_participants where activity_id=p_from_activity_id and person_id=p_person_id;
end;
$$;

create or replace function public.remove_activity_participant(
  p_activity_id bigint,p_person_id bigint,p_removal_type text,p_reason text default null
) returns void language plpgsql security definer set search_path=public
as $$
declare selected_person record; selected_activity record; normalized_type text:=upper(trim(p_removal_type)); normalized_reason text:=upper(trim(p_reason));
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if normalized_type not in ('ERROR_CARGA','OTRO_MOTIVO') then raise exception 'TIPO DE BAJA NO VÁLIDO'; end if;
  select person.id,person.identifier,person.last_name,person.first_name,person.location into selected_person from public.activity_participants participant join public.people person on person.id=participant.person_id where participant.activity_id=p_activity_id and participant.person_id=p_person_id;
  if not found then raise exception 'LA PPL NO FORMA PARTE DE ESTA ACTIVIDAD'; end if;
  select id,title into selected_activity from public.activities where id=p_activity_id and archived=false;
  if not found then raise exception 'ACTIVIDAD NO ENCONTRADA O ARCHIVADA'; end if;
  if normalized_type='OTRO_MOTIVO' then
    if normalized_reason is null or normalized_reason not in ('BAJA VOLUNTARIA','SANCIÓN','CAMBIO DE COMPLEJO','INASISTENCIAS REITERADAS') then raise exception 'SELECCIONÁ UN MOTIVO DE BAJA VÁLIDO'; end if;
    insert into public.participant_removal_tickets(activity_id,person_id,activity_title,person_identifier,person_last_name,person_first_name,person_location,reason,created_by)
    values(selected_activity.id,selected_person.id,upper(selected_activity.title),selected_person.identifier,upper(selected_person.last_name),upper(selected_person.first_name),upper(selected_person.location),normalized_reason,auth.uid());
  end if;
  perform set_config('app.activity_participant_management','true',true);
  delete from public.activity_participants where activity_id=p_activity_id and person_id=p_person_id;
end;
$$;

notify pgrst, 'reload schema';
