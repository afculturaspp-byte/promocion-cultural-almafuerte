-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 34
-- Cambio de monitor con motivo y observaciones en los préstamos.

alter table public.instrument_loan_records
add column if not exists observations text;

create table if not exists public.activity_monitor_changes(
  id bigint generated always as identity primary key,
  activity_id bigint not null references public.activities(id) on delete cascade,
  previous_instructor text,
  new_instructor text not null,
  reason text not null,
  changed_by uuid not null default auth.uid() references public.profiles(id),
  changed_at timestamptz not null default now()
);

alter table public.activity_monitor_changes enable row level security;
drop policy if exists activity_monitor_changes_read on public.activity_monitor_changes;
create policy activity_monitor_changes_read on public.activity_monitor_changes
for select to authenticated using(public.is_active_user());
grant select on public.activity_monitor_changes to authenticated;
grant usage,select on sequence public.activity_monitor_changes_id_seq to authenticated;

create or replace function public.change_activity_monitor(
  p_activity_id bigint,
  p_new_instructor text,
  p_reason text
) returns void language plpgsql security definer set search_path=public as $$
declare previous_name text;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if coalesce(trim(p_new_instructor),'')='' then raise exception 'SELECCIONÁ EL MONITOR'; end if;
  select instructor into previous_name from public.activities
  where id=p_activity_id and status='activa' and archived=false for update;
  if not found then raise exception 'LA ACTIVIDAD NO ESTÁ DISPONIBLE'; end if;
  if coalesce(trim(previous_name),'')<>'' and coalesce(upper(trim(previous_name)),'')<>upper(trim(p_new_instructor)) then
    if coalesce(trim(p_reason),'')='' then raise exception 'INDICÁ EL MOTIVO DEL CAMBIO DE MONITOR'; end if;
    insert into public.activity_monitor_changes(activity_id,previous_instructor,new_instructor,reason)
    values(p_activity_id,upper(previous_name),upper(p_new_instructor),upper(p_reason));
  end if;
  update public.activities set instructor=upper(trim(p_new_instructor)),updated_at=now() where id=p_activity_id;
end;
$$;
revoke all on function public.change_activity_monitor(bigint,text,text) from public;
grant execute on function public.change_activity_monitor(bigint,text,text) to authenticated;

notify pgrst, 'reload schema';
