-- PROMOCIÓN CULTURAL · ACTUALIZACIÓN 09
-- Fusión de Talleres y Actividades, asistencia diaria e importación de Biblioteca.

-- 1. Actividades como módulo principal.
alter table public.activities alter column workshop_id drop not null;
alter table public.activities add column if not exists instructor text;
alter table public.activities add column if not exists capacity integer check(capacity is null or capacity>0);
alter table public.activities add column if not exists description text;

update public.activities activity
set instructor=coalesce(activity.instructor,workshop.instructor),
    capacity=coalesce(activity.capacity,workshop.capacity),
    description=coalesce(activity.description,workshop.description)
from public.workshops workshop
where activity.workshop_id=workshop.id;

with migrated as (
  insert into public.activities(workshop_id,title,activity_date,location,notes,created_by,status,archived,instructor,capacity,description)
  select workshop.id,upper(workshop.name),current_date,'SALON',null,
         coalesce((select id from public.profiles where role='administrador' order by created_at limit 1),(select id from public.profiles order by created_at limit 1)),
         case when workshop.status='finalizado' then 'finalizada' else 'activa' end,
         false,workshop.instructor,workshop.capacity,workshop.description
  from public.workshops workshop
  where not exists(select 1 from public.activities activity where activity.workshop_id=workshop.id)
  returning id,workshop_id
)
insert into public.activity_participants(activity_id,person_id)
select migrated.id,enrollment.person_id
from migrated
join public.enrollments enrollment on enrollment.workshop_id=migrated.workshop_id and enrollment.active=true
on conflict do nothing;

create or replace function public.create_cultural_activity(
  p_title text,
  p_instructor text default null,
  p_capacity integer default null,
  p_location text default null,
  p_description text default null,
  p_schedules jsonb default '[]'::jsonb
) returns bigint language plpgsql security definer set search_path=public as $$
declare new_activity_id bigint;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if jsonb_array_length(p_schedules)=0 then raise exception 'DEBÉS CARGAR AL MENOS UN DÍA Y HORARIO'; end if;
  insert into public.activities(workshop_id,title,activity_date,location,created_by,status,archived,instructor,capacity,description)
  values(null,upper(p_title),current_date,upper(p_location),auth.uid(),'activa',false,upper(p_instructor),p_capacity,upper(p_description))
  returning id into new_activity_id;
  insert into public.activity_schedules(activity_id,day_of_week,start_time)
  select new_activity_id,upper(item.day_of_week),item.start_time::time
  from jsonb_to_recordset(p_schedules) as item(day_of_week text,start_time text);
  return new_activity_id;
end; $$;
grant execute on function public.create_cultural_activity(text,text,integer,text,text,jsonb) to authenticated;

create or replace function public.add_activity_participant(
  p_activity_id bigint,p_identifier text,p_last_name text,p_first_name text,p_location text,p_notes text default null
) returns bigint language plpgsql security definer set search_path=public as $$
declare person_key bigint;
begin
  if not public.is_active_user() then raise exception 'USUARIO NO HABILITADO'; end if;
  if p_identifier !~ '^[0-9]+$' then raise exception 'EL PRONTUARIO DEBE SER NUMÉRICO'; end if;
  insert into public.people(identifier,last_name,first_name,location,notes,active)
  values(p_identifier,upper(p_last_name),upper(p_first_name),upper(p_location),upper(p_notes),true)
  on conflict(identifier) do update set last_name=excluded.last_name,first_name=excluded.first_name,location=excluded.location,notes=coalesce(excluded.notes,public.people.notes),active=true
  returning id into person_key;
  insert into public.activity_participants(activity_id,person_id) values(p_activity_id,person_key)
  on conflict(activity_id,person_id) do nothing;
  return person_key;
end; $$;
grant execute on function public.add_activity_participant(bigint,text,text,text,text,text) to authenticated;

-- 2. Asistencia diaria vinculada directamente a Actividades.
create table if not exists public.activity_attendance(
  id bigint generated always as identity primary key,
  activity_id bigint not null references public.activities(id) on delete cascade,
  person_id bigint not null references public.people(id),
  attendance_date date not null,
  status text not null check(status in ('presente','ausente')),
  registered_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  unique(activity_id,person_id,attendance_date)
);
alter table public.activity_attendance enable row level security;
drop policy if exists activity_attendance_read on public.activity_attendance;
drop policy if exists activity_attendance_insert on public.activity_attendance;
drop policy if exists activity_attendance_update on public.activity_attendance;
drop policy if exists activity_attendance_delete on public.activity_attendance;
create policy activity_attendance_read on public.activity_attendance for select to authenticated using(public.is_active_user());
create policy activity_attendance_insert on public.activity_attendance for insert to authenticated with check(public.is_active_user());
create policy activity_attendance_update on public.activity_attendance for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy activity_attendance_delete on public.activity_attendance for delete to authenticated using(public.is_active_user());
grant select,insert,update,delete on public.activity_attendance to authenticated;
grant usage,select on sequence public.activity_attendance_id_seq to authenticated;
drop trigger if exists set_activity_attendance_updated on public.activity_attendance;
create trigger set_activity_attendance_updated before update on public.activity_attendance for each row execute function public.set_updated_at();
drop trigger if exists audit_activity_attendance on public.activity_attendance;
create trigger audit_activity_attendance after insert or update or delete on public.activity_attendance for each row execute function public.audit_change();

-- 3. Biblioteca según el formato del Excel suministrado.
create table if not exists public.library_records(
  id bigint generated always as identity primary key,
  title text not null,authors text,ppl_name text not null,module text,
  received_at date,renewal text,returned_at date,
  source_file text,source_row integer,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  unique(source_file,source_row)
);
alter table public.library_records enable row level security;
drop policy if exists library_records_read on public.library_records;
drop policy if exists library_records_insert on public.library_records;
drop policy if exists library_records_update on public.library_records;
drop policy if exists library_records_delete on public.library_records;
create policy library_records_read on public.library_records for select to authenticated using(public.is_active_user());
create policy library_records_insert on public.library_records for insert to authenticated with check(public.is_active_user());
create policy library_records_update on public.library_records for update to authenticated using(public.is_active_user()) with check(public.is_active_user());
create policy library_records_delete on public.library_records for delete to authenticated using(public.is_active_user());
grant select,insert,update,delete on public.library_records to authenticated;
grant usage,select on sequence public.library_records_id_seq to authenticated;
drop trigger if exists set_library_records_updated on public.library_records;
create trigger set_library_records_updated before update on public.library_records for each row execute function public.set_updated_at();
drop trigger if exists audit_library_records on public.library_records;
create trigger audit_library_records after insert or update or delete on public.library_records for each row execute function public.audit_change();

create or replace function public.force_uppercase_library_record() returns trigger language plpgsql as $$
begin
  new.title=upper(new.title);new.authors=upper(new.authors);new.ppl_name=upper(new.ppl_name);
  new.module=upper(new.module);new.renewal=upper(new.renewal);return new;
end; $$;
drop trigger if exists force_uppercase_library_records on public.library_records;
create trigger force_uppercase_library_records before insert or update on public.library_records for each row execute function public.force_uppercase_library_record();

insert into public.library_records(title,authors,ppl_name,module,received_at,renewal,returned_at,source_file,source_row) values
('El vengador','a j quinnell','Rojas Lucas','2.4','2025-11-10',null,'2025-12-01','Biblioteca control 15-09-25.xlsx',2),
('El pidding de navidad','agatha christie','Gonzalez Ortego, ivan','4.4','2025-11-25',null,null,'Biblioteca control 15-09-25.xlsx',3),
('Navidades Tragicas','agatha christie','Gonzalez Ortego, ivan','4.4','2025-11-25',null,null,'Biblioteca control 15-09-25.xlsx',4),
('Poirot Infringe la ley','agatha christie','Gonzalez Ortego, ivan','4.4','2025-11-25',null,null,'Biblioteca control 15-09-25.xlsx',5),
('Fichero de Practico del Bricolage / Superfacil','Albañileria','Pinto, Brian','1.1','2025-09-08',null,'2025-10-06','Biblioteca control 15-09-25.xlsx',6),
('Hombre','Alberto Campos Carles','Lopez Saavedra, Roque Oscar','1.3','2025-09-02',null,'2025-09-30','Biblioteca control 15-09-25.xlsx',7),
('La Empresa Flexible','Alvin Toffler','Carbajo Zerda, Rodrigo','2.4','2025-09-22',null,'2025-10-13','Biblioteca control 15-09-25.xlsx',8),
('Azabache','Ana Sewell','Gatica, Brian','6.2','2025-06-09',null,null,'Biblioteca control 15-09-25.xlsx',9),
('El Universo de las formas','Andre Chastel','Garcia, Ricardo','1.1','2025-08-11',null,'2025-08-18','Biblioteca control 15-09-25.xlsx',10),
('Philosophia','Anuario UNC','Sanchez Funes, Luis Alfredo','4.4','2025-06-24','2/7/2025 8/7/2025',null,'Biblioteca control 15-09-25.xlsx',11),
('Tinte y estampado','Bailly - Bailliere','Duran, Nazareno','2.1','2025-07-29',null,'2025-08-12','Biblioteca control 15-09-25.xlsx',12),
('Cultura musical','Bairelles-Galeano','Bravo, Armando','1.4','2025-10-01',null,'2025-12-10','Biblioteca control 15-09-25.xlsx',13),
('Slot barr historietas','barreiro  - solano lopez','Meleer, Sebastian','4.3','2025-11-14',null,'2026-01-12','Biblioteca control 15-09-25.xlsx',14),
('One way ticket','Basset Jenifer','Sanchez Zarate Jesus','6.2','2025-09-25',null,'2025-10-16','Biblioteca control 15-09-25.xlsx',15),
('El Zorro - Llanero Solitario','Biblioteca  Clarin','Oliva, Emanuel','1.1','2025-08-11',null,'2025-08-18','Biblioteca control 15-09-25.xlsx',16),
('Gran atlas','Billiken','Pinto, Brian','1.1','2025-08-11',null,'2025-08-25','Biblioteca control 15-09-25.xlsx',17),
('Cartas del diablo a su sobrino','C.S. Lewis','Carbajo Zerda, Rodrigo','2.4','2025-12-03',null,'2025-12-09','Biblioteca control 15-09-25.xlsx',18),
('Conspiraciones','campana','Meleer, Sebastian','4.3','2025-11-14',null,'2026-01-12','Biblioteca control 15-09-25.xlsx',19),
('Hacerce cargo','Casa de la memoria','Estalles, Brian','3.4','2025-06-10',null,null,'Biblioteca control 15-09-25.xlsx',20),
('Mecanica, Tecnica y Estetica Grafica','Cesarini Hermanos','Pinto, Brian','1.1','2025-08-25',null,'2025-09-01','Biblioteca control 15-09-25.xlsx',21),
('Radio Ciudad Perdida','Daniel Alarcon','Malossi Pinto, Victor Hugo','6.2','2025-10-16',null,'2025-10-30','Biblioteca control 15-09-25.xlsx',22),
('La cautela','Dominguez Fernando','Ulloa, Gustavo','6.2','2025-09-25',null,null,'Biblioteca control 15-09-25.xlsx',23),
('Biologia 2','Editorial Stella','Oliva Samorano - Emmanuel','1.1','2025-09-08',null,'2025-09-29','Biblioteca control 15-09-25.xlsx',24),
('La Filosofia Contemporanea','Enzo Paci','Carbajo Zerda, Rodrigo','2.4','2025-09-22',null,'2025-11-12','Biblioteca control 15-09-25.xlsx',25),
('Colapso','Ermand','Diaz, Franco','6.2','2025-06-09',null,null,'Biblioteca control 15-09-25.xlsx',26),
('Memorias presentes','Fava Claudia','Montenegro, Patricio','3.2','2025-06-09',null,null,'Biblioteca control 15-09-25.xlsx',27),
('Crimen y Castigo','Fedor Dostoievski','Carbajo Zerda, Rodrigo','2.4','2025-11-12',null,'2025-11-25','Biblioteca control 15-09-25.xlsx',28),
('Los mitos de la historia argentina 2','Felipe Pigna','Lucero Villafañe, Jose','1.3','2025-09-09',null,null,'Biblioteca control 15-09-25.xlsx',29),
('Historia Argentina','Fernandez Arlaud','Oliva ,Emanuel','1.1','2025-07-28',null,'2025-08-04','Biblioteca control 15-09-25.xlsx',30),
('El holandes errante','Franco Viccarini','Mairan, Alex','6.2','2025-09-25',null,null,'Biblioteca control 15-09-25.xlsx',31),
('El cuarto protocolo','Frederick Forsyth','Serrano, Brian','1.2','2025-06-27','2025-07-04','2025-08-01','Biblioteca control 15-09-25.xlsx',32),
('El cuarto protocolo','Frederick Forsyth','Ramirez Pedron, Cristian','1.1','2025-09-29','2025-10-13','2025-10-27','Biblioteca control 15-09-25.xlsx',33),
('Odessa','Frederick Forsyth','Tarrés Rios, Juan Manuel','4.4','2025-10-24',null,'2025-12-01','Biblioteca control 15-09-25.xlsx',34),
('El cuarto protocolo','Frederick Forsyth','REYES MONTECINO GONZALO','1.1','2025-11-03',null,null,'Biblioteca control 15-09-25.xlsx',35),
('Odessa','Frederick Forsyth','Gonzalez, Gael','4.4','2025-12-01',null,null,'Biblioteca control 15-09-25.xlsx',36),
('Odessa','Frederick Forsyth','Plaza, Emiliano','2.4','2025-12-23',null,'2026-01-30','Biblioteca control 15-09-25.xlsx',37),
('Cultura Musical','Galeano -Bareilles','Gonzalez Ortego, ivan','4.4','2025-09-22',null,'2025-09-30','Biblioteca control 15-09-25.xlsx',38),
('Los hermanos rico','Georges Simenon','Pelaytay, Brian','3.3','2025-10-30',null,null,'Biblioteca control 15-09-25.xlsx',39),
('El loco','Gibran Khalil','Enriquez, Angel','1.3','2025-06-24',null,null,'Biblioteca control 15-09-25.xlsx',40),
('Historia de Cristo','Giovanni Papini','Calderon Polo, Gustavo','6.2','2025-10-16',null,null,'Biblioteca control 15-09-25.xlsx',41),
('El mundo en el tiempo','Globerama','Martinez Paco, Gonzalo','3.2','2025-09-08',null,'2025-10-13','Biblioteca control 15-09-25.xlsx',42),
('El fafabricante de muertos','Guy Des Cars','REYES MONTECINO GONZALO','1.1','2025-09-01',null,'2025-09-15','Biblioteca control 15-09-25.xlsx',43),
('Tu hija de 6 a 7','Hac er familia','RangolBrian','6.2','2025-10-16',null,'2025-10-30','Biblioteca control 15-09-25.xlsx',44),
('Demoliendo Fronteras','Hafha','Gelvez, Walter','1.4','2025-08-13',null,null,'Biblioteca control 15-09-25.xlsx',45),
('los profanadores del amor','harold robbins','gianportones guerra','4.3','2025-08-29',null,null,'Biblioteca control 15-09-25.xlsx',46),
('Los niños del brasil','ira levin','Amaya Nuñez, Lucas','5.4','2025-11-20',null,null,'Biblioteca control 15-09-25.xlsx',47),
('la isla bajo el mar','isabel allende','Melendre, Pamela','6.1','2025-10-18',null,'2025-10-31','Biblioteca control 15-09-25.xlsx',48),
('Humanoides','J. Garcia Blanco','Alberto, Serna','4.2','2025-10-15',null,null,'Biblioteca control 15-09-25.xlsx',49),
('Vicente lopez me quede en tus orillas','J.G.M Olavarria','Fernandez Castillo','4.4','2025-09-19',null,null,'Biblioteca control 15-09-25.xlsx',50),
('Arquelogia Psiquica','Jeffry Goodman','Mansilla Gutierrez, Mariano','2.4','2025-08-13',null,null,'Biblioteca control 15-09-25.xlsx',51),
('Oro','Jhonatan Black','Peter Cultura para pamela','6.1','2025-10-06',null,null,'Biblioteca control 15-09-25.xlsx',52),
('Asesinato de calidad','John Le Carre','Pinto, Brian','1.1','2025-09-01',null,'2025-09-08','Biblioteca control 15-09-25.xlsx',53),
('Viaje al pais de los matreros','Jose S. Mueraz','Sicre, Matias','4.4','2025-09-19',null,null,'Biblioteca control 15-09-25.xlsx',54),
('Cronicas Penales','Juan Carlos Aguinaga','Garcia, Ricardo','1.1','2025-07-28',null,'2025-08-18','Biblioteca control 15-09-25.xlsx',55),
('Cronicas Penales','Juan Carlos Aguinaga','Videla Rojas, Luis Alberto','4.4','2025-10-06',null,'2025-11-05','Biblioteca control 15-09-25.xlsx',56),
('Pueblo Olvido','Juan Cruz Sarmiento','Cordoba Malde, Gabriel','4.4','2025-09-02',null,'2025-09-29','Biblioteca control 15-09-25.xlsx',57),
('El vacilar de las cosas','Juan Jose Sebrelli','Gimenez Agüero, Gonzalo Eric','1.2','2025-06-27',null,'2025-07-04','Biblioteca control 15-09-25.xlsx',58),
('Futboloscopia','Juan Manuel Herbella','Oliva, Emanuel','1.1','2025-08-11',null,'2025-08-18','Biblioteca control 15-09-25.xlsx',59),
('Futboloscopia','Juan Manuel Herbella','Lopez Saavedra, Roque Oscar','1.3','2025-08-26',null,'2025-09-02','Biblioteca control 15-09-25.xlsx',60),
('La fuerza de la violencia','Judith Butler','Martinez Paco, Gonzalo','3.2','2025-09-08','2025-10-27',null,'Biblioteca control 15-09-25.xlsx',61),
('Biologia para pensar','kapeluz norma','Amaya Nuñez, Lucas','5.4','2025-11-20',null,null,'Biblioteca control 15-09-25.xlsx',62),
('El ocho','katherine neville','Carbajo Zerda, Rodrigo','2.4','2025-11-25',null,'2025-11-02','Biblioteca control 15-09-25.xlsx',63),
('El hombre de San Petersburgo','Ken Follett','Ramirez Pedron, Cristian','1.1','2025-11-03',null,null,'Biblioteca control 15-09-25.xlsx',64),
('Crimenes capitales','Lawrence Sanders','Quiroga Perelli, Jose Luis','6.2','2025-06-09',null,null,'Biblioteca control 15-09-25.xlsx',65),
('Hablemos Ingles','Learning Company','Benavides, Luis','4.4','2025-06-26','12/9/2025 19/9/2025',null,'Biblioteca control 15-09-25.xlsx',66),
('Trocadero','Leslie Waller','Ramirez Pedron, Cristian','1.1','2025-10-27',null,null,'Biblioteca control 15-09-25.xlsx',67),
('Heroes y villanos','Luciana Sabina','Sanchez Funes, Luis Alfredo','4.4','2025-06-24','2/7/2025 8/7/2025',null,'Biblioteca control 15-09-25.xlsx',68),
('Las profecias de nostradamus','M Michel','Carbajo Zerda, Rodrigo','2.4','2025-11-12',null,'2025-11-17','Biblioteca control 15-09-25.xlsx',69),
('Historia "El mundo contemporaneo"','M. E. Alenso','Garcia, Ricardo','1.1','2025-08-25',null,'2025-09-01','Biblioteca control 15-09-25.xlsx',70),
('El oraculo','Manfredi','Ramirez Pedron, Cristian','1.1','2025-10-27',null,null,'Biblioteca control 15-09-25.xlsx',71),
('Las Poesias','Mari Pepa','Pinto, Brian','1.1','2025-10-06',null,'2025-10-27','Biblioteca control 15-09-25.xlsx',72),
('TEMATA y FUGA','Miguel Angel Garcia Fages','Reyes, Gonzalo','1.1','2025-08-25',null,'2025-09-01','Biblioteca control 15-09-25.xlsx',73),
('La Caida de Illia','Miguel Angel Taroncher','Ramirez Pedron, Cristian','1.1','2025-08-25',null,'2025-09-01','Biblioteca control 15-09-25.xlsx',74),
('Gramatica de la fantasia','ministerio de educacion','Meleer, Sebastian','4.3','2025-07-04',null,'2025-10-03','Biblioteca control 15-09-25.xlsx',75),
('Lengua 2','Ministerio de empleo','Ramirez, Maximiliano','6.2','2025-09-25',null,null,'Biblioteca control 15-09-25.xlsx',76),
('El abogado del diablo','Morris West','Moyano Lucero,Hernan','4.4','2025-07-03','2025-08-07','2025-09-12','Biblioteca control 15-09-25.xlsx',77),
('Arlequin','Morris West','Peter Cultura para pamela','6.1','2025-10-06',null,null,'Biblioteca control 15-09-25.xlsx',78),
('Eduque a su hijo para Dios','p Zezinho','RangolBrian','6.2','2025-10-30',null,null,'Biblioteca control 15-09-25.xlsx',79),
('La Guerra donde seremos sodados','Pablo Colombi','Oliva Samorano - Emmanuel','1.1','2025-09-08',null,'2025-09-29','Biblioteca control 15-09-25.xlsx',80),
('Historia de la estupidez humana','paul tabori','Videla Rojas, Luis Alberto','4.4','2025-11-10',null,'2025-12-01','Biblioteca control 15-09-25.xlsx',81),
('Historia de la estupidez humana','Paul Tabori','Carbajo Zerda, Rodrigo','2.4','2025-12-07',null,'2026-03-27','Biblioteca control 15-09-25.xlsx',82),
('Brida','Paulo Cohelo','Calderon Polo, Gustavo','6.2','2025-09-25',null,'2025-10-16','Biblioteca control 15-09-25.xlsx',83),
('El zahir','Paulo Cohelo','Cordoba Malde, Gabriel','4.4','2025-09-30',null,null,'Biblioteca control 15-09-25.xlsx',84),
('El manto de noe','Philippe Julien','Martinez Paco, Gonzalo','3.2','2025-10-27',null,'2025-11-03','Biblioteca control 15-09-25.xlsx',85),
('Simulacion un enfoque practico','Raul Coss Bu','Duran, Nazareno','2.1','2025-07-29','2025-08-12','2025-09-09','Biblioteca control 15-09-25.xlsx',86),
('El sueño eterno','Raymond Chandler','Garcia, Ricardo','1.1','2025-08-04',null,'2025-08-11','Biblioteca control 15-09-25.xlsx',87),
('Libros selectos','Readers Digest','Penida Chaile, Axel','4.3','2025-06-13','2025-10-03',null,'Biblioteca control 15-09-25.xlsx',88),
('Maravillas y misterios del mundo animal','Readers Digest','Gonzalez Ortego, ivan','4.4','2025-09-22',null,'2025-09-30','Biblioteca control 15-09-25.xlsx',89),
('Slot barr historietas','Ricardo Barreiro','Oliva, Emanuel','1.1','2025-06-23','2025-06-30','2025-07-28','Biblioteca control 15-09-25.xlsx',90),
('Slot-Barr','Ricardo Barreiro','Moyano Lucero,Hernan','4.4','2025-09-19',null,'2025-10-31','Biblioteca control 15-09-25.xlsx',91),
('El extraño caso del Srt. Jekyll y Mr. Hyde','Robert Louis','Alberto, Serna','4.2','2025-10-15',null,null,'Biblioteca control 15-09-25.xlsx',92),
('Secretos para triunfar en la vida','Salesman','Carbajo Zerda, Rodrigo','2.4','2025-12-02',null,'2025-12-03','Biblioteca control 15-09-25.xlsx',93),
('Ciencias Naturales 1','Santillan en linea','Amaya Nuñez, Lucas','5.4','2025-07-08',null,'2025-08-18','Biblioteca control 15-09-25.xlsx',94),
('La Enc. Del Est. Matematicas','Santillane','Pinto, Brian','1.1','2025-08-25',null,'2025-09-01','Biblioteca control 15-09-25.xlsx',95),
('El inspector justo y otras historias','Sanyu','Garcia, Ricardo','1.1','2025-06-23',null,'2025-06-30','Biblioteca control 15-09-25.xlsx',96),
('El inspector justo y otras historias','Sanyu','Mendez, Sebastian','4.3','2025-08-08',null,'2025-10-03','Biblioteca control 15-09-25.xlsx',97),
('De poemas llena De poetas todo','Sara Perez Bazot','Moyano Lucero,Hernan','4.4','2025-09-26',null,'2025-10-31','Biblioteca control 15-09-25.xlsx',98),
('El vacilar de las cosas','Sebreli Juan Jose','Gil, Franco','3.1','2025-10-30',null,null,'Biblioteca control 15-09-25.xlsx',99),
('Dos almas en busca de sueño','Serguio Putrino','Oliva, Emanuel','1.1','2025-07-28','4/8/2025 11/08/2025','2025-08-18','Biblioteca control 15-09-25.xlsx',100),
('El Desafio Mundial','Servan - Schreiber','Ramirez Pedron, Cristian','1.1','2025-07-28',null,'2025-08-18','Biblioteca control 15-09-25.xlsx',101),
('Si hubiera un mañana','Sidney Sheldon','Tarrés Rios, Juan Manuel','4.4','2025-09-30',null,'2025-10-14','Biblioteca control 15-09-25.xlsx',102),
('Si hubiera un mañana','Sidney Sheldon','Barraza, Martin','4.4','2025-10-24',null,'2025-11-20','Biblioteca control 15-09-25.xlsx',103),
('Si hubiera un mañana','Sidney Sheldon','fernandez andres','4.4','2025-11-20',null,null,'Biblioteca control 15-09-25.xlsx',104),
('Aventuras de David Balfour','Stevenson','Arredondo, Dilan','4.2','2025-10-01',null,null,'Biblioteca control 15-09-25.xlsx',105),
('Poemas para mi fueye','Teddy Peiro','Jofre, Adrian','3.3','2025-12-04',null,'2025-11-10','Biblioteca control 15-09-25.xlsx',106),
('Shibumi','Trevanian','Gonzalez, Kevin','1.2','2025-06-27',null,'2025-07-04','Biblioteca control 15-09-25.xlsx',107),
('Shibumi','Trevanian','Ramirez Pedron, Cristian','1.1','2025-09-01',null,'2025-09-29','Biblioteca control 15-09-25.xlsx',108),
('Derechos de niños, niñas y adolescentes','unicef','Martinez Paco, Gonzalo','3.2','2025-10-27',null,null,'Biblioteca control 15-09-25.xlsx',109),
('El derecho tomo 130','Vidal Campos','Pinto, Brian','1.1','2025-10-27',null,'2025-11-07','Biblioteca control 15-09-25.xlsx',110),
('El perfil del ser humano','Walter Barbosa','Moyano Lucero,Hernan','4.4','2025-06-26',null,'2025-07-03','Biblioteca control 15-09-25.xlsx',111),
('De demonios y Hombre','Walter Pohl','Cira, Alejandro','1.1','2025-10-06',null,'2025-11-07','Biblioteca control 15-09-25.xlsx',112),
('Liza nacida estrella','Wendy Leigh','Gonzalez Ortego, ivan','4.4','2025-10-06',null,'2025-10-14','Biblioteca control 15-09-25.xlsx',113),
('Tentar al diablo','Wilbur Smith','Meleer, Sebastian','4.3','2026-01-12',null,'2026-04-07','Biblioteca control 15-09-25.xlsx',114),
('Casa de estrella',null,'Ochoa, Adriel','2.4','2025-06-09',null,null,'Biblioteca control 15-09-25.xlsx',115),
('Maravillas y misterios del mundo animal',null,'Garcia, Ricardo','1.1','2025-06-09',null,'2025-06-23','Biblioteca control 15-09-25.xlsx',116),
('CIDH principios y buenas practicas sobre la proteccion de las personas privadas de libertad en america',null,'Galvan, Ariel','4.2','2025-06-18',null,null,'Biblioteca control 15-09-25.xlsx',117),
('Tecnicas de buceo deportivo',null,'Lucero Villafañe, Jose','1.3','2025-06-24',null,null,'Biblioteca control 15-09-25.xlsx',118),
('CIDH principios y buenas practicas sobre la proteccion de las personas privadas de libertad en america',null,'Oliva, Emanuel','1.1','2025-06-30',null,'2025-07-28','Biblioteca control 15-09-25.xlsx',119),
('Educacion para la salud Drogas',null,'Oliva ,Emanuel','1.1','2025-06-30',null,'2025-07-28','Biblioteca control 15-09-25.xlsx',120),
('Parques Nacionales Argentina',null,'Garcia, Ricardo','1.1','2025-06-30',null,'2025-07-28','Biblioteca control 15-09-25.xlsx',121),
('CIDH principios y buenas practicas sobre la proteccion de las personas privadas de libertad en america',null,'Reyes, Gonzalo','1.1','2025-07-28',null,'2025-08-04','Biblioteca control 15-09-25.xlsx',122),
('Vida del Chacho',null,'Sebastian Meler','4.3','2025-08-29','2025-10-03','2025-11-14','Biblioteca control 15-09-25.xlsx',123),
('Geo Vietnam',null,'Sanchez Zarate Jesus','6.2','2025-09-25','2025-10-16',null,'Biblioteca control 15-09-25.xlsx',124),
('Seccion 1: La empresa',null,'Ramirez, Maximiliano','6.2','2025-09-25',null,null,'Biblioteca control 15-09-25.xlsx',125),
('El Zorro - Llanero Solitario',null,'Malossi Pinto, Victor Hugo','6.2','2025-09-25',null,'2025-10-16','Biblioteca control 15-09-25.xlsx',126),
('For winners 1',null,'Peletay, Alexis','3.4','2025-09-30',null,null,'Biblioteca control 15-09-25.xlsx',127),
('Todo comenzo en los 60',null,'Abrego Diaz, Marco','3.4','2025-09-30',null,null,'Biblioteca control 15-09-25.xlsx',128),
('Best of you curas naturales',null,'Suarez, Luis','1.1','2025-10-13','2025-10-27',null,'Biblioteca control 15-09-25.xlsx',129),
('La tierra',null,'Sanchez Zarate Jesus','6.2','2025-10-16',null,null,'Biblioteca control 15-09-25.xlsx',130),
('Revista selecciones',null,'Sanchez Zarate Jesus','6.2','2025-10-30',null,null,'Biblioteca control 15-09-25.xlsx',131),
('Biologia 1',null,'sanches zarate jesus','6.2','2025-10-30',null,null,'Biblioteca control 15-09-25.xlsx',132),
('Momentos de gozo',null,'Oliva, Emanuel','1.1','2025-11-03',null,null,'Biblioteca control 15-09-25.xlsx',133),
('Asalto a la ilusion',null,'Meleer, Sebastian','4.3','2026-01-05',null,'2026-04-07','Biblioteca control 15-09-25.xlsx',134),
('Etica para amador',null,'Meleer, Sebastian','4.3','2026-01-05',null,'2026-01-12','Biblioteca control 15-09-25.xlsx',135),
('Jaime press y la nueva dimension',null,'Meleer, Sebastian','4.3','2026-01-12',null,null,'Biblioteca control 15-09-25.xlsx',136),
('Argentinos de raza',null,'Meleer, Sebastian','4.3','2026-01-12',null,'2026-04-07','Biblioteca control 15-09-25.xlsx',137),
('Lo que todo el mundo debe saber sobre las drogas',null,'Meleer, Sebastian','4.3','2026-01-12',null,null,'Biblioteca control 15-09-25.xlsx',138),
('Los favoritos de midas',null,'Meleer, Sebastian','4.3','2026-01-19',null,'2026-04-07','Biblioteca control 15-09-25.xlsx',139),
('Mitos griegos',null,'Meleer, Sebastian','4.3','2026-01-19',null,null,'Biblioteca control 15-09-25.xlsx',140),
('Filosofia griega',null,'Meleer, Sebastian','4.3','2026-01-19',null,null,'Biblioteca control 15-09-25.xlsx',141),
('Expreso de medianoche',null,'Meleer, Sebastian','4.3','2026-01-19',null,null,'Biblioteca control 15-09-25.xlsx',142),
('El padrino',null,'Barroso, Daniel','2.4','2026-01-19',null,null,'Biblioteca control 15-09-25.xlsx',143),
('el perrito tony',null,'Vargas Brian','4.3','2026-01-19',null,null,'Biblioteca control 15-09-25.xlsx',144),
('las caballadas en la gerra del indio',null,'Rojas Lucas','2.4','2026-01-22',null,'2026-02-02','Biblioteca control 15-09-25.xlsx',145),
('tienes miedo a la oscuridad','Sidney Sheldon','SIN INFORMAR',null,'2025-11-20',null,'2026-03-25','Biblioteca control 15-09-25.xlsx',146),
('El abogado del diablo','Morris West','Gonzalez Jose','Cetrys','2026-03-26',null,'2026-03-30','Biblioteca control 15-09-25.xlsx',147),
('Facundo','D.F. Sarmiento','Sosa, Adrian','2.4','2026-03-27',null,'2026-04-13','Biblioteca control 15-09-25.xlsx',148),
('Beethoveen','Emil Ludwig','Carbajo Zerda, Rodrigo','2.4','2026-01-02',null,'2026-04-10','Biblioteca control 15-09-25.xlsx',149),
('Mayor y Menor','Chanti','Gonzalez, Facundo','3.2','2026-03-30',null,null,'Biblioteca control 15-09-25.xlsx',150),
('Los Invitados','Alfonso Grosso','Gonzalez Jose','Cetrys','2026-03-30',null,null,'Biblioteca control 15-09-25.xlsx',151),
('La isla de las tomentas','John Le Carre','Mancuso Nicolas','3. 4',null,null,null,'Biblioteca control 15-09-25.xlsx',152),
('La fuerza de los monterrey',null,'alejandro weiss','2.4','2026-04-16',null,'2026-04-22','Biblioteca control 15-09-25.xlsx',153),
('Poder militar y sociedad politica en la argentina vol 2','Alain Rouquié','Lopez Saavedra, Roque Oscar','3.4','2026-04-24',null,'2026-04-30','Biblioteca control 15-09-25.xlsx',154),
('Odessa','Frederick Forsyth','Alejandro Weiss','2.4','2026-06-24',null,'2026-04-27','Biblioteca control 15-09-25.xlsx',155),
('Veronika decide morir','Paulo Cohelo','Alejandro Weiss','2.4','2026-04-27',null,null,'Biblioteca control 15-09-25.xlsx',156),
('Arte en el mundo Neoclasicismo','Viscontea','Carlos Gonzalez Brizuela','2.4','2026-04-28',null,null,'Biblioteca control 15-09-25.xlsx',157),
('La mas bella tradició','Nuevo estilo n° 218','Carlos Gonzalez Brizuela','2.4','2026-04-28',null,null,'Biblioteca control 15-09-25.xlsx',158),
('El atroz encanto de ser argentinos','Marcos Aguinis','Lopez Saavedra, Roque Oscar','3.4','2026-04-30',null,null,'Biblioteca control 15-09-25.xlsx',159)
on conflict(source_file,source_row) do update set
title=excluded.title,authors=excluded.authors,ppl_name=excluded.ppl_name,module=excluded.module,
received_at=excluded.received_at,renewal=excluded.renewal,returned_at=excluded.returned_at;
