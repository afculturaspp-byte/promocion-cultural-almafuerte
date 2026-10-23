-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 35
-- Los operadores habilitados pueden gestionar las actividades:
-- crear, editar, finalizar, archivar, reactivar y eliminar.
-- La administración de usuarios sigue siendo exclusiva de administradores.

create or replace function public.require_activity_administrator()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_active_user() then
    raise exception 'USUARIO NO HABILITADO';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

notify pgrst, 'reload schema';
