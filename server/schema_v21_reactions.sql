-- Trash Squad v21: реакции на сообщения в личном чате (долгий тап: like, lol, fire).
-- Одна реакция от каждого из двоих на сообщение; повторный тап той же убирает её. Запустить один раз (повтор безопасен).

alter table public.messages add column if not exists reactions jsonb not null default '{}'::jsonb;

-- p_emoji: 'like', 'lol', 'fire' или '' (убрать). Ответ: 'ok' или 'bad'.
create or replace function public.react_message(p_id bigint, p_emoji text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  e text := coalesce(p_emoji, '');
  m public.messages%rowtype;
begin
  if uid is null or e not in ('', 'like', 'lol', 'fire') then return 'bad'; end if;
  select * into m from public.messages where id = p_id;
  if not found or (m.from_id <> uid and m.to_id <> uid) then return 'bad'; end if;
  if e = '' or m.reactions->>uid::text = e then
    update public.messages set reactions = reactions - uid::text where id = p_id;
  else
    update public.messages set reactions = reactions || jsonb_build_object(uid::text, e) where id = p_id;
  end if;
  return 'ok';
end
$fn$;

-- Реакции последних 100 сообщений переписки: [{id, mine_emoji, their_emoji}], только где они есть.
create or replace function public.chat_reactions(p_code text)
returns table (id bigint, mine text, theirs text)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null then return; end if;
  return query
    select m.id, m.reactions->>uid::text, m.reactions->>target::text
    from public.messages m
    where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid)) and m.reactions <> '{}'::jsonb
    order by m.id desc limit 100;
end
$fn$;

revoke all on function public.react_message(bigint, text), public.chat_reactions(text) from public, anon;
grant execute on function public.react_message(bigint, text), public.chat_reactions(text) to authenticated;

notify pgrst, 'reload schema';
