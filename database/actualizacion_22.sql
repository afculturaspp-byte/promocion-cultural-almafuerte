-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 22
-- Renombra la actividad BARBERÍA y conserva la denominación en los historiales.

update public.activities
set title='PELUQUERÍA Y BARBERÍA'
where upper(trim(title)) in ('BARBERIA','BARBERÍA');

do $$
begin
  if to_regclass('public.participant_removal_tickets') is not null then
    update public.participant_removal_tickets
    set activity_title='PELUQUERÍA Y BARBERÍA'
    where upper(trim(activity_title)) in ('BARBERIA','BARBERÍA');
  end if;
end;
$$;

notify pgrst, 'reload schema';
