-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 27
-- Transferencia de una PPL entre actividades sin duplicar su registro personal.

create or replace function public.transfer_activity_participant(
  p_from_activity_id bigint,
  p_to_activity_id bigint,
  p_person_id bigint
) returns void
language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_active_user() or not public.is_admin() then
    raise exception 'SOLO UN ADMINISTRADOR PUEDE CAMBIAR UNA PPL DE ACTIVIDAD';
  end if;
  if p_from_activity_id=p_to_activity_id then
    raise exception 'SELECCIONÁ UNA ACTIVIDAD DIFERENTE';
  end if;
  if not exists(select 1 from public.activity_participants where activity_id=p_from_activity_id and person_id=p_person_id) then
    raise exception 'LA PPL NO FORMA PARTE DE LA ACTIVIDAD DE ORIGEN';
  end if;
  if not exists(select 1 from public.activities where id=p_to_activity_id and status='activa' and archived=false) then
    raise exception 'LA ACTIVIDAD DE DESTINO NO ESTÁ DISPONIBLE';
  end if;
  insert into public.activity_participants(activity_id,person_id)
  values(p_to_activity_id,p_person_id)
  on conflict(activity_id,person_id) do nothing;
  delete from public.activity_participants
  where activity_id=p_from_activity_id and person_id=p_person_id;
end;
$$;
revoke all on function public.transfer_activity_participant(bigint,bigint,bigint) from public;
grant execute on function public.transfer_activity_participant(bigint,bigint,bigint) to authenticated;
notify pgrst, 'reload schema';
