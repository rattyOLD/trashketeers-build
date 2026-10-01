-- Часть A: облачные сохранения (таблица закрыта, доступ только через функции).
create table if not exists public.cloud_saves (
  code text primary key,
  owner uuid not null,
  data text not null,
  updated_at timestamptz not null default now()
);
alter table public.cloud_saves enable row level security;
revoke all on public.cloud_saves from anon, authenticated;

create or replace function public.upload_save(p_data text)
returns text language plpgsql security definer set search_path = public as $fn$
declare uid uuid := auth.uid(); c text;
begin
  if uid is null or length(p_data) > 400000 then return ''; end if;
  select s.code into c from public.cloud_saves s where s.owner = uid;
  if c is null then
    loop
      c := upper(substr(translate(md5(random()::text || clock_timestamp()::text || uid::text), '01', 'XY'), 1, 14));
      exit when not exists (select 1 from public.cloud_saves s where s.code = c);
    end loop;
    insert into public.cloud_saves (code, owner, data) values (c, uid, p_data);
  else
    update public.cloud_saves set data = p_data, updated_at = now() where code = c;
  end if;
  return c;
end
$fn$;

create or replace function public.restore_save(p_code text)
returns text language plpgsql security definer set search_path = public as $fn$
declare uid uuid := auth.uid(); k text := upper(btrim(p_code)); d text;
begin
  if uid is null then return ''; end if;
  select s.data into d from public.cloud_saves s where s.code = k;
  if d is null then return ''; end if;
  delete from public.cloud_saves where owner = uid and code <> k;
  update public.cloud_saves set owner = uid where code = k;
  return d;
end
$fn$;

revoke all on function public.upload_save(text), public.restore_save(text) from public, anon;
grant execute on function public.upload_save(text), public.restore_save(text) to authenticated;
