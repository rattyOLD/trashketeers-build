-- Trash Squad v24: закрыть прямой доступ к таблицам. Всё, что меняет данные, идёт только через RPC (security definer).
-- Зачем: в Supabase новые таблицы в public по умолчанию открыты для anon/authenticated. Если где-то забыли REVOKE или
-- добавят политику UPDATE, игрок сможет менять профиль, тег, монеты прямо через REST. Этот файл закрывает это разом
-- и для будущих таблиц тоже. Запустить один раз (повтор безопасен). Клиент напрямую ходит только в line_votes (см. ниже).

do $do$
declare
  t record;
begin
  -- 1. RLS на каждой таблице public и полный REVOKE для anon и authenticated.
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' loop
    execute format('alter table public.%I enable row level security', t.relname);
    execute format('revoke all on public.%I from anon, authenticated', t.relname);
  end loop;

  -- 2. Новые таблицы в public больше не получают права автоматически.
  alter default privileges in schema public revoke all on tables from anon, authenticated;
  alter default privileges in schema public revoke all on sequences from anon, authenticated;
end
$do$;

-- 3. Что клиенту реально нужно напрямую (ничего лишнего).
grant select on public.profiles, public.friendships to authenticated;          -- политики profiles_select и friendships_select уже есть
grant select, insert, update on public.line_votes to authenticated;            -- голоса за реплики, только свои строки (политики votes_*)
-- Все записи в profiles (ник, тег, рекорд, друзья, сообщения, жалобы) идут через RPC. Прямых INSERT/UPDATE/DELETE нет.

-- 4. Отчёт: какие таблицы всё ещё доступны клиенту напрямую (должны быть только три выше).
do $do$
declare
  t record;
  line text;
begin
  for t in select table_name, string_agg(privilege_type, ',' order by privilege_type) as privs
           from information_schema.role_table_grants
           where table_schema = 'public' and grantee in ('anon', 'authenticated')
           group by table_name order by table_name loop
    line := coalesce(line || E'\n', '') || '  ' || t.table_name || ': ' || t.privs;
  end loop;
  raise notice E'Прямой доступ клиента к таблицам после v24:\n%', coalesce(line, '(нет)');
end
$do$;

notify pgrst, 'reload schema';
