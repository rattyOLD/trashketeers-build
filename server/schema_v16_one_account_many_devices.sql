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
