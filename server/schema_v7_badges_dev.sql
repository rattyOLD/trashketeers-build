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
