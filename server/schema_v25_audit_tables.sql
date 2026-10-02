-- Trash Squad v25: ежедневная проверка, что таблицы не открылись для клиента заново (после v24).
-- Результат пишется в журнал ошибок (client_errors, build = 'audit'): видно в DeV-панели в блоке «Ошибки игроков».
-- Запустить один раз (повтор безопасен). Планировщик pg_cron включается тут же; если у проекта его нет, функция всё
-- равно создастся и её можно вызвать вручную: select public.audit_table_access();

create or replace function public.audit_table_access()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  bad text := '';
  t record;
begin
  -- Разрешено клиенту напрямую: profiles и friendships (только SELECT), line_votes (SELECT, INSERT, UPDATE).
  for t in
    select g.table_name, string_agg(g.privilege_type, ',' order by g.privilege_type) as privs
    from information_schema.role_table_grants g
    where g.table_schema = 'public' and g.grantee in ('anon', 'authenticated')
      and not (g.table_name in ('profiles', 'friendships') and g.privilege_type = 'SELECT')
      and not (g.table_name = 'line_votes' and g.privilege_type in ('SELECT', 'INSERT', 'UPDATE'))
    group by g.table_name loop
    bad := bad || t.table_name || ' [' || t.privs || '] ';
  end loop;
  for t in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity loop
    bad := bad || t.relname || ' [без RLS] ';
  end loop;
  if bad <> '' then
    insert into public.client_errors (build, device, body)
      values ('audit', 'server', 'АУДИТ ТАБЛИЦ: открыто клиенту: ' || bad || '. Запусти schema_v24_lock_tables.sql ещё раз.');
    return 'open: ' || bad;
  end if;
  return 'ok';
end
$fn$;

revoke all on function public.audit_table_access() from public, anon, authenticated;

-- Раз в сутки в 03:17 UTC. Защитный блок: нет pg_cron, всё остальное всё равно применится.
do $do$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('audit_tables', '17 3 * * *', 'select public.audit_table_access()');
  raise notice 'Ежедневная проверка таблиц включена (03:17 UTC)';
exception when others then
  raise warning 'pg_cron недоступен: %. Включи в Supabase: Database -> Extensions -> pg_cron, потом запусти этот файл ещё раз.', sqlerrm;
end
$do$;

select public.audit_table_access() as audit_now;
