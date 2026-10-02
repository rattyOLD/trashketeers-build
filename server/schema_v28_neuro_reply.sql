-- v28: НейроЕнот отвечает на личные сообщения сам: с «человеческой» задержкой, статусом «печатает», подъёбами по теме.
-- Запускать после v19–v27 (после full_setup тоже безопасно, файл можно запускать повторно).
-- Ответ вставляется в messages с created_at в будущем: игроку он показывается, когда придёт время.

create table if not exists public.ai_bots (profile_id uuid primary key references public.profiles(id) on delete cascade);
alter table public.ai_bots enable row level security;
revoke all on public.ai_bots from public, anon, authenticated;

-- Бот — профиль с ником «НейроЕнот» (на момент запуска файла). Больше никто и никак ботом не станет.
insert into public.ai_bots (profile_id)
  select p.id from public.profiles p where p.nickname = 'НейроЕнот' order by p.id limit 1
  on conflict do nothing;

create or replace function public.neuro_pick(p_kind text, p_last text)
returns text language plpgsql stable set search_path = public as $fn$
declare
  pool text[];
  pick text;
begin
  pool := case p_kind
    when 'hello' then array[
      'О, живой человек. Или ты тоже бот? Подозрительно вежливо.',
      'Привет-привет. Я как раз собирался заняться важными делами. Нет, не собирался.',
      'Здарова. Если ты за промокодом, то его нет. Если за советом: не лезь в красную зону.',
      'Прив. Ты вовремя: у меня как раз закончился мусор для размышлений.']
    when 'how' then array[
      'Нормально. Сижу на баке, ем чипсы, критикую чужие билды. А у тебя как?',
      'Как у енота на свалке: шумно, грязно и почему-то хорошо.',
      'Бодрюсь. Кофе нет, зато есть пивные крышки. А ты чего не в забеге?']
    when 'bug' then array[
      'Баг? Это не баг, это фича с характером. Но скинь, где и как, посмотрю.',
      'Ой, опять сломалось? Я тут ни при чём, я вообще в отпуске. Опиши, что именно, разберёмся.',
      'Принято. Записал в блокнот, блокнот, правда, уже в мусорке. Напиши подробнее: что нажимал и что пошло не так?']
    when 'thanks' then array[
      'Обращайся. Оплата натурой: монетами, пивом или хорошим мемом.',
      'Не за что. Но я запомнил. Я злопамятный и добрый одновременно.',
      'Да ладно, чего там. Лучше пройди волну без смертей, вот это будет благодарность.']
    when 'rude' then array[
      'Больно было. Почти. Давай лучше пройдём волну и там выясним, кто тут настоящий енот.',
      'Ого, мы на «ты» и на «давай ссориться»? Ладно, я записал. В чёрный список лайков.',
      'Это ты мне или зеркалу? Зеркало, кстати, тоже обиделось.']
    when 'help' then array[
      'Совет от енота: не стой на месте, подбирай всё блестящее и жми на босса, когда он перезаряжается.',
      'Если коротко: двигайся, стреляй, не умирай. Если длинно: открой «Прокачку» и вложись в здоровье.',
      'Помогу чем смогу. Что именно: билд, босс или как не вылететь на пятой волне?']
    when 'coop' then array[
      'Кооп? Зови друга, вдвоём веселее вонять. Только не ссорьтесь из-за лута.',
      'В коопе главное — вовремя поднимать напарника. Хотя бросить его тоже весело. Шучу. Наверное.',
      'Кнопка коопа в меню, под режимами. Друг в сети — жми «Позвать» и готовься делить мусор.']
    when 'money' then array[
      'Монеты, VIP, неонит... Я, к сожалению, не банкомат. Хотя иногда очень хочется.',
      'Про донаты не ко мне, я зарабатываю одним сарказмом. Зато с него налоги не берут.',
      'Если хочешь денег, убей босса. Если хочешь много денег, убей его красиво.']
    when 'file' then array[
      'Получил. Оценка 6 из 10. Рамка хорошая, содержание спорное.',
      'Классно. Не понял, что это, но выглядит дорого.',
      'Сохранил в папку «Потом посмотрю». Туда ещё никто не возвращался.']
    when 'bye' then array[
      'Пока. Не забудь вернуться, а то я тут один со своими мыслями.',
      'Бывай. Если что, я тут. Всегда. Это немного пугает.',
      'Давай. Береги мусор.']
    when 'question' then array[
      'Хороший вопрос. Ответ: зависит. Люблю этот ответ, он ни к чему не обязывает.',
      'Интересно. Дай подумать... всё, подумал, не знаю. Но звучит так, будто важно.',
      'Спросил как в тесте на собеседовании. Уточни, что именно тебе нужно, помогу.']
    else array[
      'Ну допустим. Продолжай, мне интересно. Ну, почти.',
      'Записал. Или не записал. Ты же не проверишь.',
      'Звучит как план. Или как жалоба. Сложно сказать.',
      'Ага. Это сильно. Хотя я отвлёкся на банку.',
      'Окей. Я бы ответил умнее, но у меня обед. Свалочный.',
      'Без комментариев. Хотя нет, один: ха.',
      'Понял тебя. Почти. На 60 процентов, остальное дорисовал сам.']
  end;
  select t into pick from unnest(pool) t where t is distinct from p_last order by random() limit 1;
  return coalesce(pick, pool[1]);
end
$fn$;

create or replace function public.neuro_on_message()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  t text := lower(coalesce(new.body, ''));
  kind text;
  last_body text;
  delay numeric;
begin
  if not exists (select 1 from public.ai_bots b where b.profile_id = new.to_id) then return new; end if;
  if exists (select 1 from public.ai_bots b where b.profile_id = new.from_id) then return new; end if;
  -- не заваливаем игрока ответами: максимум 8 в минуту и не больше одного ожидающего
  if (select count(*) from public.messages m where m.from_id = new.to_id and m.to_id = new.from_id and m.created_at > now() - interval '1 minute') >= 8 then return new; end if;
  if exists (select 1 from public.messages m where m.from_id = new.to_id and m.to_id = new.from_id and m.created_at > now()) then return new; end if;

  kind := case
    when new.kind in ('image', 'file') then 'file'
    when new.kind = 'sticker' then 'default'
    when t ~ '(баг|ошибк|не работает|вылет|вылетает|завис|глюк|крэш|краш|сломал|не грузит)' then 'bug'
    when t ~ '(как дела|как ты|как жизнь|что делаешь|как сам|как оно)' then 'how'
    when t ~ '(^|[^а-яa-z])(привет|прив|хай|здаров|здорово|здравствуй|ку|хеллоу|hello|hi|йоу)([^а-яa-z]|$)' then 'hello'
    when t ~ '(спасибо|спс|благодар|thx|thanks)' then 'thanks'
    when t ~ '(дурак|тупой|тупая|лох|идиот|говно|дерьмо|бесишь|отстой|ничтожество|мусор ты)' then 'rude'
    when t ~ '(помоги|помощь|подскажи|как играть|как пройти|что делать|не понимаю)' then 'help'
    when t ~ '(кооп|друг|вдвоем|вдвоём|вместе)' then 'coop'
    when t ~ '(донат|вип|vip|монет|неонит|купить|деньги|скидк)' then 'money'
    when t ~ '(пока|бб|до свидан|удачи|спокойной|я спать|ухожу)' then 'bye'
    when t ~ '\?' then 'question'
    else 'default' end;

  select m.body into last_body from public.messages m where m.from_id = new.to_id and m.to_id = new.from_id order by m.id desc limit 1;

  -- «человеческая» пауза: пока прочитал, пока печатал; иногда отвлёкся
  delay := 3 + random() * 8 + least(length(coalesce(new.body, '')), 100) * 0.04;
  if random() < 0.06 then delay := 25 + random() * 30; end if;

  insert into public.messages (from_id, to_id, body, kind, created_at)
    values (new.to_id, new.from_id, public.neuro_pick(kind, last_body), 'text', now() + make_interval(secs => delay));
  return new;
end
$fn$;

drop trigger if exists neuro_reply on public.messages;
create trigger neuro_reply after insert on public.messages
  for each row execute function public.neuro_on_message();

-- Сообщения «из будущего» не показываем и не считаем непрочитанными, пока не придёт их время.
create or replace function public.get_messages_v2(p_code text, p_after bigint default 0)
returns table (id bigint, mine boolean, body text, created_at timestamptz, kind text, attachment jsonb, seen boolean)
language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return;
  end if;
  update public.messages m set read_at = now() where m.from_id = target and m.to_id = uid and m.read_at is null and m.created_at <= now();
  return query
    select * from (
      select m.id, (m.from_id = uid) as mine, m.body, m.created_at, m.kind, m.attachment, (m.read_at is not null) as seen
      from public.messages m
      where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid)) and m.id > p_after and m.created_at <= now()
      order by m.id desc limit 100
    ) t order by t.id;
end
$fn$;

create or replace function public.unread_total()
returns int language sql security definer set search_path = public as $fn$
  select (select count(*)::int from public.messages m where m.to_id = auth.uid() and m.read_at is null and m.created_at <= now())
       + (select count(*)::int from public.friend_requests r where r.to_id = auth.uid());
$fn$;

-- Для бота: всегда «в сети», «прочитал» через пару секунд, «печатает» перед отправкой ответа.
create or replace function public.chat_peer(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  seen timestamptz;
  is_bot boolean;
begin
  select p.id, p.last_seen into target, seen from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return null;
  end if;
  update public.profiles set last_seen = now() where id = uid;
  is_bot := exists (select 1 from public.ai_bots b where b.profile_id = target);
  if is_bot then
    return jsonb_build_object(
      'typing', exists (select 1 from public.messages m where m.from_id = target and m.to_id = uid
                          and m.created_at > now() and m.created_at < now() + interval '6 seconds'),
      'last_seen', now(),
      'read_upto', coalesce((select max(m.id) from public.messages m where m.from_id = uid and m.to_id = target and m.created_at < now() - interval '2 seconds'), 0));
  end if;
  return jsonb_build_object(
    'typing', exists (select 1 from public.chat_typing t where t.user_id = target and t.to_id = uid and t.at > now() - interval '6 seconds'),
    'last_seen', seen,
    'read_upto', coalesce((select max(m.id) from public.messages m where m.from_id = uid and m.to_id = target and m.read_at is not null), 0)
  );
end
$fn$;

revoke all on function public.neuro_pick(text, text), public.neuro_on_message() from public, anon, authenticated;
revoke all on function public.get_messages_v2(text, bigint), public.unread_total(), public.chat_peer(text) from public, anon;
grant execute on function public.get_messages_v2(text, bigint), public.unread_total(), public.chat_peer(text) to authenticated;

notify pgrst, 'reload schema';
