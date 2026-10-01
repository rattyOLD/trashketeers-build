-- Trash Squad v9: Insider-ссылка получает лимит 50 входов (новая ссылка из панели DeV — тоже на 50). Запустить один раз.
update public.badge_secrets set max_uses = 50, active = (uses < 50) where level = 1 and max_uses is null;

create or replace function public.dev_rotate_link(p_level int)
returns text language plpgsql security definer set search_path = public as $fn$
declare secret text;
begin
  if not public.is_dev() or p_level not in (0, 1) then return null; end if;
  secret := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  update public.badge_secrets set active = false where level = p_level;
  insert into public.badge_secrets (level, hash, max_uses)
    values (p_level, encode(sha256(convert_to(secret, 'UTF8')), 'hex'), case when p_level = 0 then 3 else 50 end);
  insert into public.badge_log (friend_code, nickname, level, how) values (null, null, p_level, 'новая ссылка');
  return secret;
end
$fn$;
