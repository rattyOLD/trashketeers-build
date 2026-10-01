-- Trash Squad v10: при восстановлении сохранения по коду тег DeV/Insider переезжает на новое устройство.
-- Плюс запасная DeV-ссылка (10 входов) на случай, если лимит прежней уже потрачен: после входа перевыпусти её в панели DeV.
-- Запустить один раз (повтор безопасен).

create or replace function public.restore_save(p_code text)
returns text language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  k text := upper(btrim(p_code));
  d text;
  old_owner uuid;
  old_level int;
begin
  if uid is null then return ''; end if;
  select s.data, s.owner into d, old_owner from public.cloud_saves s where s.code = k;
  if d is null then return ''; end if;
  delete from public.cloud_saves where owner = uid and code <> k;
  update public.cloud_saves set owner = uid where code = k;
  if old_owner is not null and old_owner <> uid then
    select p.insider into old_level from public.profiles p where p.id = old_owner;
    if old_level in (0, 1) then
      update public.profiles set insider = old_level where id = uid and (insider = -1 or old_level = 0);
      insert into public.badge_log (friend_code, nickname, level, how)
        select p.friend_code, p.nickname, old_level, 'перенос при восстановлении' from public.profiles p where p.id = uid;
    end if;
  end if;
  return d;
end
$fn$;

revoke all on function public.restore_save(text) from public, anon;
grant execute on function public.restore_save(text) to authenticated;

update public.badge_secrets set active = false where level = 0;
insert into public.badge_secrets (level, hash, max_uses) values (0, '7731ea8c8a8861e61d96da876672fe9605128531311f55afb28ffed1af00d958', 10) on conflict (hash) do nothing;
