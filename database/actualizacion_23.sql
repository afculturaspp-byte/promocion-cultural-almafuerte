-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 23
-- Jornadas realizadas o canceladas, vinculadas al histórico de asistencia.

create table if not exists public.activity_journeys(
  id bigint generated always as identity primary key,
  activity_id bigint not null references public.activities(id) on delete cascade,
  journey_date date not null,
  cancelled boolean not null default false,
  cancellation_reason text,
  registered_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(activity_id,journey_date),
  constraint activity_journeys_cancellation_reason check(
    (cancelled and cancellation_reason in ('REQUISA','ALTERACIÓN','OTRO'))
    or (not cancelled and cancellation_reason is null)
  )
);

alter table public.activity_journeys enable row level security;
drop policy if exists activity_journeys_read on public.activity_journeys;
drop policy if exists activity_journeys_insert on public.activity_journeys;
drop policy if exists activity_journeys_update on public.activity_journeys;
drop policy if exists activity_journeys_delete on public.activity_journeys;
create policy activity_journeys_read on public.activity_journeys for select to authenticated using(public.is_active_user());
create policy activity_journeys_insert on public.activity_journeys for insert to authenticated with check(public.is_active_user());
create policy activity_journeys_update on public.activity_journeys for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy activity_journeys_delete on public.activity_journeys for delete to authenticated using(public.is_active_user());
grant select,insert,update,delete on public.activity_journeys to authenticated;
grant usage,select on sequence public.activity_journeys_id_seq to authenticated;

drop trigger if exists set_activity_journeys_updated on public.activity_journeys;
create trigger set_activity_journeys_updated before update on public.activity_journeys
for each row execute function public.set_updated_at();

drop trigger if exists audit_activity_journeys on public.activity_journeys;
create trigger audit_activity_journeys after insert or update or delete on public.activity_journeys
for each row execute function public.audit_change();

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

  if p_cancelled and normalized_reason not in ('REQUISA','ALTERACIÓN','OTRO') then
    raise exception 'SELECCIONÁ UN MOTIVO DE CANCELACIÓN VÁLIDO';
  end if;

  insert into public.activity_journeys(activity_id,journey_date,cancelled,cancellation_reason,registered_by)
  values(p_activity_id,p_journey_date,p_cancelled,case when p_cancelled then normalized_reason else null end,auth.uid())
  on conflict(activity_id,journey_date) do update
  set cancelled=excluded.cancelled,
      cancellation_reason=excluded.cancellation_reason,
      registered_by=auth.uid(),
      updated_at=now();

  if p_cancelled then
    insert into public.activity_attendance(activity_id,person_id,attendance_date,status,registered_by)
    select p_activity_id,participant.person_id,p_journey_date,'ausente',auth.uid()
    from public.activity_participants participant
    where participant.activity_id=p_activity_id
    on conflict(activity_id,person_id,attendance_date) do update
    set status='ausente',registered_by=auth.uid(),updated_at=now();
  else
    insert into public.activity_attendance(activity_id,person_id,attendance_date,status,registered_by)
    select p_activity_id,(record->>'person_id')::bigint,p_journey_date,lower(record->>'status'),auth.uid()
    from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) record
    join public.activity_participants participant
      on participant.activity_id=p_activity_id
     and participant.person_id=(record->>'person_id')::bigint
    where lower(record->>'status') in ('presente','ausente')
    on conflict(activity_id,person_id,attendance_date) do update
    set status=excluded.status,registered_by=auth.uid(),updated_at=now();
  end if;
end;
$$;

revoke all on function public.save_activity_journey(bigint,date,jsonb,boolean,text) from public;
grant execute on function public.save_activity_journey(bigint,date,jsonb,boolean,text) to authenticated;

notify pgrst, 'reload schema';
