-- Trash Squad v18: «Ты вошёл на N устройствах» в профиле, счётчики гостей и журнал чистки в панели DeV.
-- Запустить один раз (повтор безопасен).

create table if not exists public.cleanup_log (
  at timestamptz not null default now(),
  removed int not null default 0
);
alter table public.cleanup_log enable row level security;
revoke all on public.cleanup_log from anon, authenticated;

create or replace function public.cleanup_empty_guests()
returns int language plpgsql security definer set search_path = public, auth as $fn$
declare
  n int;
begin
  with doomed as (
    select u.id from auth.users u
    left join public.profiles p on p.id = u.id
    where coalesce(u.email, '') = ''
      and coalesce(u.last_sign_in_at, u.created_at) < now() - interval '30 days'
      and coalesce(p.best_wave, 0) = 0
      and coalesce(p.insider, -1) = -1
      and not exists (select 1 from public.cloud_saves s where s.owner = u.id)
      and not exists (select 1 from public.friendships f where f.user_id = u.id)
      and not exists (select 1 from public.moved_accounts m where m.new_id = u.id)
    limit 5000
  )
  delete from auth.users u using doomed where u.id = doomed.id;
  get diagnostics n = row_count;
  insert into public.cleanup_log (removed) values (n);
  return n;
end
$fn$;
revoke all on function public.cleanup_empty_guests() from public, anon, authenticated;

create or replace function public.dev_stats()
returns jsonb language plpgsql security definer set search_path = public, auth as $fn$
begin
  if not public.is_dev() then return null; end if;
  return jsonb_build_object(
    'players', (select count(*) from public.profiles),
    'active_24h', (select count(*) from public.profiles where last_seen > now() - interval '24 hours'),
    'active_1h', (select count(*) from public.profiles where last_seen > now() - interval '1 hour'),
    'friendships', (select count(*) / 2 from public.friendships),
    'messages_24h', (select count(*) from public.messages where created_at > now() - interval '24 hours'),
    'messages_all', (select count(*) from public.messages),
    'reports_open', (select count(*) from public.reports where not resolved),
    'banned', (select count(*) from public.profiles where chat_banned),
    'devs', (select count(*) from public.profiles where insider = 0),
    'insiders', (select count(*) from public.profiles where insider = 1),
    'guests', (select count(*) from auth.users u where coalesce(u.email, '') = ''),
    'guest_logins', (select count(*) from auth.users u where u.email like 'guest\_%'),
    'accounts', (select count(*) from auth.users u where coalesce(u.email, '') <> '' and u.email not like 'guest\_%'),
    'cleanup_at', (select max(c.at) from public.cleanup_log c),
    'cleanup_removed', (select c.removed from public.cleanup_log c order by c.at desc limit 1)
  );
end
$fn$;
revoke all on function public.dev_stats() from public, anon;
grant execute on function public.dev_stats() to authenticated;

-- Сколько устройств вошло в этот аккаунт (живые сессии, обновлявшиеся за 30 дней).
create or replace function public.my_devices()
returns int language sql security definer set search_path = public, auth as $fn$
  select count(*)::int from auth.sessions s
  where s.user_id = auth.uid() and (s.not_after is null or s.not_after > now())
    and coalesce(s.refreshed_at, s.updated_at, s.created_at) > now() - interval '30 days';
$fn$;
revoke all on function public.my_devices() from public, anon;
grant execute on function public.my_devices() to authenticated;

notify pgrst, 'reload schema';
