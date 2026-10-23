-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 31
-- Reparación de la función de sincronización PPLs (ejecutar después del intento de la 30).

alter table public.people add column if not exists source_system text;
alter table public.people add column if not exists source_location text;
alter table public.people add column if not exists source_synced_at timestamptz;

create table if not exists public.ppl_sync_requests (
  id bigint generated always as identity primary key,
  status text not null default 'PENDIENTE' check(status in ('PENDIENTE','EN PROCESO','COMPLETADA','ERROR')),
  requested_at timestamptz not null default now(),
  requested_by uuid not null default auth.uid() references public.profiles(id),
  started_at timestamptz, completed_at timestamptz, error_message text
);
create table if not exists public.ppl_sync_runs (
  id bigint generated always as identity primary key,
  request_id bigint references public.ppl_sync_requests(id) on delete set null,
  status text not null check(status in ('COMPLETADA','ERROR')),
  started_at timestamptz not null default now(), completed_at timestamptz,
  source_count integer not null default 0, inserted_count integer not null default 0,
  updated_count integer not null default 0, error_message text
);
alter table public.ppl_sync_requests enable row level security;
alter table public.ppl_sync_runs enable row level security;
drop policy if exists ppl_sync_requests_read on public.ppl_sync_requests;
drop policy if exists ppl_sync_runs_read on public.ppl_sync_runs;
create policy ppl_sync_requests_read on public.ppl_sync_requests for select to authenticated using(public.is_admin());
create policy ppl_sync_runs_read on public.ppl_sync_runs for select to authenticated using(public.is_admin());
grant select on public.ppl_sync_requests,ppl_sync_runs to authenticated;
grant usage,select on sequence public.ppl_sync_requests_id_seq,public.ppl_sync_runs_id_seq to authenticated;

create or replace function public.request_ppl_sync()
returns bigint language plpgsql security definer set search_path=public
as $$
declare request_key bigint;
begin
  if not public.is_active_user() or not public.is_admin() then raise exception 'SOLO UN ADMINISTRADOR PUEDE SOLICITAR LA SINCRONIZACIÓN'; end if;
  select id into request_key from public.ppl_sync_requests where status in ('PENDIENTE','EN PROCESO') order by requested_at desc limit 1;
  if request_key is not null then return request_key; end if;
  insert into public.ppl_sync_requests(requested_by) values(auth.uid()) returning id into request_key;
  return request_key;
end;
$$;
revoke all on function public.request_ppl_sync() from public;
grant execute on function public.request_ppl_sync() to authenticated;

create or replace function public.sync_ppl_snapshot(p_people jsonb,p_request_id bigint default null)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare run_key bigint; source_total integer; existing_total integer; normalized jsonb;
begin
  if auth.role()<>'service_role' then raise exception 'SOLO EL CONECTOR INSTITUCIONAL PUEDE EJECUTAR LA SINCRONIZACIÓN'; end if;
  if jsonb_typeof(p_people)<>'array' or jsonb_array_length(p_people)=0 then raise exception 'EL PADRÓN RECIBIDO ESTÁ VACÍO'; end if;
  with incoming as (
    select regexp_replace(coalesce(item.identifier,''),'[^0-9]','','g') as identifier,
      upper(trim(coalesce(item.last_name,''))) as last_name,
      upper(trim(coalesce(item.first_name,''))) as first_name,
      upper(trim(coalesce(item.source_location,''))) as source_location
    from jsonb_to_recordset(p_people) as item(identifier text,last_name text,first_name text,source_location text)
  ), source_rows as (
    select distinct on (identifier) identifier,last_name,first_name,source_location
    from incoming
    where identifier<>'' and last_name<>'' and first_name<>''
    order by identifier
  )
  select coalesce(jsonb_agg(jsonb_build_object('identifier',identifier,'last_name',last_name,'first_name',first_name,'source_location',source_location)),'[]'::jsonb)
  into normalized from source_rows;
  source_total:=jsonb_array_length(normalized);
  if source_total=0 then raise exception 'EL PADRÓN NO CONTIENE PPLs VÁLIDAS'; end if;
  select count(*) into existing_total
  from public.people person join jsonb_to_recordset(normalized) as item(identifier text,last_name text,first_name text,source_location text) on item.identifier=person.identifier;
  if p_request_id is not null then update public.ppl_sync_requests set status='EN PROCESO',started_at=now(),error_message=null where id=p_request_id and status='PENDIENTE'; end if;
  insert into public.ppl_sync_runs(request_id,status,source_count,inserted_count,updated_count)
  values(p_request_id,'COMPLETADA',source_total,source_total-existing_total,existing_total) returning id into run_key;
  insert into public.people(identifier,last_name,first_name,location,active,source_system,source_location,source_synced_at)
  select item.identifier,item.last_name,item.first_name,
    case when item.source_location in ('ALMAFUERTE - ADMISIÓN','ALMAFUERTE - ADMISION') then 'ADMISIÓN' else 'SIN UBICACIÓN ACTUAL' end,
    true,'CONSULTAS GENERALES',item.source_location,now()
  from jsonb_to_recordset(normalized) as item(identifier text,last_name text,first_name text,source_location text)
  on conflict(identifier) do update set last_name=excluded.last_name,first_name=excluded.first_name,location=excluded.location,active=true,source_system=excluded.source_system,source_location=excluded.source_location,source_synced_at=excluded.source_synced_at;
  update public.ppl_sync_runs set completed_at=now() where id=run_key;
  if p_request_id is not null then update public.ppl_sync_requests set status='COMPLETADA',completed_at=now() where id=p_request_id; end if;
  return jsonb_build_object('run_id',run_key,'source_count',source_total,'inserted_count',source_total-existing_total,'updated_count',existing_total);
exception when others then
  if run_key is not null then update public.ppl_sync_runs set status='ERROR',completed_at=now(),error_message=sqlerrm where id=run_key; end if;
  if p_request_id is not null then update public.ppl_sync_requests set status='ERROR',completed_at=now(),error_message=sqlerrm where id=p_request_id; end if;
  raise;
end;
$$;
revoke all on function public.sync_ppl_snapshot(jsonb,bigint) from public;
grant execute on function public.sync_ppl_snapshot(jsonb,bigint) to service_role;

create or replace function public.fail_ppl_sync_request(p_request_id bigint,p_error text)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SOLO EL CONECTOR INSTITUCIONAL PUEDE ACTUALIZAR ESTA SOLICITUD'; end if;
  update public.ppl_sync_requests set status='ERROR',completed_at=now(),error_message=left(coalesce(p_error,'ERROR DE SINCRONIZACIÓN'),1000) where id=p_request_id and status in ('PENDIENTE','EN PROCESO');
end;
$$;
revoke all on function public.fail_ppl_sync_request(bigint,text) from public;
grant execute on function public.fail_ppl_sync_request(bigint,text) to service_role;

notify pgrst, 'reload schema';
