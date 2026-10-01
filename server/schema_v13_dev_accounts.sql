-- Trash Squad v13: поиск аккаунтов с логином для панели DeV (пароли не показываются, их никто не видит). Запустить один раз.
create or replace function public.dev_accounts(p_query text default '')
returns table (login text, nickname text, friend_code text, last_seen timestamptz)
language plpgsql security definer set search_path = public, auth as $fn$
declare q text := lower(btrim(coalesce(p_query, '')));
begin
  if not public.is_dev() then return; end if;
  return query
    select split_part(u.email, '@', 1), p.nickname, p.friend_code, p.last_seen
    from auth.users u join public.profiles p on p.id = u.id
    where u.email like '%@trashsquad.game'
      and (q = '' or split_part(u.email, '@', 1) like '%' || q || '%' or lower(p.nickname) like '%' || q || '%' or lower(p.friend_code) = q)
    order by p.last_seen desc limit 30;
end
$fn$;
revoke all on function public.dev_accounts(text) from public, anon;
grant execute on function public.dev_accounts(text) to authenticated;
