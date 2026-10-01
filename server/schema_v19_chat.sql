-- Trash Squad v19: живой чат. Стикеры, картинки и файлы (Supabase Storage, приватная корзина chat),
-- «печатает...», прочитано (две галочки), время сообщений.
-- Запустить один раз (повтор безопасен).

alter table public.messages add column if not exists kind text not null default 'text';
alter table public.messages add column if not exists attachment jsonb;

create table if not exists public.chat_typing (
  user_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  at timestamptz not null default now(),
  primary key (user_id, to_id)
);
alter table public.chat_typing enable row level security;
revoke all on public.chat_typing from anon, authenticated;

-- Куда класть файл для друга: путь выдаётся только друзьям (и только если никто никого не заблокировал).
create or replace function public.chat_upload_path(p_code text, p_ext text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  ext text := lower(left(regexp_replace(coalesce(p_ext, ''), '[^a-zA-Z0-9]', '', 'g'), 8));
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return '';
  end if;
  if exists (select 1 from public.blocks b where (b.user_id = target and b.blocked_id = uid) or (b.user_id = uid and b.blocked_id = target)) then
    return '';
  end if;
  if ext = '' then ext := 'bin'; end if;
  return uid::text || '/' || target::text || '/' || replace(gen_random_uuid()::text, '-', '') || '.' || ext;
end
$fn$;

-- Отправка любого сообщения: text, sticker (body = id стикера), image и file (attachment = {path, name, size, mime, w, h}).
-- Ответ: 'ok', 'not_friends', 'blocked', 'rate', 'empty', 'banned', 'bad'.
create or replace function public.send_message_v2(p_code text, p_kind text, p_body text, p_attachment jsonb default null)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  k text := coalesce(p_kind, 'text');
  b text := left(btrim(coalesce(p_body, '')), 500);
  path text := coalesce(p_attachment->>'path', '');
begin
  if uid is null then return 'auth'; end if;
  if k not in ('text', 'sticker', 'image', 'file') then return 'bad'; end if;
  if exists (select 1 from public.profiles p where p.id = uid and p.chat_banned) then return 'banned'; end if;
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return 'not_friends';
  end if;
  if exists (select 1 from public.blocks bl where (bl.user_id = target and bl.blocked_id = uid) or (bl.user_id = uid and bl.blocked_id = target)) then
    return 'blocked';
  end if;
  if (select count(*) from public.messages m where m.from_id = uid and m.created_at > now() - interval '1 minute') >= 20 then
    return 'rate';
  end if;
  if k = 'text' and b = '' then return 'empty'; end if;
  if k = 'sticker' and b !~ '^[a-z_]{1,24}$' then return 'bad'; end if;
  if k in ('image', 'file') then
    if path not like uid::text || '/' || target::text || '/%' then return 'bad'; end if;
    if b = '' then b := case when k = 'image' then '[фото]' else '[файл] ' || left(coalesce(p_attachment->>'name', ''), 80) end; end if;
  end if;
  insert into public.messages (from_id, to_id, body, kind, attachment)
    values (uid, target, case when k = 'sticker' then b else b end, k,
            case when k in ('image', 'file') then jsonb_build_object(
              'path', path, 'name', left(coalesce(p_attachment->>'name', ''), 120), 'size', coalesce((p_attachment->>'size')::bigint, 0),
              'mime', left(coalesce(p_attachment->>'mime', ''), 80), 'w', coalesce((p_attachment->>'w')::int, 0), 'h', coalesce((p_attachment->>'h')::int, 0))
            else null end);
  delete from public.chat_typing where user_id = uid and to_id = target;
  return 'ok';
end
$fn$;

-- Переписка после p_after (входящие помечаются прочитанными) со всеми полями.
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
  update public.messages m set read_at = now() where m.from_id = target and m.to_id = uid and m.read_at is null;
  return query
    select * from (
      select m.id, (m.from_id = uid) as mine, m.body, m.created_at, m.kind, m.attachment, (m.read_at is not null) as seen
      from public.messages m
      where ((m.from_id = uid and m.to_id = target) or (m.from_id = target and m.to_id = uid)) and m.id > p_after
      order by m.id desc limit 100
    ) t order by t.id;
end
$fn$;

-- Состояние собеседника: печатает ли, когда был в сети, до какого моего сообщения дочитал.
create or replace function public.chat_peer(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
  seen timestamptz;
begin
  select p.id, p.last_seen into target, seen from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return null;
  end if;
  update public.profiles set last_seen = now() where id = uid;
  return jsonb_build_object(
    'typing', exists (select 1 from public.chat_typing t where t.user_id = target and t.to_id = uid and t.at > now() - interval '6 seconds'),
    'last_seen', seen,
    'read_upto', coalesce((select max(m.id) from public.messages m where m.from_id = uid and m.to_id = target and m.read_at is not null), 0)
  );
end
$fn$;

create or replace function public.set_typing(p_code text)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  target uuid;
begin
  select p.id into target from public.profiles p where p.friend_code = upper(btrim(p_code));
  if uid is null or target is null or not exists (select 1 from public.friendships f where f.user_id = uid and f.friend_id = target) then
    return;
  end if;
  insert into public.chat_typing (user_id, to_id, at) values (uid, target, now())
    on conflict (user_id, to_id) do update set at = now();
end
$fn$;

revoke all on function public.chat_upload_path(text, text), public.send_message_v2(text, text, text, jsonb),
  public.get_messages_v2(text, bigint), public.chat_peer(text), public.set_typing(text) from public, anon;
grant execute on function public.chat_upload_path(text, text), public.send_message_v2(text, text, text, jsonb),
  public.get_messages_v2(text, bigint), public.chat_peer(text), public.set_typing(text) to authenticated;

-- Корзина для вложений: приватная, до 10 МБ. Путь файла: <отправитель>/<получатель>/<случайное имя>.
-- Идёт последней и в защитном блоке: если у SQL Editor нет прав на storage, остальное всё равно применится.
do $do$
begin
  insert into storage.buckets (id, name, public, file_size_limit)
    values ('chat', 'chat', false, 10485760)
    on conflict (id) do update set public = false, file_size_limit = 10485760;
  drop policy if exists "chat_files_read" on storage.objects;
  create policy "chat_files_read" on storage.objects for select to authenticated
    using (bucket_id = 'chat' and (auth.uid()::text = (storage.foldername(name))[1] or auth.uid()::text = (storage.foldername(name))[2]));
  drop policy if exists "chat_files_upload" on storage.objects;
  create policy "chat_files_upload" on storage.objects for insert to authenticated
    with check (bucket_id = 'chat' and auth.uid()::text = (storage.foldername(name))[1]);
  raise notice 'Хранилище chat готово';
exception when others then
  raise warning 'Хранилище для файлов не настроилось: %. Текст, стикеры и реакции работают, картинки и файлы — нет. Пришли этот текст.', sqlerrm;
end
$do$;

notify pgrst, 'reload schema';
