-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 14
-- Archivo de Actividades, nuevo préstamo de Instrumentos e Inventario.

-- 1. Eliminación definitiva exclusivamente desde el Archivo de Actividades.
create or replace function public.delete_archived_activity(p_activity_id bigint)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  delete from public.activities where id=p_activity_id and archived=true;
  if not found then raise exception 'LA ACTIVIDAD NO EXISTE O NO ESTÁ ARCHIVADA'; end if;
end;
$$;
grant execute on function public.delete_archived_activity(bigint) to authenticated;

-- 2. Préstamos de Instrumentos con la misma lógica simple de Biblioteca.
create table if not exists public.instrument_loan_records(
  id bigint generated always as identity primary key,
  instrument_name text not null,
  details text,
  ppl_name text not null,
  location text,
  received_at date not null default current_date,
  renewal text,
  returned_at date,
  source_loan_id bigint unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(location is null or location ~ '^MÓDULO [1-6] - ALA [1-4]$')
);

insert into public.instrument_loan_records(instrument_name,details,ppl_name,location,received_at,renewal,returned_at,source_loan_id)
select instrument.name,instrument.condition,person.last_name || ', ' || person.first_name,
       case when person.location ~ '^MÓDULO [1-6] - ALA [1-4]$' then person.location else null end,
       loan.delivered_at,loan.due_at::text,loan.returned_at,loan.id
from public.instrument_loans loan
join public.instruments instrument on instrument.id=loan.instrument_id
join public.people person on person.id=loan.person_id
on conflict(source_loan_id) do nothing;

alter table public.instrument_loan_records enable row level security;
drop policy if exists instrument_loan_records_read on public.instrument_loan_records;
drop policy if exists instrument_loan_records_insert on public.instrument_loan_records;
drop policy if exists instrument_loan_records_update on public.instrument_loan_records;
drop policy if exists instrument_loan_records_delete on public.instrument_loan_records;
create policy instrument_loan_records_read on public.instrument_loan_records for select to authenticated using(public.is_active_user());
create policy instrument_loan_records_insert on public.instrument_loan_records for insert to authenticated with check(public.is_active_user());
create policy instrument_loan_records_update on public.instrument_loan_records for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy instrument_loan_records_delete on public.instrument_loan_records for delete to authenticated using(public.is_active_user());
grant select,insert,update,delete on public.instrument_loan_records to authenticated;
grant usage,select on sequence public.instrument_loan_records_id_seq to authenticated;
drop trigger if exists set_instrument_loan_records_updated on public.instrument_loan_records;
create trigger set_instrument_loan_records_updated before update on public.instrument_loan_records for each row execute function public.set_updated_at();
drop trigger if exists audit_instrument_loan_records on public.instrument_loan_records;
create trigger audit_instrument_loan_records after insert or update or delete on public.instrument_loan_records for each row execute function public.audit_change();

-- 3. Inventario general inicial.
create table if not exists public.inventory_items(
  id bigint generated always as identity primary key,
  category text not null check(category in ('INSTRUMENTO','CABLE','MOBILIARIO','EQUIPO','OTRO')),
  name text not null,
  quantity integer not null default 1 check(quantity>0),
  condition text,
  location text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(location is null or location ~ '^MÓDULO [1-6] - ALA [1-4]$')
);

alter table public.inventory_items enable row level security;
drop policy if exists inventory_items_read on public.inventory_items;
drop policy if exists inventory_items_insert on public.inventory_items;
drop policy if exists inventory_items_update on public.inventory_items;
drop policy if exists inventory_items_delete on public.inventory_items;
create policy inventory_items_read on public.inventory_items for select to authenticated using(public.is_active_user());
create policy inventory_items_insert on public.inventory_items for insert to authenticated with check(public.is_active_user());
create policy inventory_items_update on public.inventory_items for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy inventory_items_delete on public.inventory_items for delete to authenticated using(public.is_active_user());
grant select,insert,update,delete on public.inventory_items to authenticated;
grant usage,select on sequence public.inventory_items_id_seq to authenticated;
drop trigger if exists set_inventory_items_updated on public.inventory_items;
create trigger set_inventory_items_updated before update on public.inventory_items for each row execute function public.set_updated_at();
drop trigger if exists audit_inventory_items on public.inventory_items;
create trigger audit_inventory_items after insert or update or delete on public.inventory_items for each row execute function public.audit_change();

create or replace function public.force_uppercase_cultural_assets() returns trigger language plpgsql as $$
begin
  if tg_table_name='instrument_loan_records' then
    new.instrument_name=upper(new.instrument_name);new.details=upper(new.details);
    new.ppl_name=upper(new.ppl_name);new.location=upper(new.location);new.renewal=upper(new.renewal);
  else
    new.category=upper(new.category);new.name=upper(new.name);new.condition=upper(new.condition);
    new.location=upper(new.location);new.notes=upper(new.notes);
  end if;
  return new;
end;
$$;
drop trigger if exists force_uppercase_instrument_loan_records on public.instrument_loan_records;
create trigger force_uppercase_instrument_loan_records before insert or update on public.instrument_loan_records for each row execute function public.force_uppercase_cultural_assets();
drop trigger if exists force_uppercase_inventory_items on public.inventory_items;
create trigger force_uppercase_inventory_items before insert or update on public.inventory_items for each row execute function public.force_uppercase_cultural_assets();
