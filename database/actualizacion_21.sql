-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 21
-- Corrección para la tabla de tickets de bajas y recarga del esquema de Supabase.

create table if not exists public.participant_removal_tickets(
  id bigint generated always as identity primary key,
  activity_id bigint references public.activities(id) on delete set null,
  person_id bigint references public.people(id) on delete set null,
  activity_title text not null,
  person_identifier text not null,
  person_last_name text not null,
  person_first_name text not null,
  person_location text,
  reason text not null check(reason in ('BAJA VOLUNTARIA','SANCIÓN','CAMBIO DE COMPLEJO')),
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists participant_removal_tickets_date_idx
on public.participant_removal_tickets(created_at desc);

create index if not exists participant_removal_tickets_person_idx
on public.participant_removal_tickets(person_identifier,created_at desc);

alter table public.participant_removal_tickets enable row level security;

drop policy if exists participant_removal_tickets_read
on public.participant_removal_tickets;

create policy participant_removal_tickets_read
on public.participant_removal_tickets for select to authenticated
using(public.is_active_user());

grant select on public.participant_removal_tickets to authenticated;
grant usage,select on sequence public.participant_removal_tickets_id_seq to authenticated;

drop trigger if exists audit_participant_removal_tickets
on public.participant_removal_tickets;

create trigger audit_participant_removal_tickets
after insert or update or delete on public.participant_removal_tickets
for each row execute function public.audit_change();

create or replace function public.remove_activity_participant(
  p_activity_id bigint,
  p_person_id bigint,
  p_removal_type text,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  selected_person record;
  selected_activity record;
  normalized_type text:=upper(trim(p_removal_type));
  normalized_reason text:=upper(trim(p_reason));
begin
  if not public.is_active_user() then
    raise exception 'USUARIO NO HABILITADO';
  end if;

  if normalized_type not in ('ERROR_CARGA','OTRO_MOTIVO') then
    raise exception 'TIPO DE BAJA NO VÁLIDO';
  end if;

  select person.id,person.identifier,person.last_name,person.first_name,person.location
  into selected_person
  from public.activity_participants participant
  join public.people person on person.id=participant.person_id
  where participant.activity_id=p_activity_id and participant.person_id=p_person_id;

  if not found then
    raise exception 'LA PPL NO FORMA PARTE DE ESTA ACTIVIDAD';
  end if;

  select id,title into selected_activity
  from public.activities
  where id=p_activity_id and archived=false;

  if not found then
    raise exception 'ACTIVIDAD NO ENCONTRADA O ARCHIVADA';
  end if;

  if normalized_type='OTRO_MOTIVO' then
    if normalized_reason is null or normalized_reason not in ('BAJA VOLUNTARIA','SANCIÓN','CAMBIO DE COMPLEJO') then
      raise exception 'SELECCIONÁ UN MOTIVO DE BAJA VÁLIDO';
    end if;

    insert into public.participant_removal_tickets(
      activity_id,person_id,activity_title,person_identifier,
      person_last_name,person_first_name,person_location,reason,created_by
    ) values(
      selected_activity.id,selected_person.id,upper(selected_activity.title),selected_person.identifier,
      upper(selected_person.last_name),upper(selected_person.first_name),upper(selected_person.location),
      normalized_reason,auth.uid()
    );
  end if;

  delete from public.activity_participants
  where activity_id=p_activity_id and person_id=p_person_id;
end;
$$;

revoke all on function public.remove_activity_participant(bigint,bigint,text,text) from public;
grant execute on function public.remove_activity_participant(bigint,bigint,text,text) to authenticated;

-- Solicita a PostgREST que reconozca inmediatamente la tabla y la función.
notify pgrst, 'reload schema';

