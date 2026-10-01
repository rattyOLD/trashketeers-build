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
