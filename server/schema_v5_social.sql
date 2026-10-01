-- Trash Squad: социальная часть (заявки, профили друзей, личные сообщения, блокировки, жалобы).
-- Вставить целиком в SQL Editor и нажать Run. Можно запускать повторно.

alter table public.profiles add column if not exists stats jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists last_seen timestamptz not null default now();
alter table public.profiles add column if not exists chat_banned boolean not null default false;

create table if not exists public.friend_requests (
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_id, to_id),
  check (from_id <> to_id)
);

create table if not exists public.blocks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, blocked_id),
  check (user_id <> blocked_id)
);

create table if not exists public.messages (
  id bigserial primary key,
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists messages_pair_idx on public.messages (from_id, to_id, id);
create index if not exists messages_inbox_idx on public.messages (to_id, read_at);

create table if not exists public.reports (
  id bigserial primary key,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  message_id bigint,
  reason text not null default '',
  created_at timestamptz not null default now()
);

alter table public.friend_requests enable row level security;
alter table public.blocks enable row level security;
alter table public.messages enable row level security;
alter table public.reports enable row level security;
revoke all on public.friend_requests, public.blocks, public.messages, public.reports from anon, authenticated;

-- Профиль с публичной статистикой и отметкой «был в сети».
create or replace function public.sync_profile_v2(p_nickname text, p_best_wave int, p_insider int, p_stats jsonb)
returns table (friend_code text) language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  code text;
  nick text := left(btrim(coalesce(p_nickname, '')), 24);
  wave int := least(greatest(coalesce(p_best_wave, 0), 0), 500);
  clean jsonb := case when p_stats is null or length(p_stats::text) > 2000 then '{}'::jsonb else p_stats end;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if nick = '' then nick := 'Енот'; end if;
  select p.friend_code into code from public.profiles p where p.id = uid;
  if code is null then
    loop
      code := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'XY'), 1, 6));
      exit when not exists (select 1 from public.profiles p where p.friend_code = code);
    end loop;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider, stats, last_seen)
      values (uid, nick, code, wave, p_insider, clean, now());
  else
    update public.profiles set nickname = nick, best_wave = greatest(best_wave, wave), insider = p_insider,
      stats = clean, last_seen = now(), updated_at = now() where id = uid;
  end if;
  return query select code;
end
$fn$;

-- Заявка в друзья: 'sent', 'ok' (встречная заявка принята), 'friends', 'self', 'not_found', 'blocked', 'limit'.
create or replace function public.request_friend(p_code text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  if uid is null then return 'auth'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if target is null then return 'not_found'; end if;
  if target = uid then return 'self'; end if;
  if exists (select 1 from public.blocks b where (b.user_id = target and b.blocked_id = uid) or (b.user_id = uid and b.blocked_id = target)) then
    return 'blocked';
  end if;
  if exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then return 'friends'; end if;
  if (select count(*) from public.friendships where user_id = uid) >= 100 then return 'limit'; end if;
  if exists (select 1 from public.friend_requests r where r.from_id = target and r.to_id = uid) then
    insert into public.friendships (user_id, friend_id) values (uid, target), (target, uid) on conflict do nothing;
    delete from public.friend_requests where (from_id = target and to_id = uid) or (from_id = uid and to_id = target);
    return 'ok';
  end if;
  if (select count(*) from public.friend_requests where from_id = uid) >= 30 then return 'limit'; end if;
  insert into public.friend_requests (from_id, to_id) values (uid, target) on conflict do nothing;
  return 'sent';
end
$fn$;

create or replace function public.list_requests()
returns table (nickname text, friend_code text, best_wave int, insider int, created_at timestamptz)
language sql security definer set search_path = public as $fn$
  select p.nickname, p.friend_code, p.best_wave, p.insider, r.created_at
  from public.friend_requests r join public.profiles p on p.id = r.from_id
  where r.to_id = auth.uid() order by r.created_at desc limit 50;
$fn$;

create or replace function public.answer_request(p_code text, p_accept boolean)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  if uid is null then return 'auth'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if target is null then return 'not_found'; end if;
  if not exists (select 1 from public.friend_requests r where r.from_id = target and r.to_id = uid) then return 'none'; end if;
  delete from public.friend_requests where from_id = target and to_id = uid;
  if p_accept then
    insert into public.friendships (user_id, friend_id) values (uid, target), (target, uid) on conflict do nothing;
    return 'ok';
  end if;
  return 'declined';
end
$fn$;

-- Друзья с последним сообщением и числом непрочитанных.
create or replace function public.inbox()
returns table (nickname text, friend_code text, best_wave int, insider int, last_seen timestamptz,
               last_body text, last_at timestamptz, unread int, stats jsonb)
language sql security definer set search_path = public as $fn$
  select p.nickname, p.friend_code, p.best_wave, p.insider, p.last_seen,
    (select m.body from public.messages m where (m.from_id = uid.id and m.to_id = p.id) or (m.from_id = p.id and m.to_id = uid.id) order by m.id desc limit 1),
    (select m.created_at from public.messages m where (m.from_id = uid.id and m.to_id = p.id) or (m.from_id = p.id and m.to_id = uid.id) order by m.id desc limit 1),
    (select count(*)::int from public.messages m where m.from_id = p.id and m.to_id = uid.id and m.read_at is null),
    p.stats
  from (select auth.uid() as id) uid
  join public.friendships f on f.user_id = uid.id
  join public.profiles p on p.id = f.friend_id
  order by 7 desc nulls last, p.nickname;
$fn$;

-- Профиль игрока: свой или друга (или того, кто прислал заявку).
create or replace function public.friend_profile(p_code text)
returns table (nickname text, friend_code text, best_wave int, insider int, last_seen timestamptz, stats jsonb, is_friend boolean, is_blocked boolean)
language sql security definer set search_path = public as $fn$
  select p.nickname, p.friend_code, p.best_wave, p.insider, p.last_seen, p.stats,
    exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = p.id),
    exists (select 1 from public.blocks b where b.user_id = auth.uid() and b.blocked_id = p.id)
  from public.profiles p
  where p.friend_code = upper(btrim(p_code))
    and (p.id = auth.uid()
      or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = p.id)
      or exists (select 1 from public.friend_requests r where r.to_id = auth.uid() and r.from_id = p.id));
$fn$;

-- Отправка: 'ok', 'not_friends', 'blocked', 'rate', 'empty', 'banned'.
create or replace function public.send_message(p_code text, p_body text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  text_body text := left(btrim(coalesce(p_body, '')), 500);
begin
  if uid is null then return 'auth'; end if;
  if text_body = '' then return 'empty'; end if;
  if exists (select 1 from public.profiles p where p.id = uid and p.chat_banned) then return 'banned'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return 'not_friends';
  end if;
  if exists (select 1 from public.blocks b where (b.user_id = target and b.blocked_id = uid) or (b.user_id = uid and b.blocked_id = target)) then
    return 'blocked';
  end if;
  if (select count(*) from public.messages m where m.from_id = uid and m.created_at > now() - interval '1 minute') >= 20 then
    return 'rate';
  end if;
  insert into public.messages (from_id, to_id, body) values (uid, target, text_body);
  return 'ok';
end
$fn$;

-- Сообщения переписки после id p_after; входящие помечаются прочитанными.
create or replace function public.get_messages(p_code text, p_after bigint default 0)
returns table (id bigint, mine boolean, body text, created_at timestamptz)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return;
  end if;
  update public.messages m set read_at = now() where m.from_id = target and m.to_id = uid and m.read_at is null;
  return query
    select * from (
      select m.id, (m.from_id = uid) as mine, m.body, m.created_at
      from public.messages m
      where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid)) and m.id > p_after
      order by m.id desc limit 100
    ) t order by t.id;
end
$fn$;

create or replace function public.unread_total()
returns int language sql security definer set search_path = public as $fn$
  select (select count(*)::int from public.messages m where m.to_id = auth.uid() and m.read_at is null)
       + (select count(*)::int from public.friend_requests r where r.to_id = auth.uid());
$fn$;

create or replace function public.block_user(p_code text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or target = uid then return 'bad'; end if;
  insert into public.blocks (user_id, blocked_id) values (uid, target) on conflict do nothing;
  delete from public.friendships where (user_id = uid and friend_id = target) or (user_id = target and friend_id = uid);
  delete from public.friend_requests where (from_id = uid and to_id = target) or (from_id = target and to_id = uid);
  return 'ok';
end
$fn$;

create or replace function public.unblock_user(p_code text)
returns void language plpgsql security definer set search_path = public as $fn$
declare target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if auth.uid() is null or target is null then return; end if;
  delete from public.blocks where user_id = auth.uid() and blocked_id = target;
end
$fn$;

create or replace function public.list_blocks()
returns table (nickname text, friend_code text)
language sql security definer set search_path = public as $fn$
  select p.nickname, p.friend_code from public.blocks b join public.profiles p on p.id = b.blocked_id
  where b.user_id = auth.uid() order by b.created_at desc;
$fn$;

create or replace function public.report_user(p_code text, p_reason text, p_message_id bigint default null)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or target = uid then return 'bad'; end if;
  if (select count(*) from public.reports r where r.reporter_id = uid and r.created_at > now() - interval '1 day') >= 20 then return 'rate'; end if;
  insert into public.reports (reporter_id, target_id, message_id, reason) values (uid, target, p_message_id, left(coalesce(p_reason, ''), 200));
  return 'ok';
end
$fn$;

revoke all on function
  public.sync_profile_v2(text, int, int, jsonb), public.request_friend(text), public.list_requests(), public.answer_request(text, boolean),
  public.inbox(), public.friend_profile(text), public.send_message(text, text), public.get_messages(text, bigint), public.unread_total(),
  public.block_user(text), public.unblock_user(text), public.list_blocks(), public.report_user(text, text, bigint)
from public, anon;
grant execute on function
  public.sync_profile_v2(text, int, int, jsonb), public.request_friend(text), public.list_requests(), public.answer_request(text, boolean),
  public.inbox(), public.friend_profile(text), public.send_message(text, text), public.get_messages(text, bigint), public.unread_total(),
  public.block_user(text), public.unblock_user(text), public.list_blocks(), public.report_user(text, text, bigint)
to authenticated;

-- Чистка: сообщения старше 30 дней можно удалять запросом
--   delete from public.messages where created_at < now() - interval '30 days';
