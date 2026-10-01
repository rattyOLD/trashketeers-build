-- Trash Squad v15: журнал ошибок игры прямо в базе (вкладка «Ошибки» в панели DeV, без выгрузки Excel).
-- Игра сама присылает ошибки (не чаще 30 в час с одного игрока), DeV читает последние и сводку по типам.
-- Запустить один раз (повтор безопасен).

create table if not exists public.client_errors (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  user_id uuid,
  friend_code text,
  build text not null default '',
  device text not null default '',
  body text not null
);
create index if not exists client_errors_time_idx on public.client_errors (created_at desc);
alter table public.client_errors enable row level security;
revoke all on public.client_errors from anon, authenticated;

create or replace function public.log_error(p_build text, p_device text, p_body text)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
begin
  if uid is null or coalesce(btrim(p_body), '') = '' then return; end if;
  if (select count(*) from public.client_errors e where e.user_id = uid and e.created_at > now() - interval '1 hour') >= 30 then
    return;
  end if;
  insert into public.client_errors (user_id, friend_code, build, device, body)
    values (uid, (select p.friend_code from public.profiles p where p.id = uid), left(coalesce(p_build, ''), 40),
            left(coalesce(p_device, ''), 120), left(p_body, 4000));
  -- Журнал не растёт бесконечно: держим последние 20 000 записей.
  if random() < 0.01 then
    delete from public.client_errors where id < (select max(id) - 20000 from public.client_errors);
  end if;
end
$fn$;

-- Последние ошибки (по желанию только одной сборки).
create or replace function public.dev_errors(p_limit int default 60, p_build text default '')
returns table (id bigint, created_at timestamptz, friend_code text, nickname text, build text, device text, body text)
language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  return query
    select e.id, e.created_at, e.friend_code, p.nickname, e.build, e.device, e.body
    from public.client_errors e left join public.profiles p on p.id = e.user_id
    where coalesce(p_build, '') = '' or e.build = p_build
    order by e.id desc limit least(greatest(coalesce(p_limit, 60), 1), 300);
end
$fn$;

-- Сводка за сутки: какие ошибки чаще всего, у скольких игроков, в каких сборках.
create or replace function public.dev_error_summary()
returns table (head text, hits bigint, players bigint, builds text, last_at timestamptz)
language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  return query
    select left(split_part(e.body, chr(10), 1), 90) as head, count(*), count(distinct e.user_id),
      string_agg(distinct e.build, ', '), max(e.created_at)
    from public.client_errors e
    where e.created_at > now() - interval '24 hours'
    group by 1 order by 2 desc limit 40;
end
$fn$;

revoke all on function public.log_error(text, text, text), public.dev_errors(int, text), public.dev_error_summary() from public, anon;
grant execute on function public.log_error(text, text, text), public.dev_errors(int, text), public.dev_error_summary() to authenticated;

notify pgrst, 'reload schema';
