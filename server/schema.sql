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
