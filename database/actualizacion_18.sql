-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 18
-- Número de serie o CUPI opcional para los elementos del Inventario.

alter table public.inventory_items
add column if not exists serial_cupi text;

create or replace function public.normalize_inventory_serial_cupi()
returns trigger language plpgsql as $$
begin
  new.serial_cupi=nullif(upper(trim(new.serial_cupi)),'');
  return new;
end;
$$;

drop trigger if exists normalize_inventory_serial_cupi on public.inventory_items;
create trigger normalize_inventory_serial_cupi
before insert or update of serial_cupi on public.inventory_items
for each row execute function public.normalize_inventory_serial_cupi();

-- El campo puede quedar vacío y no se exige que sea único.
