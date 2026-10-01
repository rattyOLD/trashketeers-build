-- Trash Squad: фильтр слов в личных сообщениях. Слова из таблицы banned_words заменяются на ***.
-- Список правится в Table Editor: добавляй основы слов строчными буквами. Можно запускать повторно.

create table if not exists public.banned_words (
  stem text primary key check (stem = lower(stem) and char_length(stem) >= 3)
);
alter table public.banned_words enable row level security;
revoke all on public.banned_words from anon, authenticated;

insert into public.banned_words (stem) values
  ('хуй'), ('хуе'), ('хуя'), ('хуё'), ('пизд'), ('ебан'), ('ебат'), ('ебал'), ('ебла'), ('ёбан'), ('ёбар'),
  ('блядь'), ('бляд'), ('блять'), ('мудак'), ('мудил'), ('гондон'), ('пидор'), ('пидар'), ('пидр'),
  ('залуп'), ('шлюх'), ('ублюд'), ('сучар'), ('уёб'), ('уеб'), ('долбоёб'), ('долбоеб'), ('нигер'), ('хохл'), ('чурк')
on conflict do nothing;

create or replace function public.clean_text(p_text text)
returns text language plpgsql stable security definer set search_path = public as $fn$
declare
  result text := p_text;
  w record;
begin
  for w in select stem from public.banned_words loop
    result := regexp_replace(result, '[[:alnum:]]*' || regexp_replace(w.stem, '([\\.^$*+?()\[\]{}|-])', '\\\1', 'g') || '[[:alnum:]]*', '***', 'gi');
  end loop;
  return result;
end
$fn$;
revoke all on function public.clean_text(text) from public, anon, authenticated;

create or replace function public.send_message(p_code text, p_body text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  text_body text := left(btrim(coalesce(p_body, '')), 500);
begin
  if uid is null then return 'auth'; end if;
  if text_body = '' then return 'empty'; end if;
  if exists (select 1 from public.profiles p where p.id = uid and p.chat_banned) then return 'banned'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return 'not_friends';
  end if;
  if exists (select 1 from public.blocks b where (b.user_id = target and b.blocked_id = uid) or (b.user_id = uid and b.blocked_id = target)) then
    return 'blocked';
  end if;
  if (select count(*) from public.messages m where m.from_id = uid and m.created_at > now() - interval '1 minute') >= 20 then
    return 'rate';
  end if;
  insert into public.messages (from_id, to_id, body) values (uid, target, public.clean_text(text_body));
  return 'ok';
end
$fn$;
revoke all on function public.send_message(text, text) from public, anon;
grant execute on function public.send_message(text, text) to authenticated;
