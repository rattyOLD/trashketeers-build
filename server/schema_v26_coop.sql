-- Trash Squad v26: кооп. Приглашения друзей в комнату и серверная проверка «входить можно только другу хозяина».
-- Запустить один раз (повтор безопасен). Таблица закрыта для клиента (как все после v24), всё через RPC.

create table if not exists public.coop_invites (
  id bigserial primary key,
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  room text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);
create index if not exists coop_invites_to_idx on public.coop_invites (to_id, created_at desc);
alter table public.coop_invites enable row level security;
revoke all on public.coop_invites from anon, authenticated;

-- Позвать друга в комнату. Ответ: 'ok', 'not_friends', 'blocked', 'banned', 'rate', 'bad', 'auth'.
create or replace function public.send_coop_invite(p_code text, p_room text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  room text := upper(btrim(coalesce(p_room, '')));
begin
  if uid is null then return 'auth'; end if;
  if room !~ '^[A-Z0-9]{3,12}$' then return 'bad'; end if;
  if exists (select 1 from public.profiles p where p.id = uid and p.chat_banned) then return 'banned'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(coalesce(p_code, '')));
  if target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return 'not_friends';
  end if;
  if exists (select 1 from public.blocks b where (b.user_id = target and b.blocked_id = uid) or (b.user_id = uid and b.blocked_id = target)) then
    return 'blocked';
  end if;
  if (select count(*) from public.coop_invites i where i.from_id = uid and i.created_at > now() - interval '1 minute') >= 6 then
    return 'rate';
  end if;
  -- Тому же другу не чаще раза в 10 секунд, повторное приглашение заменяет прошлое, а не копится стопкой.
  if exists (select 1 from public.coop_invites i where i.from_id = uid and i.to_id = target and i.created_at > now() - interval '10 seconds') then
    return 'rate';
  end if;
  delete from public.coop_invites where from_id = uid and to_id = target and status = 'pending';
  insert into public.coop_invites (from_id, to_id, room) values (uid, target, room);
  return 'ok';
end
$fn$;

-- Мои приглашения: только свежие (до 3 минут) и ещё не принятые.
drop function if exists public.coop_inbox();
create or replace function public.coop_inbox()
returns table (id bigint, from_name text, from_code text, room text, age_sec int, from_c text, from_s text, from_lv int)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
begin
  if uid is null then return; end if;
  delete from public.coop_invites where created_at < now() - interval '1 hour';
  return query
    select i.id, p.nickname, p.friend_code, i.room, extract(epoch from now() - i.created_at)::int,
           left(coalesce(p.stats->>'c', ''), 24), left(coalesce(p.stats->>'s', 'classic'), 24),
           least(greatest(coalesce(nullif(p.stats->>'lv', '')::int, 1), 1), 999)
    from public.coop_invites i join public.profiles p on p.id = i.from_id
    where i.to_id = uid and i.status = 'pending' and i.created_at > now() - interval '3 minutes'
      and not exists (select 1 from public.blocks b where b.user_id = uid and b.blocked_id = i.from_id)
    order by i.created_at desc limit 5;
end
$fn$;

-- Ответ на приглашение. Принял: вернёт код комнаты. Иначе: 'declined', 'expired' или 'bad'.
create or replace function public.coop_invite_answer(p_id bigint, p_accept boolean)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  inv public.coop_invites%rowtype;
begin
  if uid is null then return 'bad'; end if;
  select * into inv from public.coop_invites where id = p_id and to_id = uid and status = 'pending';
  if not found then return 'bad'; end if;
  if inv.created_at < now() - interval '3 minutes' then
    delete from public.coop_invites where id = p_id;
    return 'expired';
  end if;
  update public.coop_invites set status = case when p_accept then 'accepted' else 'declined' end where id = p_id;
  return case when p_accept then inv.room else 'declined' end;
end
$fn$;

-- Игровой сервер зовёт это ОТ ИМЕНИ ВХОДЯЩЕГО (с его токеном): можно ли ему в комнату этого хозяина.
-- Условия: хозяин существует, вы друзья, никто никого не блокировал, оба не забанены.
create or replace function public.coop_can_join(p_room text)
returns boolean language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  host uuid;
begin
  if uid is null then return false; end if;
  select p.id into host from public.profiles p where p.friend_code = upper(btrim(coalesce(p_room, ''))) and not p.chat_banned;
  if host is null or host = uid then return false; end if;
  if exists (select 1 from public.profiles p where p.id = uid and p.chat_banned) then return false; end if;
  if not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = host)
     or not exists (select 1 from public.friendships f where f.user_id = host and f.friend_id = uid) then
    return false;
  end if;
  return not exists (select 1 from public.blocks b where (b.user_id = host and b.blocked_id = uid) or (b.user_id = uid and b.blocked_id = host));
end
$fn$;

revoke all on function public.send_coop_invite(text, text), public.coop_inbox(), public.coop_invite_answer(bigint, boolean), public.coop_can_join(text) from public, anon;
grant execute on function public.send_coop_invite(text, text), public.coop_inbox(), public.coop_invite_answer(bigint, boolean), public.coop_can_join(text) to authenticated;

notify pgrst, 'reload schema';
