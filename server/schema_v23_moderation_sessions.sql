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
