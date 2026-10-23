-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 24
-- Los operadores registran asistencia, pero no pueden crear, editar,
-- finalizar, archivar, reactivar ni modificar integrantes/horarios de actividades.

create or replace function public.require_activity_administrator()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then
    raise exception 'SOLO UN ADMINISTRADOR PUEDE MODIFICAR ACTIVIDADES';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists activity_admin_only on public.activities;
create trigger activity_admin_only
before insert or update or delete on public.activities
for each row execute function public.require_activity_administrator();

drop trigger if exists activity_schedules_admin_only on public.activity_schedules;
create trigger activity_schedules_admin_only
before insert or update or delete on public.activity_schedules
for each row execute function public.require_activity_administrator();

drop trigger if exists activity_participants_admin_only on public.activity_participants;
create trigger activity_participants_admin_only
before insert or update or delete on public.activity_participants
for each row execute function public.require_activity_administrator();

notify pgrst, 'reload schema';
