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
