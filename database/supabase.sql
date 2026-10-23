-- PROMOCIÓN CULTURAL · COMPLEJO ALMAFUERTE
-- Pegá todo este script en Supabase > SQL Editor y presioná Run.

create extension if not exists pgcrypto;
create type public.app_role as enum ('operador','administrador');
create type public.workshop_status as enum ('activo','suspendido','finalizado');
create type public.attendance_status as enum ('presente','ausente','justificado');
create type public.asset_status as enum ('disponible','prestado','baja');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null, full_name text not null default 'Usuario',
  role public.app_role not null default 'operador', active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.people (
  id bigint generated always as identity primary key, identifier text not null unique,
  last_name text not null, first_name text not null, location text, active boolean not null default true,
  notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.workshops (
  id bigint generated always as identity primary key, name text not null, instructor text, schedule text,
  location text, capacity integer check(capacity is null or capacity > 0), status public.workshop_status not null default 'activo',
  description text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.enrollments (
  id bigint generated always as identity primary key, workshop_id bigint not null references public.workshops(id) on delete cascade,
  person_id bigint not null references public.people(id), active boolean not null default true,
  created_at timestamptz not null default now(), unique(workshop_id,person_id)
);
create table public.attendance (
  id bigint generated always as identity primary key, workshop_id bigint not null references public.workshops(id) on delete cascade,
  enrollment_id bigint not null references public.enrollments(id) on delete cascade, attendance_date date not null,
  status public.attendance_status not null default 'presente', notes text, registered_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(enrollment_id,attendance_date)
);
create table public.books (
  id bigint generated always as identity primary key, title text not null, author text, isbn text, code text not null unique,
  status public.asset_status not null default 'disponible', notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.book_loans (
  id bigint generated always as identity primary key, book_id bigint not null references public.books(id), person_id bigint not null references public.people(id),
  delivered_at date not null default current_date, due_at date, returned_at date, notes text, registered_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.instruments (
  id bigint generated always as identity primary key, name text not null, code text not null unique, condition text not null default 'bueno',
  status public.asset_status not null default 'disponible', notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.instrument_loans (
  id bigint generated always as identity primary key, instrument_id bigint not null references public.instruments(id), person_id bigint not null references public.people(id),
  delivered_at date not null default current_date, due_at date, returned_at date, return_condition text, notes text,
  registered_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.audit_log (
  id bigint generated always as identity primary key, user_id uuid references public.profiles(id), action text not null,
  entity text not null, entity_id text, detail jsonb, created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,email,full_name) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1))); return new; end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='administrador' and active=true);
$$;
create or replace function public.is_active_user() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active=true);
$$;

create or replace function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;
do $$ declare t text; begin foreach t in array array['profiles','people','workshops','attendance','books','book_loans','instruments','instrument_loans'] loop execute format('create trigger set_%I_updated before update on public.%I for each row execute function public.set_updated_at()',t,t); end loop; end $$;

create or replace function public.audit_change() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.audit_log(user_id,action,entity,entity_id,detail) values(auth.uid(),lower(tg_op),tg_table_name,coalesce(new.id,old.id)::text,case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end); return coalesce(new,old); end; $$;
do $$ declare t text; begin foreach t in array array['people','workshops','enrollments','attendance','books','book_loans','instruments','instrument_loans'] loop execute format('create trigger audit_%I after insert or update or delete on public.%I for each row execute function public.audit_change()',t,t); end loop; end $$;

create or replace function public.loan_book(book_id bigint,person_id bigint,due_at date default null,registered_by uuid default auth.uid()) returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_active_user() then raise exception 'Usuario no habilitado'; end if; update books b set status='prestado' where b.id=$1 and b.status='disponible'; if not found then raise exception 'El libro no está disponible'; end if; insert into book_loans(book_id,person_id,due_at,registered_by) values($1,$2,$3,auth.uid()); end $$;
create or replace function public.return_book(loan_id bigint) returns void language plpgsql security definer set search_path=public as $$
declare asset_id bigint; begin if not public.is_active_user() then raise exception 'Usuario no habilitado'; end if; update book_loans bl set returned_at=current_date where bl.id=$1 and bl.returned_at is null returning bl.book_id into asset_id; if asset_id is null then raise exception 'Préstamo no encontrado'; end if; update books b set status='disponible' where b.id=asset_id; end $$;
create or replace function public.loan_instrument(instrument_id bigint,person_id bigint,due_at date default null,registered_by uuid default auth.uid()) returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_active_user() then raise exception 'Usuario no habilitado'; end if; update instruments i set status='prestado' where i.id=$1 and i.status='disponible'; if not found then raise exception 'El instrumento no está disponible'; end if; insert into instrument_loans(instrument_id,person_id,due_at,registered_by) values($1,$2,$3,auth.uid()); end $$;
create or replace function public.return_instrument(loan_id bigint) returns void language plpgsql security definer set search_path=public as $$
declare asset_id bigint; begin if not public.is_active_user() then raise exception 'Usuario no habilitado'; end if; update instrument_loans il set returned_at=current_date where il.id=$1 and il.returned_at is null returning il.instrument_id into asset_id; if asset_id is null then raise exception 'Préstamo no encontrado'; end if; update instruments i set status='disponible' where i.id=asset_id; end $$;

alter table public.profiles enable row level security; alter table public.people enable row level security; alter table public.workshops enable row level security;
alter table public.enrollments enable row level security; alter table public.attendance enable row level security; alter table public.books enable row level security;
alter table public.book_loans enable row level security; alter table public.instruments enable row level security; alter table public.instrument_loans enable row level security; alter table public.audit_log enable row level security;

create policy profiles_read on public.profiles for select to authenticated using(public.is_active_user());
create policy profiles_admin_update on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
do $$ declare t text; begin foreach t in array array['people','workshops','enrollments','attendance','books','book_loans','instruments','instrument_loans'] loop
 execute format('create policy %I_read on public.%I for select to authenticated using(public.is_active_user())',t,t);
 execute format('create policy %I_insert on public.%I for insert to authenticated with check(public.is_active_user())',t,t);
 execute format('create policy %I_update on public.%I for update to authenticated using(public.is_active_user()) with check(public.is_active_user())',t,t);
 execute format('create policy %I_delete_admin on public.%I for delete to authenticated using(public.is_admin())',t,t);
end loop; end $$;
create policy audit_admin_read on public.audit_log for select to authenticated using(public.is_admin());

grant execute on function public.loan_book(bigint,bigint,date,uuid) to authenticated;
grant execute on function public.return_book(bigint) to authenticated;
grant execute on function public.loan_instrument(bigint,bigint,date,uuid) to authenticated;
grant execute on function public.return_instrument(bigint) to authenticated;

-- DESPUÉS DE CREAR TU PRIMER USUARIO EN AUTHENTICATION > USERS, CONVERTILO EN ADMINISTRADOR:
-- update public.profiles set full_name='Administrador', role='administrador' where email='TU_CORREO@EJEMPLO.COM';
