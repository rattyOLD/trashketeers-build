-- Часть C: сохранение текущего профиля (для входа по почте).
create or replace function public.my_save()
returns text language sql security definer set search_path = public as $fn$
  select s.data from public.cloud_saves s where s.owner = auth.uid();
$fn$;

revoke all on function public.my_save() from public, anon;
grant execute on function public.my_save() to authenticated;
