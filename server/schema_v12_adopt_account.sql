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
