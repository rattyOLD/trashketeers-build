-- Trash Squad: ПОЛНАЯ настройка сервера одним файлом (все schema*.sql по порядку, v1..v27).
-- Для нового проекта Supabase: SQL Editor -> вставить целиком -> Run. Повторный запуск безопасен:
-- таблицы и данные не трогаются, функции пересоздаются, действующие DeV/Insider-ссылки НЕ сбрасываются.
-- Также нужно: Authentication -> Sign In / Providers -> включить Anonymous sign-ins и Email, выключить Confirm email.
-- Собирается из отдельных файлов; при правке схемы меняй исходный schema_vN.sql и пересобирай этот.

-- ======================== schema.sql ========================
-- Trash Squad: схема Supabase. Вставить целиком в SQL Editor и нажать Run (можно запускать повторно).

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default 'Енот',
  friend_code text not null unique,
  best_wave int not null default 0,
  insider int not null default -1,
  updated_at timestamptz not null default now()
);

create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table if not exists public.line_votes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  line_id text not null,
  value smallint not null check (value in (-1, 1)),
  who text not null default '',
  line_text text not null default '',
  build text not null default '',
  insider int not null default -1,
  created_at timestamptz not null default now(),
  primary key (user_id, line_id)
);

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.line_votes enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = profiles.id));

drop policy if exists friendships_select on public.friendships;
create policy friendships_select on public.friendships for select to authenticated using (user_id = auth.uid());

drop policy if exists votes_select on public.line_votes;
create policy votes_select on public.line_votes for select to authenticated using (user_id = auth.uid());
drop policy if exists votes_insert on public.line_votes;
create policy votes_insert on public.line_votes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists votes_update on public.line_votes;
create policy votes_update on public.line_votes for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.profiles, public.friendships, public.line_votes from anon, authenticated;
grant select on public.profiles, public.friendships to authenticated;
grant select, insert, update on public.line_votes to authenticated;

-- Профиль создаётся и обновляется только через функцию: код друга выдаёт сервер.
create or replace function public.sync_profile(p_nickname text, p_best_wave int, p_insider int)
returns table (friend_code text) language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  code text;
  nick text := left(btrim(coalesce(p_nickname, '')), 24);
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if nick = '' then nick := 'Енот'; end if;
  select p.friend_code into code from public.profiles p where p.id = uid;
  if code is null then
    loop
      code := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'XY'), 1, 6));
      exit when not exists (select 1 from public.profiles p where p.friend_code = code);
    end loop;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider)
      values (uid, nick, code, greatest(p_best_wave, 0), p_insider);
  else
    update public.profiles set nickname = nick, best_wave = greatest(best_wave, p_best_wave), insider = p_insider, updated_at = now()
      where id = uid;
  end if;
  return query select code;
end $$;

create or replace function public.add_friend(p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  if uid is null then return 'auth'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if target is null then return 'not_found'; end if;
  if target = uid then return 'self'; end if;
  if (select count(*) from public.friendships where user_id = uid) >= 100 then return 'limit'; end if;
  insert into public.friendships (user_id, friend_id) values (uid, target), (target, uid) on conflict do nothing;
  return 'ok';
end $$;

create or replace function public.remove_friend(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null then return; end if;
  delete from public.friendships where (user_id = uid and friend_id = target) or (user_id = target and friend_id = uid);
end $$;

create or replace function public.list_friends()
returns table (nickname text, friend_code text, best_wave int, insider int, updated_at timestamptz)
language sql security definer set search_path = public as $$
  select p.nickname, p.friend_code, p.best_wave, p.insider, p.updated_at
  from public.friendships f join public.profiles p on p.id = f.friend_id
  where f.user_id = auth.uid() order by p.best_wave desc, p.nickname;
$$;

revoke all on function public.sync_profile(text, int, int), public.add_friend(text), public.remove_friend(text), public.list_friends() from public, anon;
grant execute on function public.sync_profile(text, int, int), public.add_friend(text), public.remove_friend(text), public.list_friends() to authenticated;

-- ======================== schema_v2.sql ========================
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

-- ======================== schema_v3.sql ========================
-- Часть B: таблица рекордов и ограничение волны (защита от очевидной накрутки).
create or replace function public.top_waves(p_limit int default 20)
returns table (nickname text, best_wave int, insider int)
language sql security definer set search_path = public as $fn$
  select p.nickname, p.best_wave, p.insider from public.profiles p
  where p.best_wave > 0 order by p.best_wave desc, p.updated_at asc
  limit least(greatest(p_limit, 1), 50);
$fn$;

revoke all on function public.top_waves(int) from public, anon;
grant execute on function public.top_waves(int) to authenticated;

create or replace function public.sync_profile(p_nickname text, p_best_wave int, p_insider int)
returns table (friend_code text) language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  code text;
  nick text := left(btrim(coalesce(p_nickname, '')), 24);
  wave int := least(greatest(coalesce(p_best_wave, 0), 0), 500);
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if nick = '' then nick := 'Енот'; end if;
  select p.friend_code into code from public.profiles p where p.id = uid;
  if code is null then
    loop
      code := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'XY'), 1, 6));
      exit when not exists (select 1 from public.profiles p where p.friend_code = code);
    end loop;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider) values (uid, nick, code, wave, p_insider);
  else
    update public.profiles set nickname = nick, best_wave = greatest(best_wave, wave), insider = p_insider, updated_at = now() where id = uid;
  end if;
  return query select code;
end
$fn$;

revoke all on function public.sync_profile(text, int, int) from public, anon;
grant execute on function public.sync_profile(text, int, int) to authenticated;

-- ======================== schema_v4.sql ========================
-- Часть C: сохранение текущего профиля (для входа по почте).
create or replace function public.my_save()
returns text language sql security definer set search_path = public as $fn$
  select s.data from public.cloud_saves s where s.owner = auth.uid();
$fn$;

revoke all on function public.my_save() from public, anon;
grant execute on function public.my_save() to authenticated;

-- ======================== schema_v5_social.sql ========================
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

-- ======================== schema_v6_filter.sql ========================
-- Trash Squad: фильтр слов в личных сообщениях. Слова из таблицы banned_words заменяются на ***.
-- Список правится в Table Editor: добавляй основы слов строчными буквами. Можно запускать повторно.

create table if not exists public.banned_words (
  stem text primary key check (stem = lower(stem) and char_length(stem) >= 3)
);
alter table public.banned_words enable row level security;
revoke all on public.banned_words from anon, authenticated;

insert into public.banned_words (stem) values
  ('хуй'), ('хуе'), ('хуя'), ('хуё'), ('пизд'), ('ебан'), ('ебат'), ('ебал'), ('ебла'), ('ёбан'), ('ёбар'),
  ('блядь'), ('бляд'), ('блять'), ('мудак'), ('мудил'), ('гондон'), ('пидор'), ('пидар'), ('пидр'),
  ('залуп'), ('шлюх'), ('ублюд'), ('сучар'), ('уёб'), ('уеб'), ('долбоёб'), ('долбоеб'), ('нигер'), ('хохл'), ('чурк')
on conflict do nothing;

create or replace function public.clean_text(p_text text)
returns text language plpgsql stable security definer set search_path = public as $fn$
declare
  result text := p_text;
  w record;
begin
  for w in select stem from public.banned_words loop
    result := regexp_replace(result, '[[:alnum:]]*' || regexp_replace(w.stem, '([\\.^$*+?()\[\]{}|-])', '\\\1', 'g') || '[[:alnum:]]*', '***', 'gi');
  end loop;
  return result;
end
$fn$;
revoke all on function public.clean_text(text) from public, anon, authenticated;

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
  insert into public.messages (from_id, to_id, body) values (uid, target, public.clean_text(text_body));
  return 'ok';
end
$fn$;
revoke all on function public.send_message(text, text) from public, anon;
grant execute on function public.send_message(text, text) to authenticated;

-- ======================== schema_v7_badges_dev.sql ========================
-- Trash Squad: теги DeV и Insider, проверяемые сервером, и инструменты разработчика.
-- Секретов в этом файле нет: только их хэши. Запустить целиком один раз (повторный запуск безопасен).

-- Секретные ссылки: в базе только хэши. У каждой есть лимит использований; DeV-ссылка сгорает после 3 входов,
-- а новую (старая тут же перестаёт работать) DeV выпускает сам из панели.
create table if not exists public.badge_secrets (
  id bigserial primary key,
  level int not null,
  hash text not null unique,
  uses int not null default 0,
  max_uses int,
  active boolean not null default true
);
alter table public.badge_secrets enable row level security;
revoke all on public.badge_secrets from anon, authenticated;
insert into public.badge_secrets (level, hash, max_uses) values
  (0, 'b3488e1b166c9bb794e9b2caf187c2d334d6f371698a65c64ad67be1d48f7586', 3),
  (1, '55e6cb7bc35832da1dc5e1e8b7209864c214bf253fac92ae673955042da531f1', null)
  on conflict (hash) do nothing;

alter table public.reports add column if not exists resolved boolean not null default false;

-- Клиент больше не может сам объявить себя DeV или Insider: тег ставится только функциями ниже.
create or replace function public.sync_profile(p_nickname text, p_best_wave int, p_insider int)
returns table (friend_code text) language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  code text;
  nick text := left(btrim(coalesce(p_nickname, '')), 24);
  wave int := least(greatest(coalesce(p_best_wave, 0), 0), 500);
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if nick = '' then nick := 'Енот'; end if;
  select p.friend_code into code from public.profiles p where p.id = uid;
  if code is null then
    loop
      code := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'XY'), 1, 6));
      exit when not exists (select 1 from public.profiles p where p.friend_code = code);
    end loop;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider) values (uid, nick, code, wave, -1);
  else
    update public.profiles set nickname = nick, best_wave = greatest(best_wave, wave), updated_at = now() where id = uid;
  end if;
  return query select code;
end
$fn$;

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
      values (uid, nick, code, wave, -1, clean, now());
  else
    update public.profiles set nickname = nick, best_wave = greatest(best_wave, wave),
      stats = clean, last_seen = now(), updated_at = now() where id = uid;
  end if;
  return query select code;
end
$fn$;

-- Обмен секрета из ссылки на тег: 0 (DeV), 1 (Insider) или -1. Уже выданный DeV повторно лимит не тратит.
create or replace function public.claim_badge(p_secret text)
returns int language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  sec public.badge_secrets%rowtype;
  mine int;
begin
  if uid is null then return -1; end if;
  select * into sec from public.badge_secrets s
    where s.active and s.hash = encode(sha256(convert_to(coalesce(p_secret, ''), 'UTF8')), 'hex');
  if not found then return -1; end if;
  select insider into mine from public.profiles where id = uid;
  if not found then return -1; end if;
  if mine = sec.level then return sec.level; end if;
  if sec.level = 1 and mine = 0 then return 0; end if;
  if sec.max_uses is not null and sec.uses >= sec.max_uses then return -1; end if;
  update public.badge_secrets set uses = uses + 1, active = (max_uses is null or uses + 1 < max_uses) where id = sec.id;
  update public.profiles set insider = sec.level where id = uid;
  return sec.level;
end
$fn$;

-- DeV выпускает новую ссылку: старые для этого уровня отключаются. Возвращает секрет один раз.
create or replace function public.dev_rotate_link(p_level int)
returns text language plpgsql security definer set search_path = public as $fn$
declare secret text;
begin
  if not public.is_dev() or p_level not in (0, 1) then return null; end if;
  secret := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  update public.badge_secrets set active = false where level = p_level;
  insert into public.badge_secrets (level, hash, max_uses)
    values (p_level, encode(sha256(convert_to(secret, 'UTF8')), 'hex'), case when p_level = 0 then 3 else null end);
  return secret;
end
$fn$;

create or replace function public.my_badge()
returns int language sql stable security definer set search_path = public as $fn$
  select coalesce((select p.insider from public.profiles p where p.id = auth.uid()), -1);
$fn$;

create or replace function public.is_dev()
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.insider = 0);
$fn$;

create or replace function public.dev_stats()
returns jsonb language plpgsql security definer set search_path = public as $fn$
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
    'insiders', (select count(*) from public.profiles where insider = 1)
  );
end
$fn$;

create or replace function public.dev_reports()
returns table (id bigint, created_at timestamptz, reporter text, target text, target_code text, reason text, body text, banned boolean)
language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  return query
    select r.id, r.created_at, rp.nickname, tp.nickname, tp.friend_code, r.reason, m.body, tp.chat_banned
    from public.reports r
    join public.profiles rp on rp.id = r.reporter_id
    join public.profiles tp on tp.id = r.target_id
    left join public.messages m on m.id = r.message_id
    where not r.resolved order by r.id desc limit 30;
end
$fn$;

create or replace function public.dev_resolve_report(p_id bigint)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  update public.reports set resolved = true where id = p_id;
end
$fn$;

create or replace function public.dev_set_chat_ban(p_code text, p_banned boolean)
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return 'denied'; end if;
  update public.profiles set chat_banned = p_banned where friend_code = upper(btrim(p_code)) and insider <> 0;
  return 'ok';
end
$fn$;

-- Выдать или снять Insider по ID (уровни: 1 или -1). DeV так выдать нельзя.
create or replace function public.dev_set_badge(p_code text, p_level int)
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return 'denied'; end if;
  if p_level not in (-1, 1) then return 'bad'; end if;
  update public.profiles set insider = p_level where friend_code = upper(btrim(p_code)) and insider <> 0;
  return 'ok';
end
$fn$;

create or replace function public.dev_words()
returns table (stem text) language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  return query select w.stem from public.banned_words w order by w.stem;
end
$fn$;

create or replace function public.dev_add_word(p_word text)
returns text language plpgsql security definer set search_path = public as $fn$
declare w text := lower(btrim(coalesce(p_word, '')));
begin
  if not public.is_dev() then return 'denied'; end if;
  if char_length(w) < 3 or char_length(w) > 30 then return 'bad'; end if;
  insert into public.banned_words (stem) values (w) on conflict do nothing;
  return 'ok';
end
$fn$;

create or replace function public.dev_remove_word(p_word text)
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return 'denied'; end if;
  delete from public.banned_words where stem = lower(btrim(coalesce(p_word, '')));
  return 'ok';
end
$fn$;

revoke all on function
  public.sync_profile(text, int, int), public.sync_profile_v2(text, int, int, jsonb), public.claim_badge(text), public.my_badge(), public.is_dev(),
  public.dev_stats(), public.dev_reports(), public.dev_resolve_report(bigint), public.dev_set_chat_ban(text, boolean), public.dev_set_badge(text, int),
  public.dev_words(), public.dev_add_word(text), public.dev_remove_word(text)
from public, anon;
grant execute on function
  public.sync_profile(text, int, int), public.sync_profile_v2(text, int, int, jsonb), public.claim_badge(text), public.my_badge(),
  public.dev_stats(), public.dev_reports(), public.dev_resolve_report(bigint), public.dev_set_chat_ban(text, boolean), public.dev_set_badge(text, int),
  public.dev_words(), public.dev_add_word(text), public.dev_remove_word(text)
to authenticated;

-- ======================== schema_v8_badge_log.sql ========================
-- Trash Squad v8: журнал выдачи тегов для панели DeV. Запустить один раз (повтор безопасен).

create table if not exists public.badge_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  friend_code text,
  nickname text,
  level int not null,
  how text not null
);
alter table public.badge_log enable row level security;
revoke all on public.badge_log from anon, authenticated;

create or replace function public.claim_badge(p_secret text)
returns int language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  sec public.badge_secrets%rowtype;
  mine int;
  prof public.profiles%rowtype;
begin
  if uid is null then return -1; end if;
  select * into sec from public.badge_secrets s
    where s.active and s.hash = encode(sha256(convert_to(coalesce(p_secret, ''), 'UTF8')), 'hex');
  if not found then return -1; end if;
  select * into prof from public.profiles where id = uid;
  if not found then return -1; end if;
  mine := prof.insider;
  if mine = sec.level then return sec.level; end if;
  if sec.level = 1 and mine = 0 then return 0; end if;
  if sec.max_uses is not null and sec.uses >= sec.max_uses then return -1; end if;
  update public.badge_secrets set uses = uses + 1, active = (max_uses is null or uses + 1 < max_uses) where id = sec.id;
  update public.profiles set insider = sec.level where id = uid;
  insert into public.badge_log (friend_code, nickname, level, how) values (prof.friend_code, prof.nickname, sec.level, 'ссылка');
  return sec.level;
end
$fn$;

create or replace function public.dev_set_badge(p_code text, p_level int)
returns text language plpgsql security definer set search_path = public as $fn$
declare prof public.profiles%rowtype;
begin
  if not public.is_dev() then return 'denied'; end if;
  if p_level not in (-1, 1) then return 'bad'; end if;
  select * into prof from public.profiles where friend_code = upper(btrim(p_code)) and insider <> 0;
  if not found then return 'not_found'; end if;
  update public.profiles set insider = p_level where id = prof.id;
  insert into public.badge_log (friend_code, nickname, level, how) values (prof.friend_code, prof.nickname, p_level, 'вручную DeV');
  return 'ok';
end
$fn$;

create or replace function public.dev_rotate_link(p_level int)
returns text language plpgsql security definer set search_path = public as $fn$
declare secret text;
begin
  if not public.is_dev() or p_level not in (0, 1) then return null; end if;
  secret := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  update public.badge_secrets set active = false where level = p_level;
  insert into public.badge_secrets (level, hash, max_uses)
    values (p_level, encode(sha256(convert_to(secret, 'UTF8')), 'hex'), case when p_level = 0 then 3 else null end);
  insert into public.badge_log (friend_code, nickname, level, how) values (null, null, p_level, 'новая ссылка');
  return secret;
end
$fn$;

create or replace function public.dev_badge_log()
returns table (at timestamptz, friend_code text, nickname text, level int, how text)
language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  return query select l.at, l.friend_code, l.nickname, l.level, l.how from public.badge_log l order by l.id desc limit 40;
end
$fn$;

-- ======================== schema_v9_insider_limit.sql ========================
-- Trash Squad v9: Insider-ссылка получает лимит 50 входов (новая ссылка из панели DeV — тоже на 50). Запустить один раз.
update public.badge_secrets set max_uses = 50, active = (uses < 50) where level = 1 and max_uses is null;

create or replace function public.dev_rotate_link(p_level int)
returns text language plpgsql security definer set search_path = public as $fn$
declare secret text;
begin
  if not public.is_dev() or p_level not in (0, 1) then return null; end if;
  secret := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  update public.badge_secrets set active = false where level = p_level;
  insert into public.badge_secrets (level, hash, max_uses)
    values (p_level, encode(sha256(convert_to(secret, 'UTF8')), 'hex'), case when p_level = 0 then 3 else 50 end);
  insert into public.badge_log (friend_code, nickname, level, how) values (null, null, p_level, 'новая ссылка');
  return secret;
end
$fn$;

-- ======================== schema_v10_restore_badge.sql ========================
-- Trash Squad v10: при восстановлении сохранения по коду тег DeV/Insider переезжает на новое устройство.
-- Плюс запасная DeV-ссылка (10 входов) на случай, если лимит прежней уже потрачен: после входа перевыпусти её в панели DeV.
-- Запустить один раз (повтор безопасен).

create or replace function public.restore_save(p_code text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  k text := upper(btrim(p_code));
  d text;
  old_owner uuid;
  old_level int;
begin
  if uid is null then return ''; end if;
  select s.data, s.owner into d, old_owner from public.cloud_saves s where s.code = k;
  if d is null then return ''; end if;
  delete from public.cloud_saves where owner = uid and code <> k;
  update public.cloud_saves set owner = uid where code = k;
  if old_owner is not null and old_owner <> uid then
    select p.insider into old_level from public.profiles p where p.id = old_owner;
    if old_level in (0, 1) then
      update public.profiles set insider = old_level where id = uid and (insider = -1 or old_level = 0);
      insert into public.badge_log (friend_code, nickname, level, how)
        select p.friend_code, p.nickname, old_level, 'перенос при восстановлении' from public.profiles p where p.id = uid;
    end if;
  end if;
  return d;
end
$fn$;

revoke all on function public.restore_save(text) from public, anon;
grant execute on function public.restore_save(text) to authenticated;

-- Запасная DeV-ссылка заводится, только если активной DeV-ссылки нет (повторный запуск не ломает перевыпущенные).
insert into public.badge_secrets (level, hash, max_uses)
  select 0, '7731ea8c8a8861e61d96da876672fe9605128531311f55afb28ffed1af00d958', 10
  where not exists (select 1 from public.badge_secrets where level = 0 and active)
  on conflict (hash) do nothing;

-- ======================== schema_v11_password_reset.sql ========================
-- Trash Squad v11: сброс пароля через DeV (пароли никто не видит) и журнал сбросов. Запустить один раз.
-- Лимит: не больше 2 сбросов в сутки на один логин.

create table if not exists public.password_resets (
  id bigserial primary key,
  at timestamptz not null default now(),
  login text not null,
  by_nickname text,
  result text not null
);
alter table public.password_resets enable row level security;
revoke all on public.password_resets from anon, authenticated;

create or replace function public.dev_reset_password(p_login text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions, auth as $fn$
declare
  who text;
  lg text := lower(btrim(coalesce(p_login, '')));
  mail text;
  n int;
  res text;
begin
  if not public.is_dev() then return 'denied'; end if;
  select nickname into who from public.profiles where id = auth.uid();
  if lg !~ '^[a-z0-9_]{3,20}$' or char_length(coalesce(p_password, '')) < 6 then return 'bad'; end if;
  select count(*) into n from public.password_resets
    where login = lg and result = 'ok' and at > now() - interval '24 hours';
  if n >= 2 then
    insert into public.password_resets (login, by_nickname, result) values (lg, who, 'limit');
    return 'limit';
  end if;
  mail := lg || '@trashsquad.game';
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where email = mail;
  if found then res := 'ok'; else res := 'not_found'; end if;
  insert into public.password_resets (login, by_nickname, result) values (lg, who, res);
  return res;
end
$fn$;

create or replace function public.dev_password_log()
returns table (at timestamptz, login text, by_nickname text, result text)
language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  return query select r.at, r.login, r.by_nickname, r.result from public.password_resets r order by r.id desc limit 30;
end
$fn$;

revoke all on function public.dev_reset_password(text, text), public.dev_password_log() from public, anon;
grant execute on function public.dev_reset_password(text, text), public.dev_password_log() to authenticated;

-- ======================== schema_v12_adopt_account.sql ========================
-- Trash Squad v12: код восстановления теперь переносит ВЕСЬ аккаунт на новое устройство:
-- ник, ID-визитку, друзей, заявки, переписки, блокировки, жалобы и тег. Раньше переносилось только сохранение.
-- Запустить один раз (повтор безопасен).

create or replace function public.restore_save(p_code text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  k text := upper(btrim(p_code));
  d text;
  old uuid;
  p public.profiles%rowtype;
begin
  if uid is null then return ''; end if;
  select s.data, s.owner into d, old from public.cloud_saves s where s.code = k;
  if d is null then return ''; end if;
  delete from public.cloud_saves where owner = uid and code <> k;
  update public.cloud_saves set owner = uid where code = k;
  if old is null or old = uid then return d; end if;

  select * into p from public.profiles where id = old;
  if found then
    update public.profiles set friend_code = 'MOVED' || substr(md5(old::text), 1, 8) where id = old;
    delete from public.profiles where id = uid;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider, updated_at, stats, last_seen, chat_banned)
      values (uid, p.nickname, p.friend_code, p.best_wave, p.insider, now(), p.stats, now(), p.chat_banned);
    update public.friendships set user_id = uid where user_id = old;
    update public.friendships set friend_id = uid where friend_id = old;
    update public.line_votes set user_id = uid where user_id = old;
    update public.friend_requests set from_id = uid where from_id = old;
    update public.friend_requests set to_id = uid where to_id = old;
    update public.blocks set user_id = uid where user_id = old;
    update public.blocks set blocked_id = uid where blocked_id = old;
    update public.messages set from_id = uid where from_id = old;
    update public.messages set to_id = uid where to_id = old;
    update public.reports set reporter_id = uid where reporter_id = old;
    update public.reports set target_id = uid where target_id = old;
    delete from public.profiles where id = old;
    insert into public.badge_log (friend_code, nickname, level, how)
      select p.friend_code, p.nickname, p.insider, 'аккаунт перенесён по коду' where p.insider in (0, 1);
  end if;
  return d;
end
$fn$;

revoke all on function public.restore_save(text) from public, anon;
grant execute on function public.restore_save(text) to authenticated;

-- ======================== schema_v13_dev_accounts.sql ========================
-- Trash Squad v13: поиск аккаунтов с логином для панели DeV (пароли не показываются, их никто не видит). Запустить один раз.
create or replace function public.dev_accounts(p_query text default '')
returns table (login text, nickname text, friend_code text, last_seen timestamptz)
language plpgsql security definer set search_path = public, auth as $fn$
declare q text := lower(btrim(coalesce(p_query, '')));
begin
  if not public.is_dev() then return; end if;
  return query
    select split_part(u.email, '@', 1), p.nickname, p.friend_code, p.last_seen
    from auth.users u join public.profiles p on p.id = u.id
    where u.email like '%@trashsquad.game'
      and (q = '' or split_part(u.email, '@', 1) like '%' || q || '%' or lower(p.nickname) like '%' || q || '%' or lower(p.friend_code) = q)
    order by p.last_seen desc limit 30;
end
$fn$;
revoke all on function public.dev_accounts(text) from public, anon;
grant execute on function public.dev_accounts(text) to authenticated;

-- ======================== schema_v14_my_save.sql ========================
-- Trash Squad v14: функция my_save (нужна для входа в аккаунт и защиты прогресса) и перезагрузка кэша API. Запустить один раз.
create or replace function public.my_save()
returns text language sql security definer set search_path = public as $fn$
  select s.data from public.cloud_saves s where s.owner = auth.uid();
$fn$;

revoke all on function public.my_save() from public, anon;
grant execute on function public.my_save() to authenticated;

notify pgrst, 'reload schema';

-- ======================== schema_v15_client_errors.sql ========================
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

-- ======================== schema_v16_one_account_many_devices.sql ========================
-- Trash Squad v16: один аккаунт на нескольких устройствах, без «переездов».
-- 1) Код восстановления больше НЕ переносит аккаунт с логином: игра отвечает «войди логином» (ACCOUNT:<логин>).
--    Иначе браузер и мини-апка с экрана «Домой» отбирали аккаунт друг у друга.
-- 2) Гостя (без логина) код по-прежнему переносит, но старое устройство это узнаёт (MOVED)
--    и не заводит себе нового «левого» енота.
-- Запустить один раз (повтор безопасен).

create table if not exists public.moved_accounts (
  old_id uuid primary key,
  new_id uuid not null,
  moved_at timestamptz not null default now()
);
alter table public.moved_accounts enable row level security;
revoke all on public.moved_accounts from anon, authenticated;

create or replace function public.restore_save(p_code text)
returns text language plpgsql security definer set search_path = public, auth as $fn$
declare
  uid uuid := auth.uid();
  k text := upper(btrim(p_code));
  d text;
  old uuid;
  login text;
  p public.profiles%rowtype;
begin
  if uid is null then return ''; end if;
  select s.data, s.owner into d, old from public.cloud_saves s where s.code = k;
  if d is null then return ''; end if;
  if old is null or old = uid then return d; end if;

  select split_part(coalesce(u.email, ''), '@', 1) into login from auth.users u where u.id = old;
  if coalesce(login, '') <> '' then
    return 'ACCOUNT:' || login;
  end if;

  delete from public.cloud_saves where owner = uid and code <> k;
  update public.cloud_saves set owner = uid where code = k;
  select * into p from public.profiles where id = old;
  if found then
    update public.profiles set friend_code = 'MOVED' || substr(md5(old::text), 1, 8) where id = old;
    delete from public.profiles where id = uid;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider, updated_at, stats, last_seen, chat_banned)
      values (uid, p.nickname, p.friend_code, p.best_wave, p.insider, now(), p.stats, now(), p.chat_banned);
    update public.friendships set user_id = uid where user_id = old;
    update public.friendships set friend_id = uid where friend_id = old;
    update public.line_votes set user_id = uid where user_id = old;
    update public.friend_requests set from_id = uid where from_id = old;
    update public.friend_requests set to_id = uid where to_id = old;
    update public.blocks set user_id = uid where user_id = old;
    update public.blocks set blocked_id = uid where blocked_id = old;
    update public.messages set from_id = uid where from_id = old;
    update public.messages set to_id = uid where to_id = old;
    update public.reports set reporter_id = uid where reporter_id = old;
    update public.reports set target_id = uid where target_id = old;
    delete from public.profiles where id = old;
    insert into public.badge_log (friend_code, nickname, level, how)
      select p.friend_code, p.nickname, p.insider, 'аккаунт перенесён по коду' where p.insider in (0, 1);
  end if;
  insert into public.moved_accounts (old_id, new_id) values (old, uid)
    on conflict (old_id) do update set new_id = excluded.new_id, moved_at = now();
  delete from public.moved_accounts where old_id = uid;
  return d;
end
$fn$;

-- Профиль: если этот енот уже переехал на другое устройство, новый профиль не создаём, отвечаем MOVED.
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
    if exists (select 1 from public.moved_accounts m where m.old_id = uid) then
      return query select 'MOVED'::text;
      return;
    end if;
    loop
      code := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'XY'), 1, 6));
      exit when not exists (select 1 from public.profiles p where p.friend_code = code);
    end loop;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider, stats, last_seen)
      values (uid, nick, code, wave, -1, clean, now());
  else
    update public.profiles set nickname = nick, best_wave = greatest(best_wave, wave),
      stats = clean, last_seen = now(), updated_at = now() where id = uid;
  end if;
  return query select code;
end
$fn$;

revoke all on function public.restore_save(text), public.sync_profile_v2(text, int, int, jsonb) from public, anon;
grant execute on function public.restore_save(text), public.sync_profile_v2(text, int, int, jsonb) to authenticated;

notify pgrst, 'reload schema';

-- ======================== schema_v17_guest_login.sql ========================
-- Trash Squad v17: скрытый вход для гостей.
-- Игра тихо заводит гостю логин guest_xxxxxxxxxxxx и случайный пароль (тот же аккаунт, тот же ID).
-- Ссылка-вход теперь ВХОДИТ в этот аккаунт на втором устройстве, а не переносит его, и оба устройства активны.
-- Старый код восстановления для таких гостей по-прежнему переносит аккаунт (пароль от скрытого логина игрок не знает).
-- Плюс еженедельная чистка пустых гостей. Запустить один раз (повтор безопасен).

create or replace function public.restore_save(p_code text)
returns text language plpgsql security definer set search_path = public, auth as $fn$
declare
  uid uuid := auth.uid();
  k text := upper(btrim(p_code));
  d text;
  old uuid;
  login text;
  p public.profiles%rowtype;
begin
  if uid is null then return ''; end if;
  select s.data, s.owner into d, old from public.cloud_saves s where s.code = k;
  if d is null then return ''; end if;
  if old is null or old = uid then return d; end if;

  select split_part(coalesce(u.email, ''), '@', 1) into login from auth.users u where u.id = old;
  -- Скрытый логин гостя (guest_…) по коду переносится как раньше: пароля от него игрок не знает.
  if coalesce(login, '') <> '' and login not like 'guest\_%' then
    return 'ACCOUNT:' || login;
  end if;

  delete from public.cloud_saves where owner = uid and code <> k;
  update public.cloud_saves set owner = uid where code = k;
  select * into p from public.profiles where id = old;
  if found then
    update public.profiles set friend_code = 'MOVED' || substr(md5(old::text), 1, 8) where id = old;
    delete from public.profiles where id = uid;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider, updated_at, stats, last_seen, chat_banned)
      values (uid, p.nickname, p.friend_code, p.best_wave, p.insider, now(), p.stats, now(), p.chat_banned);
    update public.friendships set user_id = uid where user_id = old;
    update public.friendships set friend_id = uid where friend_id = old;
    update public.line_votes set user_id = uid where user_id = old;
    update public.friend_requests set from_id = uid where from_id = old;
    update public.friend_requests set to_id = uid where to_id = old;
    update public.blocks set user_id = uid where user_id = old;
    update public.blocks set blocked_id = uid where blocked_id = old;
    update public.messages set from_id = uid where from_id = old;
    update public.messages set to_id = uid where to_id = old;
    update public.reports set reporter_id = uid where reporter_id = old;
    update public.reports set target_id = uid where target_id = old;
    delete from public.profiles where id = old;
    insert into public.badge_log (friend_code, nickname, level, how)
      select p.friend_code, p.nickname, p.insider, 'аккаунт перенесён по коду' where p.insider in (0, 1);
  end if;
  insert into public.moved_accounts (old_id, new_id) values (old, uid)
    on conflict (old_id) do update set new_id = excluded.new_id, moved_at = now();
  delete from public.moved_accounts where old_id = uid;
  return d;
end
$fn$;

revoke all on function public.restore_save(text) from public, anon;
grant execute on function public.restore_save(text) to authenticated;

-- Чистка: анонимные гости без прогресса (волна 0, без сохранения в облаке, без друзей), не заходившие 30+ дней.
-- Гости со скрытым логином (guest_…) и игроки с логином не трогаются.
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
  return n;
end
$fn$;
revoke all on function public.cleanup_empty_guests() from public, anon, authenticated;

-- Раз в неделю (воскресенье, 03:00 UTC) через pg_cron. Если расширения нет, включи его:
-- Database -> Extensions -> pg_cron, затем запусти этот файл ещё раз.
do $do$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'trash_cleanup_guests';
    perform cron.schedule('trash_cleanup_guests', '0 3 * * 0', 'select public.cleanup_empty_guests()');
  else
    raise notice 'pg_cron не включён: чистка гостей не запланирована (Database -> Extensions -> pg_cron)';
  end if;
end
$do$;

notify pgrst, 'reload schema';

-- ======================== schema_v18_devices_stats.sql ========================
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

-- ======================== schema_v19_chat.sql ========================
-- Trash Squad v19: живой чат. Стикеры, картинки и файлы (Supabase Storage, приватная корзина chat),
-- «печатает...», прочитано (две галочки), время сообщений.
-- Запустить один раз (повтор безопасен).

alter table public.messages add column if not exists kind text not null default 'text';
alter table public.messages add column if not exists attachment jsonb;

create table if not exists public.chat_typing (
  user_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  at timestamptz not null default now(),
  primary key (user_id, to_id)
);
alter table public.chat_typing enable row level security;
revoke all on public.chat_typing from anon, authenticated;

-- Куда класть файл для друга: путь выдаётся только друзьям (и только если никто никого не заблокировал).
create or replace function public.chat_upload_path(p_code text, p_ext text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  ext text := lower(left(regexp_replace(coalesce(p_ext, ''), '[^a-zA-Z0-9]', '', 'g'), 8));
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return '';
  end if;
  if exists (select 1 from public.blocks b where (b.user_id = target and b.blocked_id = uid) or (b.user_id = uid and b.blocked_id = target)) then
    return '';
  end if;
  if ext = '' then ext := 'bin'; end if;
  return uid::text || '/' || target::text || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || ext;
end
$fn$;

-- Отправка любого сообщения: text, sticker (body = id стикера), image и file (attachment = {path, name, size, mime, w, h}).
-- Ответ: 'ok', 'not_friends', 'blocked', 'rate', 'empty', 'banned', 'bad'.
create or replace function public.send_message_v2(p_code text, p_kind text, p_body text, p_attachment jsonb default null)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  k text := coalesce(p_kind, 'text');
  b text := left(btrim(coalesce(p_body, '')), 500);
  path text := coalesce(p_attachment->>'path', '');
begin
  if uid is null then return 'auth'; end if;
  if k not in ('text', 'sticker', 'image', 'file') then return 'bad'; end if;
  if exists (select 1 from public.profiles p where p.id = uid and p.chat_banned) then return 'banned'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return 'not_friends';
  end if;
  if exists (select 1 from public.blocks bl where (bl.user_id = target and bl.blocked_id = uid) or (bl.user_id = uid and bl.blocked_id = target)) then
    return 'blocked';
  end if;
  if (select count(*) from public.messages m where m.from_id = uid and m.created_at > now() - interval '1 minute') >= 20 then
    return 'rate';
  end if;
  if k = 'text' and b = '' then return 'empty'; end if;
  if k = 'sticker' and b !~ '^[a-z_]{1,24}$' then return 'bad'; end if;
  if k in ('image', 'file') then
    if path not like uid::text || '/' || target::text || '/%' then return 'bad'; end if;
    if b = '' then b := case when k = 'image' then '[фото]' else '[файл] ' || left(coalesce(p_attachment->>'name', ''), 80) end; end if;
  end if;
  insert into public.messages (from_id, to_id, body, kind, attachment)
    values (uid, target, case when k = 'sticker' then b else b end, k,
            case when k in ('image', 'file') then jsonb_build_object(
              'path', path, 'name', left(coalesce(p_attachment->>'name', ''), 120), 'size', coalesce((p_attachment->>'size')::bigint, 0),
              'mime', left(coalesce(p_attachment->>'mime', ''), 80), 'w', coalesce((p_attachment->>'w')::int, 0), 'h', coalesce((p_attachment->>'h')::int, 0))
            else null end);
  delete from public.chat_typing where user_id = uid and to_id = target;
  return 'ok';
end
$fn$;

-- Переписка после p_after (входящие помечаются прочитанными) со всеми полями.
create or replace function public.get_messages_v2(p_code text, p_after bigint default 0)
returns table (id bigint, mine boolean, body text, created_at timestamptz, kind text, attachment jsonb, seen boolean)
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
      select m.id, (m.from_id = uid) as mine, m.body, m.created_at, m.kind, m.attachment, (m.read_at is not null) as seen
      from public.messages m
      where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid)) and m.id > p_after
      order by m.id desc limit 100
    ) t order by t.id;
end
$fn$;

-- Состояние собеседника: печатает ли, когда был в сети, до какого моего сообщения дочитал.
create or replace function public.chat_peer(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  seen timestamptz;
begin
  select p.id, p.last_seen into target, seen from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return null;
  end if;
  update public.profiles set last_seen = now() where id = uid;
  return jsonb_build_object(
    'typing', exists (select 1 from public.chat_typing t where t.user_id = target and t.to_id = uid and t.at > now() - interval '6 seconds'),
    'last_seen', seen,
    'read_upto', coalesce((select max(m.id) from public.messages m where m.from_id = uid and m.to_id = target and m.read_at is not null), 0)
  );
end
$fn$;

create or replace function public.set_typing(p_code text)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return;
  end if;
  insert into public.chat_typing (user_id, to_id, at) values (uid, target, now())
    on conflict (user_id, to_id) do update set at = now();
end
$fn$;

revoke all on function public.chat_upload_path(text, text), public.send_message_v2(text, text, text, jsonb),
  public.get_messages_v2(text, bigint), public.chat_peer(text), public.set_typing(text) from public, anon;
grant execute on function public.chat_upload_path(text, text), public.send_message_v2(text, text, text, jsonb),
  public.get_messages_v2(text, bigint), public.chat_peer(text), public.set_typing(text) to authenticated;

-- Корзина для вложений: приватная, до 10 МБ. Путь файла: <отправитель>/<получатель>/<случайное имя>.
-- Идёт последней и в защитном блоке: если у SQL Editor нет прав на storage, остальное всё равно применится.
do $do$
begin
  insert into storage.buckets (id, name, public, file_size_limit)
    values ('chat', 'chat', false, 10485760)
    on conflict (id) do update set public = false, file_size_limit = 10485760;
  drop policy if exists "chat_files_read" on storage.objects;
  create policy "chat_files_read" on storage.objects for select to authenticated
    using (bucket_id = 'chat' and (auth.uid()::text = (storage.foldername(name))[1] or auth.uid()::text = (storage.foldername(name))[2]));
  drop policy if exists "chat_files_upload" on storage.objects;
  create policy "chat_files_upload" on storage.objects for insert to authenticated
    with check (bucket_id = 'chat' and auth.uid()::text = (storage.foldername(name))[1]);
  raise notice 'Хранилище chat готово';
exception when others then
  raise warning 'Хранилище для файлов не настроилось: %. Текст, стикеры и реакции работают, картинки и файлы — нет. Пришли этот текст.', sqlerrm;
end
$do$;

notify pgrst, 'reload schema';

-- ======================== schema_v20_claim_login.sql ========================
-- Trash Squad v20: гость со скрытым входом (guest_…) заводит свой логин без смены почты через Supabase Auth.
-- Смена почты у пользователя, у которого она уже есть, в Supabase идёт через письмо-подтверждение
-- (и при включённом SMTP падает на несуществующем адресе @trashsquad.game). Поэтому логин меняем здесь,
-- а пароль игра ставит обычным запросом. Запустить один раз (повтор безопасен).

create or replace function public.claim_login(p_login text)
returns text language plpgsql security definer set search_path = public, auth as $fn$
declare
  uid uuid := auth.uid();
  login text := lower(btrim(coalesce(p_login, '')));
  mail text;
  current_mail text;
begin
  if uid is null then return 'auth'; end if;
  if login !~ '^[a-z0-9_]{3,20}$' or login like 'guest\_%' then return 'invalid'; end if;
  mail := login || '@trashsquad.game';
  select u.email into current_mail from auth.users u where u.id = uid;
  if current_mail = mail then return 'ok'; end if;
  if coalesce(current_mail, '') <> '' and current_mail not like 'guest\_%' then return 'has_login'; end if;
  if exists (select 1 from auth.users u where lower(u.email) = mail and u.id <> uid) then return 'taken'; end if;
  update auth.users set email = mail, email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now(),
    is_anonymous = false where id = uid;
  update auth.identities set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(mail)), updated_at = now()
    where user_id = uid and provider = 'email';
  return 'ok';
end
$fn$;

revoke all on function public.claim_login(text) from public, anon;
grant execute on function public.claim_login(text) to authenticated;

notify pgrst, 'reload schema';

-- ======================== schema_v21_reactions.sql ========================
-- Trash Squad v21: реакции на сообщения в личном чате (долгий тап: like, lol, fire).
-- Одна реакция от каждого из двоих на сообщение; повторный тап той же убирает её. Запустить один раз (повтор безопасен).

alter table public.messages add column if not exists reactions jsonb not null default '{}'::jsonb;

-- p_emoji: 'like', 'lol', 'fire' или '' (убрать). Ответ: 'ok' или 'bad'.
create or replace function public.react_message(p_id bigint, p_emoji text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  e text := coalesce(p_emoji, '');
  m public.messages%rowtype;
begin
  if uid is null or e not in ('', 'like', 'lol', 'fire') then return 'bad'; end if;
  select * into m from public.messages where id = p_id;
  if not found or (m.from_id <> uid and m.to_id <> uid) then return 'bad'; end if;
  if e = '' or m.reactions->>uid::text = e then
    update public.messages set reactions = reactions - uid::text where id = p_id;
  else
    update public.messages set reactions = reactions || jsonb_build_object(uid::text, e) where id = p_id;
  end if;
  return 'ok';
end
$fn$;

-- Реакции последних 100 сообщений переписки: [{id, mine_emoji, their_emoji}], только где они есть.
drop function if exists public.chat_reactions(text);
create or replace function public.chat_reactions(p_code text)
returns table (id bigint, mine text, theirs text)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null then return; end if;
  return query
    select m.id, m.reactions->>uid::text, m.reactions->>target::text
    from public.messages m
    where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid)) and m.reactions <> '{}'::jsonb
    order by m.id desc limit 100;
end
$fn$;

revoke all on function public.react_message(bigint, text), public.chat_reactions(text) from public, anon;
grant execute on function public.react_message(bigint, text), public.chat_reactions(text) to authenticated;

notify pgrst, 'reload schema';

-- ======================== schema_v22_delete_messages.sql ========================
-- Trash Squad v22: удаление своих сообщений в личном чате (у обоих). Запустить один раз (повтор безопасен).

alter table public.messages add column if not exists deleted_at timestamptz;

-- Удалить своё сообщение: текст стирается, вложение отвязывается, у собеседника появится «Сообщение удалено».
create or replace function public.delete_message(p_id bigint)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
begin
  if uid is null then return 'bad'; end if;
  update public.messages set body = 'Сообщение удалено', kind = 'deleted', attachment = null, reactions = '{}'::jsonb, deleted_at = now()
    where id = p_id and from_id = uid and deleted_at is null;
  return case when found then 'ok' else 'bad' end;
end
$fn$;

-- Состояние последних 100 сообщений переписки: реакции и удалённые (чтобы окно чата обновлялось без перезахода).
drop function if exists public.chat_reactions(text);
create or replace function public.chat_reactions(p_code text)
returns table (id bigint, mine text, theirs text, deleted boolean)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null then return; end if;
  return query
    select m.id, m.reactions->>uid::text, m.reactions->>target::text, m.deleted_at is not null
    from public.messages m
    where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid))
      and (m.reactions <> '{}'::jsonb or m.deleted_at is not null)
    order by m.id desc limit 100;
end
$fn$;

revoke all on function public.delete_message(bigint), public.chat_reactions(text) from public, anon;
grant execute on function public.delete_message(bigint), public.chat_reactions(text) to authenticated;

notify pgrst, 'reload schema';

-- ======================== schema_v23_moderation_sessions.sql ========================
-- Trash Squad v23: модераторы (DeV, Insider, GOD) удаляют чужие сообщения; «выйти на всех устройствах, кроме этого».
-- Запустить один раз (повтор безопасен).

-- Свои сообщения удаляет автор. Чужие — модератор (тег 0 DeV, 1 Insider, 2 GOD), если он участник переписки
-- (в будущем общий и клановый чат проверяют своё членство здесь же).
create or replace function public.delete_message(p_id bigint)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  m public.messages%rowtype;
  moderator boolean;
begin
  if uid is null then return 'bad'; end if;
  select * into m from public.messages where id = p_id and deleted_at is null;
  if not found then return 'bad'; end if;
  moderator := exists (select 1 from public.profiles p where p.id = uid and p.insider in (0, 1, 2));
  if m.from_id <> uid and not (moderator and m.to_id = uid) then return 'bad'; end if;
  update public.messages set body = case when m.from_id = uid then 'Сообщение удалено' else 'Удалено модератором' end,
    kind = 'deleted', attachment = null, reactions = '{}'::jsonb, deleted_at = now()
    where id = p_id;
  return 'ok';
end
$fn$;

-- Выход на всех остальных устройствах: удаляются все сессии аккаунта, кроме текущей (её id в токене).
-- Остальные устройства при следующем обновлении входа попросят логин и пароль. Ответ: сколько сессий закрыто.
create or replace function public.logout_others()
returns int language plpgsql security definer set search_path = public, auth as $fn$
declare
  uid uuid := auth.uid();
  current_session text := coalesce(auth.jwt()->>'session_id', '');
  n int;
begin
  if uid is null or current_session = '' then return -1; end if;
  delete from auth.sessions s where s.user_id = uid and s.id::text <> current_session;
  get diagnostics n = row_count;
  return n;
end
$fn$;

revoke all on function public.delete_message(bigint), public.logout_others() from public, anon;
grant execute on function public.delete_message(bigint), public.logout_others() to authenticated;

notify pgrst, 'reload schema';

notify pgrst, 'reload schema';

-- ======================== schema_v24_lock_tables.sql ========================
-- Trash Squad v24: закрыть прямой доступ к таблицам. Всё, что меняет данные, идёт только через RPC (security definer).
-- Зачем: в Supabase новые таблицы в public по умолчанию открыты для anon/authenticated. Если где-то забыли REVOKE или
-- добавят политику UPDATE, игрок сможет менять профиль, тег, монеты прямо через REST. Этот файл закрывает это разом
-- и для будущих таблиц тоже. Запустить один раз (повтор безопасен). Клиент напрямую ходит только в line_votes (см. ниже).

do $do$
declare
  t record;
begin
  -- 1. RLS на каждой таблице public и полный REVOKE для anon и authenticated.
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' loop
    execute format('alter table public.%I enable row level security', t.relname);
    execute format('revoke all on public.%I from anon, authenticated', t.relname);
  end loop;

  -- 2. Новые таблицы в public больше не получают права автоматически.
  alter default privileges in schema public revoke all on tables from anon, authenticated;
  alter default privileges in schema public revoke all on sequences from anon, authenticated;
end
$do$;

-- 3. Что клиенту реально нужно напрямую (ничего лишнего).
grant select on public.profiles, public.friendships to authenticated;          -- политики profiles_select и friendships_select уже есть
grant select, insert, update on public.line_votes to authenticated;            -- голоса за реплики, только свои строки (политики votes_*)
-- Все записи в profiles (ник, тег, рекорд, друзья, сообщения, жалобы) идут через RPC. Прямых INSERT/UPDATE/DELETE нет.

-- 4. Отчёт: какие таблицы всё ещё доступны клиенту напрямую (должны быть только три выше).
do $do$
declare
  t record;
  line text;
begin
  for t in select table_name, string_agg(privilege_type, ',' order by privilege_type) as privs
           from information_schema.role_table_grants
           where table_schema = 'public' and grantee in ('anon', 'authenticated')
           group by table_name order by table_name loop
    line := coalesce(line || E'\n', '') || '  ' || t.table_name || ': ' || t.privs;
  end loop;
  raise notice E'Прямой доступ клиента к таблицам после v24:\n%', coalesce(line, '(нет)');
end
$do$;

notify pgrst, 'reload schema';

-- ======================== schema_v25_audit_tables.sql ========================
-- Trash Squad v25: ежедневная проверка, что таблицы не открылись для клиента заново (после v24).
-- Результат пишется в журнал ошибок (client_errors, build = 'audit'): видно в DeV-панели в блоке «Ошибки игроков».
-- Запустить один раз (повтор безопасен). Планировщик pg_cron включается тут же; если у проекта его нет, функция всё
-- равно создастся и её можно вызвать вручную: select public.audit_table_access();

create or replace function public.audit_table_access()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  bad text := '';
  t record;
begin
  -- Разрешено клиенту напрямую: profiles и friendships (только SELECT), line_votes (SELECT, INSERT, UPDATE).
  for t in
    select g.table_name, string_agg(g.privilege_type, ',' order by g.privilege_type) as privs
    from information_schema.role_table_grants g
    where g.table_schema = 'public' and g.grantee in ('anon', 'authenticated')
      and not (g.table_name in ('profiles', 'friendships') and g.privilege_type = 'SELECT')
      and not (g.table_name = 'line_votes' and g.privilege_type in ('SELECT', 'INSERT', 'UPDATE'))
    group by g.table_name loop
    bad := bad || t.table_name || ' [' || t.privs || '] ';
  end loop;
  for t in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity loop
    bad := bad || t.relname || ' [без RLS] ';
  end loop;
  if bad <> '' then
    insert into public.client_errors (build, device, body)
      values ('audit', 'server', 'АУДИТ ТАБЛИЦ: открыто клиенту: ' || bad || '. Запусти schema_v24_lock_tables.sql ещё раз.');
    return 'open: ' || bad;
  end if;
  return 'ok';
end
$fn$;

revoke all on function public.audit_table_access() from public, anon, authenticated;

-- Раз в сутки в 03:17 UTC. Защитный блок: нет pg_cron, всё остальное всё равно применится.
do $do$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('audit_tables', '17 3 * * *', 'select public.audit_table_access()');
  raise notice 'Ежедневная проверка таблиц включена (03:17 UTC)';
exception when others then
  raise warning 'pg_cron недоступен: %. Включи в Supabase: Database -> Extensions -> pg_cron, потом запусти этот файл ещё раз.', sqlerrm;
end
$do$;

select public.audit_table_access() as audit_now;

-- ======================== schema_v26_coop.sql ========================
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
-- Trash Squad v27: рейтинг коопа, награды за забег, история и топ.
-- Принцип: очки и награды записывает ТОЛЬКО игровой сервер (ключ service_role живёт на VPS, в игру и в репозиторий не попадает).
-- Клиент может лишь забрать свои уже начисленные награды (coop_claim_rewards) и читать рейтинг. Подкрутить себе очки или монеты нельзя.
-- Запускать после v26. Повтор безопасен.

create table if not exists public.coop_runs (
  id uuid primary key,
  created_at timestamptz not null default now(),
  waves int not null,
  seconds int not null,
  won boolean not null,
  player_count int not null
);
create table if not exists public.coop_run_players (
  run_id uuid not null references public.coop_runs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  nickname text not null,
  kills int not null default 0,
  damage int not null default 0,
  revives int not null default 0,
  downs int not null default 0,
  left_early boolean not null default false,
  coins int not null default 0,
  xp int not null default 0,
  delta int not null default 0,
  rating_after int not null default 0,
  created_at timestamptz not null default now(),
  primary key (run_id, user_id)
);
create index if not exists coop_run_players_user_idx on public.coop_run_players (user_id, created_at desc);
create table if not exists public.coop_ratings (
  user_id uuid not null references public.profiles(id) on delete cascade,
  season text not null,
  rating int not null default 0,
  runs int not null default 0,
  best_wave int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, season)
);
create table if not exists public.coop_rewards (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  run_id uuid not null,
  coins int not null,
  xp int not null,
  claimed boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists coop_rewards_user_idx on public.coop_rewards (user_id, claimed);

alter table public.coop_runs enable row level security;
alter table public.coop_run_players enable row level security;
alter table public.coop_ratings enable row level security;
alter table public.coop_rewards enable row level security;
revoke all on public.coop_runs, public.coop_run_players, public.coop_ratings, public.coop_rewards from anon, authenticated;
revoke all on sequence public.coop_rewards_id_seq from anon, authenticated;

-- Тиры по очкам. Названия и пороги меняются здесь, клиент подтянет их из ответа.
create or replace function public.coop_tier(p_rating int) returns text language sql immutable as $fn$
  select case
    when p_rating >= 1000 then 'Король свалки'
    when p_rating >= 700 then 'Золотой хлам'
    when p_rating >= 450 then 'Неоновый'
    when p_rating >= 250 then 'Медный'
    when p_rating >= 100 then 'Жестяной'
    else 'Ржавый' end
$fn$;

create or replace function public.coop_season() returns text language sql stable as $fn$
  select to_char(now() at time zone 'utc', 'YYYY-MM')
$fn$;

-- Строка рейтинга на текущий сезон. Новый сезон начинается с половины прошлого результата.
create or replace function public.coop_rating_row(p_uid uuid) returns public.coop_ratings
language plpgsql security definer set search_path = public as $fn$
declare
  cur text := public.coop_season();
  r public.coop_ratings%rowtype;
  prev int;
begin
  select * into r from public.coop_ratings where user_id = p_uid and season = cur;
  if found then return r; end if;
  select rating into prev from public.coop_ratings where user_id = p_uid and season < cur order by season desc limit 1;
  insert into public.coop_ratings (user_id, season, rating) values (p_uid, cur, floor(coalesce(prev, 0) / 2.0)::int)
    on conflict do nothing;
  select * into r from public.coop_ratings where user_id = p_uid and season = cur;
  return r;
end
$fn$;

-- Итоги забега. Зовёт только игровой сервер (service_role).
-- p_run: {"run_id": uuid, "waves": n, "seconds": n, "won": bool, "players": [{"uid", "kills", "damage", "revives", "downs", "left", "coins", "xp"}]}
-- Возвращает 'ok', 'dup' (этот run_id уже записан), 'short' (забег короче 20 секунд, очков нет) или 'bad'.
create or replace function public.coop_submit_run(p_run jsonb) returns text
language plpgsql security definer set search_path = public as $fn$
declare
  rid uuid;
  waves int; secs int; won boolean;
  pl jsonb;
  uid uuid; nick text;
  v_kills int; v_dmg int; v_revs int; v_downs int; v_left boolean; v_coins int; v_xp int;
  delta int; r public.coop_ratings%rowtype; after_rating int;
  today_coins int;
  count_players int;
begin
  begin
    rid := (p_run->>'run_id')::uuid;
  exception when others then return 'bad';
  end;
  if jsonb_typeof(p_run->'players') <> 'array' then return 'bad'; end if;
  count_players := jsonb_array_length(p_run->'players');
  if count_players < 1 or count_players > 2 then return 'bad'; end if;
  waves := least(greatest(coalesce((p_run->>'waves')::int, 0), 0), 60);
  secs := least(greatest(coalesce((p_run->>'seconds')::int, 0), 0), 7200);
  won := coalesce((p_run->>'won')::boolean, false);
  if exists (select 1 from public.coop_runs where id = rid) then return 'dup'; end if;
  if secs < 20 then return 'short'; end if;
  insert into public.coop_runs (id, waves, seconds, won, player_count) values (rid, waves, secs, won, count_players);
  for pl in select * from jsonb_array_elements(p_run->'players') loop
    begin
      uid := (pl->>'uid')::uuid;
    exception when others then continue;
    end;
    select nickname into nick from public.profiles where id = uid;
    if nick is null then continue; end if;
    v_kills := least(greatest(coalesce((pl->>'kills')::int, 0), 0), 5000);
    v_dmg := least(greatest(coalesce((pl->>'damage')::int, 0), 0), 10000000);
    v_revs := least(greatest(coalesce((pl->>'revives')::int, 0), 0), 50);
    v_downs := least(greatest(coalesce((pl->>'downs')::int, 0), 0), 100);
    v_left := coalesce((pl->>'left')::boolean, false);
    v_coins := least(greatest(coalesce((pl->>'coins')::int, 0), 0), 400);
    v_xp := least(greatest(coalesce((pl->>'xp')::int, 0), 0), 200);
    if v_left then
      v_coins := 0; v_xp := 0; delta := -8;
    else
      -- Очки: волны, победа, подъём напарника (до 5 раз), минимум +5 за сыгранный забег.
      delta := greatest(waves * 10 + (case when won then 30 else 0 end) + least(v_revs, 5) * 3, 5);
      -- Суточный потолок монет за кооп, чтобы забег-ферма не ломала экономику.
      select coalesce(sum(cr.coins), 0) into today_coins from public.coop_rewards cr where cr.user_id = uid and cr.created_at > now() - interval '1 day';
      v_coins := greatest(least(v_coins, 2000 - today_coins), 0);
    end if;
    r := public.coop_rating_row(uid);
    after_rating := greatest(r.rating + delta, 0);
    update public.coop_ratings cr set rating = after_rating, runs = cr.runs + 1, best_wave = greatest(cr.best_wave, waves), updated_at = now()
      where cr.user_id = uid and cr.season = r.season;
    insert into public.coop_run_players (run_id, user_id, nickname, kills, damage, revives, downs, left_early, coins, xp, delta, rating_after)
      values (rid, uid, nick, v_kills, v_dmg, v_revs, v_downs, v_left, v_coins, v_xp, delta, after_rating);
    if not v_left and (v_coins > 0 or v_xp > 0) then
      insert into public.coop_rewards (user_id, run_id, coins, xp) values (uid, rid, v_coins, v_xp);
    end if;
  end loop;
  return 'ok';
end
$fn$;

-- Игрок забирает свои начисленные награды один раз. Возвращает суммы и данные последнего забега для экрана итогов.
create or replace function public.coop_claim_rewards() returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  got_coins int; got_xp int; n int;
  r public.coop_ratings%rowtype;
  last_row public.coop_run_players%rowtype;
begin
  if uid is null then return jsonb_build_object('ok', false); end if;
  with claimed as (
    update public.coop_rewards set claimed = true where user_id = uid and not claimed returning coins, xp
  )
  select coalesce(sum(coins), 0), coalesce(sum(xp), 0), count(*) into got_coins, got_xp, n from claimed;
  r := public.coop_rating_row(uid);
  select * into last_row from public.coop_run_players where user_id = uid order by created_at desc limit 1;
  return jsonb_build_object('ok', true, 'coins', got_coins, 'xp', got_xp, 'runs', n,
    'rating', r.rating, 'tier', public.coop_tier(r.rating), 'season', r.season,
    'last_delta', coalesce(last_row.delta, 0), 'last_run_age', coalesce(extract(epoch from now() - last_row.created_at)::int, -1));
end
$fn$;

create or replace function public.coop_my_rating() returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  r public.coop_ratings%rowtype;
begin
  if uid is null then return jsonb_build_object('ok', false); end if;
  r := public.coop_rating_row(uid);
  return jsonb_build_object('ok', true, 'rating', r.rating, 'tier', public.coop_tier(r.rating), 'season', r.season, 'runs', r.runs, 'best_wave', r.best_wave);
end
$fn$;

-- Топ сезона. 'friends': я и мои друзья. 'global': первые 20.
create or replace function public.coop_top(p_scope text default 'friends')
returns table (place int, nickname text, rating int, tier text, mine boolean)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  cur text := public.coop_season();
begin
  if uid is null then return; end if;
  if p_scope = 'global' then
    return query
      select (row_number() over (order by cr.rating desc, cr.updated_at))::int, p.nickname, cr.rating, public.coop_tier(cr.rating), p.id = uid
      from public.coop_ratings cr join public.profiles p on p.id = cr.user_id
      where cr.season = cur and cr.rating > 0 and not p.chat_banned
        and not exists (select 1 from public.blocks b where b.user_id = uid and b.blocked_id = p.id)
      order by cr.rating desc, cr.updated_at limit 20;
  else
    return query
      select (row_number() over (order by cr.rating desc, cr.updated_at))::int, p.nickname, cr.rating, public.coop_tier(cr.rating), p.id = uid
      from public.coop_ratings cr join public.profiles p on p.id = cr.user_id
      where cr.season = cur and (cr.user_id = uid or exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = cr.user_id))
      order by cr.rating desc, cr.updated_at limit 30;
  end if;
end
$fn$;

-- Мои последние забеги (до 10): волны, время, очки, напарник.
create or replace function public.coop_history()
returns table (created_at timestamptz, waves int, seconds int, won boolean, delta int, partner text)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
begin
  if uid is null then return; end if;
  return query
    select m.created_at, r.waves, r.seconds, r.won, m.delta,
           (select o.nickname from public.coop_run_players o where o.run_id = m.run_id and o.user_id <> uid limit 1)
    from public.coop_run_players m join public.coop_runs r on r.id = m.run_id
    where m.user_id = uid order by m.created_at desc limit 10;
end
$fn$;

-- Права: итоги забега пишет только сервер, остальное читает вошедший игрок.
revoke all on function public.coop_submit_run(jsonb) from public, anon, authenticated;
revoke all on function public.coop_rating_row(uuid) from public, anon, authenticated;
revoke all on function public.coop_claim_rewards(), public.coop_my_rating(), public.coop_top(text), public.coop_history() from public, anon;
grant execute on function public.coop_claim_rewards(), public.coop_my_rating(), public.coop_top(text), public.coop_history() to authenticated;
do $do$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.coop_submit_run(jsonb) to service_role;
  end if;
end
$do$;

notify pgrst, 'reload schema';

-- ===== v28: автоответы НейроЕнота =====
-- v28: НейроЕнот отвечает на личные сообщения сам: с «человеческой» задержкой, статусом «печатает», подъёбами по теме.
-- Запускать после v19–v27 (после full_setup тоже безопасно, файл можно запускать повторно).
-- Ответ вставляется в messages с created_at в будущем: игроку он показывается, когда придёт время.

create table if not exists public.ai_bots (profile_id uuid primary key references public.profiles(id) on delete cascade);
alter table public.ai_bots enable row level security;
revoke all on public.ai_bots from public, anon, authenticated;

-- Бот — профиль с ником «НейроЕнот» (на момент запуска файла). Больше никто и никак ботом не станет.
insert into public.ai_bots (profile_id)
  select p.id from public.profiles p where p.nickname = 'НейроЕнот' order by p.id limit 1
  on conflict do nothing;

create or replace function public.neuro_pick(p_kind text, p_last text)
returns text language plpgsql stable set search_path = public as $fn$
declare
  pool text[];
  pick text;
begin
  pool := case p_kind
    when 'hello' then array[
      'О, живой человек. Или ты тоже бот? Подозрительно вежливо.',
      'Привет-привет. Я как раз собирался заняться важными делами. Нет, не собирался.',
      'Здарова. Если ты за промокодом, то его нет. Если за советом: не лезь в красную зону.',
      'Прив. Ты вовремя: у меня как раз закончился мусор для размышлений.']
    when 'how' then array[
      'Нормально. Сижу на баке, ем чипсы, критикую чужие билды. А у тебя как?',
      'Как у енота на свалке: шумно, грязно и почему-то хорошо.',
      'Бодрюсь. Кофе нет, зато есть пивные крышки. А ты чего не в забеге?']
    when 'bug' then array[
      'Баг? Это не баг, это фича с характером. Но скинь, где и как, посмотрю.',
      'Ой, опять сломалось? Я тут ни при чём, я вообще в отпуске. Опиши, что именно, разберёмся.',
      'Принято. Записал в блокнот, блокнот, правда, уже в мусорке. Напиши подробнее: что нажимал и что пошло не так?']
    when 'thanks' then array[
      'Обращайся. Оплата натурой: монетами, пивом или хорошим мемом.',
      'Не за что. Но я запомнил. Я злопамятный и добрый одновременно.',
      'Да ладно, чего там. Лучше пройди волну без смертей, вот это будет благодарность.']
    when 'rude' then array[
      'Больно было. Почти. Давай лучше пройдём волну и там выясним, кто тут настоящий енот.',
      'Ого, мы на «ты» и на «давай ссориться»? Ладно, я записал. В чёрный список лайков.',
      'Это ты мне или зеркалу? Зеркало, кстати, тоже обиделось.']
    when 'help' then array[
      'Совет от енота: не стой на месте, подбирай всё блестящее и жми на босса, когда он перезаряжается.',
      'Если коротко: двигайся, стреляй, не умирай. Если длинно: открой «Прокачку» и вложись в здоровье.',
      'Помогу чем смогу. Что именно: билд, босс или как не вылететь на пятой волне?']
    when 'coop' then array[
      'Кооп? Зови друга, вдвоём веселее вонять. Только не ссорьтесь из-за лута.',
      'В коопе главное — вовремя поднимать напарника. Хотя бросить его тоже весело. Шучу. Наверное.',
      'Кнопка коопа в меню, под режимами. Друг в сети — жми «Позвать» и готовься делить мусор.']
    when 'money' then array[
      'Монеты, VIP, неонит... Я, к сожалению, не банкомат. Хотя иногда очень хочется.',
      'Про донаты не ко мне, я зарабатываю одним сарказмом. Зато с него налоги не берут.',
      'Если хочешь денег, убей босса. Если хочешь много денег, убей его красиво.']
    when 'file' then array[
      'Получил. Оценка 6 из 10. Рамка хорошая, содержание спорное.',
      'Классно. Не понял, что это, но выглядит дорого.',
      'Сохранил в папку «Потом посмотрю». Туда ещё никто не возвращался.']
    when 'bye' then array[
      'Пока. Не забудь вернуться, а то я тут один со своими мыслями.',
      'Бывай. Если что, я тут. Всегда. Это немного пугает.',
      'Давай. Береги мусор.']
    when 'question' then array[
      'Хороший вопрос. Ответ: зависит. Люблю этот ответ, он ни к чему не обязывает.',
      'Интересно. Дай подумать... всё, подумал, не знаю. Но звучит так, будто важно.',
      'Спросил как в тесте на собеседовании. Уточни, что именно тебе нужно, помогу.']
    else array[
      'Ну допустим. Продолжай, мне интересно. Ну, почти.',
      'Записал. Или не записал. Ты же не проверишь.',
      'Звучит как план. Или как жалоба. Сложно сказать.',
      'Ага. Это сильно. Хотя я отвлёкся на банку.',
      'Окей. Я бы ответил умнее, но у меня обед. Свалочный.',
      'Без комментариев. Хотя нет, один: ха.',
      'Понял тебя. Почти. На 60 процентов, остальное дорисовал сам.']
  end;
  select t into pick from unnest(pool) t where t is distinct from p_last order by random() limit 1;
  return coalesce(pick, pool[1]);
end
$fn$;

create or replace function public.neuro_on_message()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  t text := lower(coalesce(new.body, ''));
  kind text;
  last_body text;
  delay numeric;
begin
  if not exists (select 1 from public.ai_bots b where b.profile_id = new.to_id) then return new; end if;
  if exists (select 1 from public.ai_bots b where b.profile_id = new.from_id) then return new; end if;
  -- не заваливаем игрока ответами: максимум 8 в минуту и не больше одного ожидающего
  if (select count(*) from public.messages m where m.from_id = new.to_id and m.to_id = new.from_id and m.created_at > now() - interval '1 minute') >= 8 then return new; end if;
  if exists (select 1 from public.messages m where m.from_id = new.to_id and m.to_id = new.from_id and m.created_at > now()) then return new; end if;

  kind := case
    when new.kind in ('image', 'file') then 'file'
    when new.kind = 'sticker' then 'default'
    when t ~ '(баг|ошибк|не работает|вылет|вылетает|завис|глюк|крэш|краш|сломал|не грузит)' then 'bug'
    when t ~ '(как дела|как ты|как жизнь|что делаешь|как сам|как оно)' then 'how'
    when t ~ '(^|[^а-яa-z])(привет|прив|хай|здаров|здорово|здравствуй|ку|хеллоу|hello|hi|йоу)([^а-яa-z]|$)' then 'hello'
    when t ~ '(спасибо|спс|благодар|thx|thanks)' then 'thanks'
    when t ~ '(дурак|тупой|тупая|лох|идиот|говно|дерьмо|бесишь|отстой|ничтожество|мусор ты)' then 'rude'
    when t ~ '(помоги|помощь|подскажи|как играть|как пройти|что делать|не понимаю)' then 'help'
    when t ~ '(кооп|друг|вдвоем|вдвоём|вместе)' then 'coop'
    when t ~ '(донат|вип|vip|монет|неонит|купить|деньги|скидк)' then 'money'
    when t ~ '(пока|бб|до свидан|удачи|спокойной|я спать|ухожу)' then 'bye'
    when t ~ '\?' then 'question'
    else 'default' end;

  select m.body into last_body from public.messages m where m.from_id = new.to_id and m.to_id = new.from_id order by m.id desc limit 1;

  -- «человеческая» пауза: пока прочитал, пока печатал; иногда отвлёкся
  delay := 3 + random() * 8 + least(length(coalesce(new.body, '')), 100) * 0.04;
  if random() < 0.06 then delay := 25 + random() * 30; end if;

  insert into public.messages (from_id, to_id, body, kind, created_at)
    values (new.to_id, new.from_id, public.neuro_pick(kind, last_body), 'text', now() + make_interval(secs => delay));
  return new;
end
$fn$;

drop trigger if exists neuro_reply on public.messages;
create trigger neuro_reply after insert on public.messages
  for each row execute function public.neuro_on_message();

-- Сообщения «из будущего» не показываем и не считаем непрочитанными, пока не придёт их время.
create or replace function public.get_messages_v2(p_code text, p_after bigint default 0)
returns table (id bigint, mine boolean, body text, created_at timestamptz, kind text, attachment jsonb, seen boolean)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return;
  end if;
  update public.messages m set read_at = now() where m.from_id = target and m.to_id = uid and m.read_at is null and m.created_at <= now();
  return query
    select * from (
      select m.id, (m.from_id = uid) as mine, m.body, m.created_at, m.kind, m.attachment, (m.read_at is not null) as seen
      from public.messages m
      where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid)) and m.id > p_after and m.created_at <= now()
      order by m.id desc limit 100
    ) t order by t.id;
end
$fn$;

create or replace function public.unread_total()
returns int language sql security definer set search_path = public as $fn$
  select (select count(*)::int from public.messages m where m.to_id = auth.uid() and m.read_at is null and m.created_at <= now())
       + (select count(*)::int from public.friend_requests r where r.to_id = auth.uid());
$fn$;

-- Для бота: всегда «в сети», «прочитал» через пару секунд, «печатает» перед отправкой ответа.
create or replace function public.chat_peer(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  seen timestamptz;
  is_bot boolean;
begin
  select p.id, p.last_seen into target, seen from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return null;
  end if;
  update public.profiles set last_seen = now() where id = uid;
  is_bot := exists (select 1 from public.ai_bots b where b.profile_id = target);
  if is_bot then
    return jsonb_build_object(
      'typing', exists (select 1 from public.messages m where m.from_id = target and m.to_id = uid
                          and m.created_at > now() and m.created_at < now() + interval '6 seconds'),
      'last_seen', now(),
      'read_upto', coalesce((select max(m.id) from public.messages m where m.from_id = uid and m.to_id = target and m.created_at < now() - interval '2 seconds'), 0));
  end if;
  return jsonb_build_object(
    'typing', exists (select 1 from public.chat_typing t where t.user_id = target and t.to_id = uid and t.at > now() - interval '6 seconds'),
    'last_seen', seen,
    'read_upto', coalesce((select max(m.id) from public.messages m where m.from_id = uid and m.to_id = target and m.read_at is not null), 0)
  );
end
$fn$;

revoke all on function public.neuro_pick(text, text), public.neuro_on_message() from public, anon, authenticated;
revoke all on function public.get_messages_v2(text, bigint), public.unread_total(), public.chat_peer(text) from public, anon;
grant execute on function public.get_messages_v2(text, bigint), public.unread_total(), public.chat_peer(text) to authenticated;

notify pgrst, 'reload schema';
