-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 17
-- Préstamos vinculados al Inventario.
-- La agrupación visual de Actividades no modifica la base de datos.

alter table public.instrument_loan_records
add column if not exists inventory_item_id bigint
references public.inventory_items(id) on delete restrict;

create index if not exists instrument_loan_records_inventory_idx
on public.instrument_loan_records(inventory_item_id);

-- Garantiza que el elemento elegido exista en Inventario y sea un INSTRUMENTO.
-- El nombre se copia automáticamente para conservar el historial del préstamo.
create or replace function public.sync_instrument_loan_inventory()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  selected_name text;
begin
  if new.inventory_item_id is null then
    return new;
  end if;

  select name into selected_name
  from public.inventory_items
  where id=new.inventory_item_id and category='INSTRUMENTO';

  if selected_name is null then
    raise exception 'EL ELEMENTO SELECCIONADO NO ES UN INSTRUMENTO DEL INVENTARIO';
  end if;

  new.instrument_name=upper(selected_name);
  return new;
end;
$$;

drop trigger if exists sync_instrument_loan_inventory on public.instrument_loan_records;
create trigger sync_instrument_loan_inventory
before insert or update of inventory_item_id on public.instrument_loan_records
for each row execute function public.sync_instrument_loan_inventory();

-- Los registros anteriores permanecen válidos aunque todavía no tengan vínculo.
-- Todo préstamo nuevo creado desde la aplicación exige seleccionar Inventario.
