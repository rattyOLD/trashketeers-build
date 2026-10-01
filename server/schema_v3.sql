-- Часть B: таблица рекордов и ограничение волны (защита от очевидной накрутки).
create or replace function public.top_waves(p_limit int default 20)
returns table (nickname text, best_wave int, insider int)
language sql security definer set search_path = public as $fn$
  select p.nickname, p.best_wave, p.insider from public.profiles p
  where p.best_wave > 0 order by p.best_wave desc, p.updated_at asc
  limit least(greatest(p_limit, 1), 50);
$fn$;

revoke all on function public.top_waves(int) from public, anon;
grant execute on function public.top_waves(int) to authenticated;

create or replace function public.sync_profile(p_nickname text, p_best_wave int, p_insider int)
returns table (friend_code text) language plpgsql security definer set search_path = public as $fn$
declare
  uid uuid := auth.uid();
  code text;
  nick text := left(btrim(coalesce(p_nickname, '')), 24);
  wave int := least(greatest(coalesce(p_best_wave, 0), 0), 500);
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if nick = '' then nick := 'Енот'; end if;
  select p.friend_code into code from public.profiles p where p.id = uid;
  if code is null then
    loop
      code := upper(substr(translate(md5(random()::text || clock_timestamp()::text), '01', 'XY'), 1, 6));
      exit when not exists (select 1 from public.profiles p where p.friend_code = code);
    end loop;
    insert into public.profiles (id, nickname, friend_code, best_wave, insider) values (uid, nick, code, wave, p_insider);
  else
    update public.profiles set nickname = nick, best_wave = greatest(best_wave, wave), insider = p_insider, updated_at = now() where id = uid;
  end if;
  return query select code;
end
$fn$;

revoke all on function public.sync_profile(text, int, int) from public, anon;
grant execute on function public.sync_profile(text, int, int) to authenticated;
