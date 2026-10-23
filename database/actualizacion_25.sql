-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 25
-- Nuevo motivo de cancelación y baja automática por ausencias reiteradas.

alter table public.activity_journeys
  drop constraint if exists activity_journeys_cancellation_reason;

alter table public.activity_journeys
  add constraint activity_journeys_cancellation_reason check (
    (cancelled and cancellation_reason in ('REQUISA','ALTERACIÓN','AUSENCIA DEL MONITOR','OTRO'))
    or (not cancelled and cancellation_reason is null)
  );

create or replace function public.save_activity_journey(
  p_activity_id bigint,
  p_journey_date date,
  p_records jsonb default '[]'::jsonb,
  p_cancelled boolean default false,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  normalized_reason text:=upper(nullif(trim(p_reason),''));
begin
  if not public.is_active_user() then
    raise exception 'USUARIO NO HABILITADO';
  end if;
  if not exists(select 1 from public.activities where id=p_activity_id and archived=false) then
    raise exception 'ACTIVIDAD NO ENCONTRADA O ARCHIVADA';
  end if;
  if p_cancelled and normalized_reason not in ('REQUISA','ALTERACIÓN','AUSENCIA DEL MONITOR','OTRO') then
    raise exception 'SELECCIONÁ UN MOTIVO DE CANCELACIÓN VÁLIDO';
  end if;
  insert into public.activity_journeys(activity_id,journey_date,cancelled,cancellation_reason,registered_by)
  values(p_activity_id,p_journey_date,p_cancelled,case when p_cancelled then normalized_reason else null end,auth.uid())
  on conflict(activity_id,journey_date) do update set cancelled=excluded.cancelled,cancellation_reason=excluded.cancellation_reason,registered_by=auth.uid(),updated_at=now();
  if p_cancelled then
    insert into public.activity_attendance(activity_id,person_id,attendance_date,status,registered_by)
    select p_activity_id,participant.person_id,p_journey_date,'ausente',auth.uid() from public.activity_participants participant where participant.activity_id=p_activity_id
    on conflict(activity_id,person_id,attendance_date) do update set status='ausente',registered_by=auth.uid(),updated_at=now();
  else
    insert into public.activity_attendance(activity_id,person_id,attendance_date,status,registered_by)
    select p_activity_id,(record->>'person_id')::bigint,p_journey_date,lower(record->>'status'),auth.uid()
    from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) record join public.activity_participants participant on participant.activity_id=p_activity_id and participant.person_id=(record->>'person_id')::bigint
    where lower(record->>'status') in ('presente','ausente')
    on conflict(activity_id,person_id,attendance_date) do update set status=excluded.status,registered_by=auth.uid(),updated_at=now();
  end if;
end;
$$;

create or replace function public.remove_activity_participant(
  p_activity_id bigint,
  p_person_id bigint,
  p_removal_type text,
  p_reason text default null
) returns void
language plpgsql security definer set search_path=public
as $$
declare selected_person record; selected_activity record; normalized_type text:=upper(trim(p_removal_type)); normalized_reason text:=upper(trim(p_reason));
begin
  if not public.is_active_user() or not public.is_admin() then raise exception 'SOLO UN ADMINISTRADOR PUEDE DAR DE BAJA A UNA PPL'; end if;
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
  delete from public.activity_participants where activity_id=p_activity_id and person_id=p_person_id;
end;
$$;

revoke all on function public.save_activity_journey(bigint,date,jsonb,boolean,text) from public;
grant execute on function public.save_activity_journey(bigint,date,jsonb,boolean,text) to authenticated;
revoke all on function public.remove_activity_participant(bigint,bigint,text,text) from public;
grant execute on function public.remove_activity_participant(bigint,bigint,text,text) to authenticated;
notify pgrst, 'reload schema';
