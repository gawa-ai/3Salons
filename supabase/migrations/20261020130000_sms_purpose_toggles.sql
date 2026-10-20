-- Owner control over which customer text types are sent (cost control). Re-runnable.
-- Fixes the default: deposit_received (the "you are confirmed" text after a deposit) must be on.
alter table app.salons
  alter column sms_purposes set default
  '{"request_received":false,"confirmed":true,"deposit_request":true,"deposit_received":true,"deposit_expired":false,"rescheduled":true,"cancelled":true}'::jsonb;

-- Existing salons: add any missing keys but never overwrite a choice the owner already made.
update app.salons s
   set sms_purposes = ('{"request_received":false,"confirmed":true,"deposit_request":true,"deposit_received":true,"deposit_expired":false,"rescheduled":true,"cancelled":true}'::jsonb) || s.sms_purposes
 where true;

create or replace function public.salon_owner_sms_save(p_salon uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); k text; v jsonb; cur jsonb; nxt jsonb;
begin
  m := app.require_owner(p_salon);
  select sms_purposes into cur from app.salons where id = p_salon for update;
  nxt := cur;
  for k, v in select * from jsonb_each(a) loop
    if k not in ('request_received','confirmed','deposit_request','deposit_received','deposit_expired','rescheduled','cancelled') then
      perform app.fail('invalid_purpose', 'Unknown text type.');
    end if;
    if jsonb_typeof(v) <> 'boolean' then perform app.fail('invalid_value', 'Each text type must be on or off.'); end if;
    nxt := nxt || jsonb_build_object(k, v);
  end loop;
  update app.salons set sms_purposes = nxt, updated_at = now() where id = p_salon;
  perform app.audit(p_salon, null, m.user_id, 'owner', 'sms_settings.updated', 'salon', p_salon::text,
                    jsonb_build_object('before', cur, 'after', nxt));
  return jsonb_build_object('ok', true, 'sms_purposes', nxt);
end $$;

do $$
begin
  revoke all on function public.salon_owner_sms_save(uuid, jsonb) from public;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.salon_owner_sms_save(uuid, jsonb) from anon;
    grant execute on function public.salon_owner_sms_save(uuid, jsonb) to authenticated;
  end if;
end $$;
