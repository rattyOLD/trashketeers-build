-- Trash Squad v20: гость со скрытым входом (guest_…) заводит свой логин без смены почты через Supabase Auth.
-- Смена почты у пользователя, у которого она уже есть, в Supabase идёт через письмо-подтверждение
-- (и при включённом SMTP падает на несуществующем адресе @trashsquad.game). Поэтому логин меняем здесь,
-- а пароль игра ставит обычным запросом. Запустить один раз (повтор безопасен).

create or replace function public.claim_login(p_login text)
returns text language plpgsql security definer set search_path = public, auth as $fn$
declare
  uid uuid := auth.uid();
  login text := lower(btrim(coalesce(p_login, '')));
  mail text;
  current_mail text;
begin
  if uid is null then return 'auth'; end if;
  if login !~ '^[a-z0-9_]{3,20}$' or login like 'guest\_%' then return 'invalid'; end if;
  mail := login || '@trashsquad.game';
  select u.email into current_mail from auth.users u where u.id = uid;
  if current_mail = mail then return 'ok'; end if;
  if coalesce(current_mail, '') <> '' and current_mail not like 'guest\_%' then return 'has_login'; end if;
  if exists (select 1 from auth.users u where lower(u.email) = mail and u.id <> uid) then return 'taken'; end if;
  update auth.users set email = mail, email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now(),
    is_anonymous = false where id = uid;
  update auth.identities set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(mail)), updated_at = now()
    where user_id = uid and provider = 'email';
  return 'ok';
end
$fn$;

revoke all on function public.claim_login(text) from public, anon;
grant execute on function public.claim_login(text) to authenticated;

notify pgrst, 'reload schema';
