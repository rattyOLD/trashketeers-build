-- Trash Squad: ПОЛНАЯ настройка сервера одним файлом (все schema*.sql по порядку, v1..v16).
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

notify pgrst, 'reload schema';
