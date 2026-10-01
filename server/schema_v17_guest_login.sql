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
