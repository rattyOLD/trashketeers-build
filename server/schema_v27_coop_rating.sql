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
