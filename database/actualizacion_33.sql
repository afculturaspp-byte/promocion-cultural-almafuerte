-- BÚSQUEDA REMOTA DE PPLs DESDE CULTURA
create table if not exists public.ppl_lookup_requests (
  id bigint generated always as identity primary key,
  requested_by uuid not null default auth.uid() references public.profiles(id),
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'PENDIENTE' check(status in ('PENDIENTE','EN PROCESO','COMPLETADA','ERROR')),
  last_name text not null default '%', first_name text not null default '%', identifier text,
  results jsonb not null default '[]'::jsonb, error_message text
);
alter table public.ppl_lookup_requests enable row level security;
drop policy if exists ppl_lookup_requests_read on public.ppl_lookup_requests;
create policy ppl_lookup_requests_read on public.ppl_lookup_requests for select to authenticated using(requested_by=auth.uid() or public.is_admin());
grant select on public.ppl_lookup_requests to authenticated;
grant usage,select on sequence public.ppl_lookup_requests_id_seq to authenticated;

create or replace function public.request_ppl_lookup(p_last_name text default '%',p_first_name text default '%',p_identifier text default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare key bigint;
begin
 if not public.is_active_user() then raise exception 'USUARIO SIN ACCESO'; end if;
 if coalesce(trim(p_identifier),'')='' and coalesce(trim(p_last_name),'')='' and coalesce(trim(p_first_name),'')='' then raise exception 'INGRESÁ APELLIDO, NOMBRE O NÚMERO'; end if;
 insert into public.ppl_lookup_requests(last_name,first_name,identifier)
 values(coalesce(nullif(upper(trim(p_last_name)),''),'%'),coalesce(nullif(upper(trim(p_first_name)),''),'%'),nullif(regexp_replace(coalesce(p_identifier,''),'[^0-9]','','g'),'')) returning id into key;
 return key;
end; $$;
revoke all on function public.request_ppl_lookup(text,text,text) from public;
grant execute on function public.request_ppl_lookup(text,text,text) to authenticated;

create or replace function public.complete_ppl_lookup(p_request_id bigint,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.role()<>'service_role' then raise exception 'SOLO EL CONECTOR INSTITUCIONAL PUEDE COMPLETAR BÚSQUEDAS'; end if;
 update public.ppl_lookup_requests set status='COMPLETADA',completed_at=now(),results=coalesce(p_results,'[]'::jsonb),error_message=null where id=p_request_id;
end; $$;
revoke all on function public.complete_ppl_lookup(bigint,jsonb) from public;
grant execute on function public.complete_ppl_lookup(bigint,jsonb) to service_role;
notify pgrst, 'reload schema';
