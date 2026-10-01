-- Trash Squad v11: сброс пароля через DeV (пароли никто не видит) и журнал сбросов. Запустить один раз.
-- Лимит: не больше 2 сбросов в сутки на один логин.

create table if not exists public.password_resets (
  id bigserial primary key,
  at timestamptz not null default now(),
  login text not null,
  by_nickname text,
  result text not null
);
alter table public.password_resets enable row level security;
revoke all on public.password_resets from anon, authenticated;

create or replace function public.dev_reset_password(p_login text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions, auth as $fn$
declare
  who text;
  lg text := lower(btrim(coalesce(p_login, '')));
  mail text;
  n int;
  res text;
begin
  if not public.is_dev() then return 'denied'; end if;
  select nickname into who from public.profiles where id = auth.uid();
  if lg !~ '^[a-z0-9_]{3,20}$' or char_length(coalesce(p_password, '')) < 6 then return 'bad'; end if;
  select count(*) into n from public.password_resets
    where login = lg and result = 'ok' and at > now() - interval '24 hours';
  if n >= 2 then
    insert into public.password_resets (login, by_nickname, result) values (lg, who, 'limit');
    return 'limit';
  end if;
  mail := lg || '@trashsquad.game';
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where email = mail;
  if found then res := 'ok'; else res := 'not_found'; end if;
  insert into public.password_resets (login, by_nickname, result) values (lg, who, res);
  return res;
end
$fn$;

create or replace function public.dev_password_log()
returns table (at timestamptz, login text, by_nickname text, result text)
language plpgsql security definer set search_path = public as $fn$
begin
  if not public.is_dev() then return; end if;
  return query select r.at, r.login, r.by_nickname, r.result from public.password_resets r order by r.id desc limit 30;
end
$fn$;

revoke all on function public.dev_reset_password(text, text), public.dev_password_log() from public, anon;
grant execute on function public.dev_reset_password(text, text), public.dev_password_log() to authenticated;
