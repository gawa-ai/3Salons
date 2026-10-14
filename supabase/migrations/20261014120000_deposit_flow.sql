-- Round 4 (client, 2026-10-14): deposit flow, bank transfer, no online payment.
--   1. Customer books online (pending).
--   2. The artist accepts ("confirm"). If the service carries a deposit, the booking stays pending,
--      the slot is held for deposit_hours (default 24) and the customer is sent the deposit request
--      (amount, payment details, reference).
--   3. The studio checks its own bank, then taps "Deposit received": booking is confirmed and the customer
--      is told their deposit is received.
--   4. No deposit in time: the booking expires, the slot is released, the customer is told.
-- Payment details (bank account etc.) are NEVER in code or git: the owner types them in Studio > Settings
-- and they are stored in app.salons.deposit_instructions. Re-runnable.

alter table app.salons
  add column if not exists deposit_instructions text,
  add column if not exists deposit_hours int not null default 24
    check (deposit_hours between 1 and 168);

alter table app.services
  add column if not exists deposit_pence int not null default 0
    check (deposit_pence between 0 and 100000);

alter table app.bookings
  add column if not exists deposit_pence int not null default 0 check (deposit_pence >= 0),
  add column if not exists deposit_status text not null default 'none',
  add column if not exists deposit_due_at timestamptz,
  add column if not exists deposit_received_at timestamptz;
alter table app.bookings drop constraint if exists bookings_deposit_status_check;
alter table app.bookings add constraint bookings_deposit_status_check
  check (deposit_status in ('none','requested','received','waived'));

-- Amounts the client stated (2026-10-14): hair 10, hijab 10, hair + makeup 20.
-- Makeup only, saree and bridal are NOT set (not confirmed yet): the owner sets them in Settings.
update app.services set deposit_pence = 1000
 where deposit_pence = 0 and category in ('hair','hijab') and price_kind <> 'enquire';
update app.services set deposit_pence = 2000
 where deposit_pence = 0 and category = 'hair_makeup' and price_kind <> 'enquire';

-- A booking snapshots the service deposit when it is created (later price edits never change it).
create or replace function app.booking_deposit_snapshot()
returns trigger language plpgsql set search_path = '' as $$
begin
  select deposit_pence into new.deposit_pence from app.services where id = new.service_id;
  new.deposit_pence := coalesce(new.deposit_pence, 0);
  return new;
end $$;
drop trigger if exists bookings_deposit_snapshot on app.bookings;
create trigger bookings_deposit_snapshot before insert on app.bookings
  for each row execute function app.booking_deposit_snapshot();

-- ---------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------
create or replace function app.message_body(p_purpose text, s app.salons, p app.professionals,
                                            k app.bookings, c app.clients)
returns text language sql stable set search_path = '' as $$
  select replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
    case p_purpose
      when 'request_received' then 'Hi {first}, thank you for your booking request with {pro} at {salon}: {service} on {when}. It is provisional until {pro_short} confirms. Ref {ref}.'
      when 'new_request'      then 'New booking request: {service} on {when} for {client}. Ref {ref}. Please confirm or decline in your dashboard.'
      when 'confirmed'        then 'Hi {first}, {pro_short} has confirmed your {service} on {when} at {salon}. Ref {ref}.{contact}'
      when 'deposit_request'  then 'Hi {first}, {pro_short} can take your {service} on {when}. Please note all bookings take place at {salon}. To secure your booking please pay a {deposit} non refundable deposit within {hours} hours, which will be deducted on the day.{payment} Please leave your name or ref {ref} as the payment reference.'
      when 'deposit_received' then 'Hi {first}, thank you, we have received your {deposit} deposit. Your {service} with {pro_short} on {when} at {salon} is confirmed. Ref {ref}.{contact}'
      when 'deposit_expired'  then 'Hi {first}, we did not receive the deposit for your {service} on {when}, so the time has been released. You are welcome to book again on our website. Ref {ref}.'
      when 'declined'         then 'Hi {first}, sorry, {pro_short} cannot take your {service} request for {when}. Please choose another time on our website. Ref {ref}.'
      when 'cancelled'        then 'Hi {first}, your {service} with {pro_short} on {when} has been cancelled. Ref {ref}.'
      when 'cancelled_pro'    then 'Booking cancelled by the customer: {service} on {when} for {client}. Ref {ref}.'
      when 'rescheduled'      then 'Hi {first}, your {service} with {pro_short} has moved to {when}. Ref {ref}.'
      else '' end,
    '{first}', coalesce(nullif(split_part(btrim(coalesce(c.name, '')), ' ', 1), ''), 'there')),
    '{client}', coalesce(c.name, 'a client')),
    '{pro_short}', p.short_name),
    '{pro}', p.display_name),
    '{salon}', s.name || coalesce(', ' || nullif(btrim(s.address), ''), '')),
    '{service}', k.service_name),
    '{when}', app.fmt_when(k.starts_at, s.timezone)),
    '{contact}', coalesce(' Questions? Call ' || nullif(btrim(s.phone), '') || '.', '')),
    '{deposit}', app.fmt_price(k.deposit_pence, 'fixed')),
    '{hours}', s.deposit_hours::text),
    '{payment}', coalesce(E'\n' || nullif(btrim(s.deposit_instructions), '') || E'\n', ' '))
$$;

-- ---------------------------------------------------------------------
-- Booking JSON now carries the deposit state
-- ---------------------------------------------------------------------
create or replace function app.booking_json(k app.bookings, p_include_private boolean default true)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', k.id, 'ref', k.ref, 'status', k.status, 'source', k.source,
    'professional_id', k.professional_id,
    'professional', p.display_name, 'professional_short', p.short_name, 'professional_color', p.color,
    'service_id', k.service_id, 'service', k.service_name,
    'starts_at', k.starts_at, 'ends_at', k.ends_at, 'block_end', k.block_end,
    'local_date', to_char(k.starts_at at time zone s.timezone, 'YYYY-MM-DD'),
    'local_time', to_char(k.starts_at at time zone s.timezone, 'HH24:MI'),
    'local_end',  to_char(k.ends_at at time zone s.timezone, 'HH24:MI'),
    'when', app.fmt_when(k.starts_at, s.timezone),
    'duration_min', k.duration_min, 'buffer_min', k.buffer_min,
    'price_pence', k.price_pence, 'price_kind', k.price_kind, 'price_label', app.fmt_price(k.price_pence, k.price_kind),
    'deposit_pence', k.deposit_pence, 'deposit_status', k.deposit_status, 'deposit_due_at', k.deposit_due_at,
    'deposit_label', case when k.deposit_pence > 0 then app.fmt_price(k.deposit_pence, 'fixed') end,
    'version', k.version, 'created_at', k.created_at, 'confirmed_at', k.confirmed_at,
    'cancelled_at', k.cancelled_at, 'status_reason', k.status_reason
  ) || case when p_include_private then jsonb_build_object(
    'client_id', c.id, 'client_name', c.name, 'client_phone', c.phone, 'client_email', c.email,
    'customer_note', k.customer_note, 'internal_note', k.internal_note) else '{}'::jsonb end
  from app.salons s, app.professionals p, app.clients c
  where s.id = k.salon_id and p.id = k.professional_id and c.id = k.client_id
$$;

-- ---------------------------------------------------------------------
-- Expiry: unconfirmed requests past their start, and deposits not paid in time
-- ---------------------------------------------------------------------
create or replace function app.expire_stale(p_salon uuid)
returns void language plpgsql set search_path = '' as $$
declare r record; k app.bookings;
begin
  for k in update app.bookings set status = 'expired', version = version + 1, updated_at = now(),
                                   status_reason = 'Deposit not received in time'
           where salon_id = p_salon and status = 'pending' and deposit_status = 'requested'
             and deposit_due_at < now()
           returning * loop
    perform app.notify_booking(k, 'deposit_expired', 'customer');
    perform app.audit(p_salon, k.professional_id, null, 'system', 'booking.deposit_expired', 'booking', k.id::text,
                      jsonb_build_object('ref', k.ref));
  end loop;
  for r in update app.bookings set status = 'expired', version = version + 1, updated_at = now(),
                                   status_reason = 'Not confirmed before the appointment time'
           where salon_id = p_salon and status = 'pending' and starts_at < now()
           returning id, professional_id loop
    perform app.audit(p_salon, r.professional_id, null, 'system', 'booking.expired', 'booking', r.id::text);
  end loop;
end $$;

-- Runs expiry for every salon; used by the optional schedule below.
create or replace function app.expire_all()
returns void language plpgsql set search_path = '' as $$
declare s record;
begin
  for s in select id from app.salons loop perform app.expire_stale(s.id); end loop;
end $$;

-- If pg_cron is enabled (Supabase: Database > Extensions), unpaid deposits are released every 10 minutes
-- even when nobody opens Studio. Without pg_cron the release happens as soon as Studio is opened.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('app-expire-stale', '*/10 * * * *', 'select app.expire_all()');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Status actions: confirm now asks for the deposit first when the service carries one
-- ---------------------------------------------------------------------
create or replace function public.salon_dash_booking_action(p_booking uuid, p_action text,
                                                            p_reason text default null, p_version int default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k app.bookings; m app.memberships; s app.salons; old text; new_status text;
        act text := lower(coalesce(p_action, '')); v_dep text;
begin
  k := app.booking_for_caller(p_booking, true);
  m := app.my_membership(k.salon_id);
  if p_version is not null and p_version <> k.version then
    perform app.fail('stale', 'This booking was changed by someone else. Please refresh.');
  end if;
  old := k.status;
  select * into s from app.salons where id = k.salon_id;

  -- Accepting a booking whose service has a deposit: hold the slot and ask for the deposit.
  if act = 'confirm' and old = 'pending' and k.deposit_pence > 0 and k.deposit_status = 'none' then
    if k.starts_at <= now() then
      perform app.fail('too_late', 'This appointment time has passed and can no longer be confirmed.');
    end if;
    if nullif(btrim(coalesce(s.deposit_instructions, '')), '') is null then
      perform app.fail('deposit_details_missing', 'Add your payment details in Settings first, so the client knows where to pay the deposit.');
    end if;
    update app.bookings
       set deposit_status = 'requested',
           deposit_due_at = least(now() + make_interval(hours => s.deposit_hours), k.starts_at),
           version = version + 1, updated_at = now()
     where id = k.id returning * into k;
    perform app.notify_booking(k, 'deposit_request', 'customer');
    perform app.audit(k.salon_id, k.professional_id, auth.uid(), app.actor_label(m), 'booking.deposit_requested', 'booking',
                      k.id::text, jsonb_build_object('ref', k.ref, 'deposit_pence', k.deposit_pence));
    return jsonb_build_object('ok', true, 'deposit_requested', true, 'booking', app.booking_json(k));
  end if;

  new_status := case
    when act = 'confirm'  and old = 'pending' then 'confirmed'
    when act = 'deposit_received' and old = 'pending' and k.deposit_pence > 0
         and k.deposit_status in ('none','requested') then 'confirmed'
    when act = 'decline'  and old = 'pending' then 'declined'
    when act = 'cancel'   and old in ('pending','confirmed') then 'cancelled'
    when act = 'complete' and old in ('confirmed','no_show') then 'completed'
    when act = 'no_show'  and old in ('confirmed','completed') then 'no_show'
    else null end;
  if new_status is null then
    perform app.fail('invalid_transition', 'A ' || old || ' booking cannot be changed with "' || act || '".');
  end if;
  if new_status = 'confirmed' and k.starts_at <= now() then
    perform app.fail('too_late', 'This appointment time has passed and can no longer be confirmed.');
  end if;
  if new_status in ('completed','no_show') and k.starts_at > now() then
    perform app.fail('not_started', 'You can mark the outcome once the appointment has started.');
  end if;

  update app.bookings
     set status = new_status, version = version + 1, updated_at = now(),
         status_reason = coalesce(app.clean_text(p_reason, 300), case when new_status in ('declined','cancelled') then null else status_reason end),
         confirmed_at = case when new_status = 'confirmed' then now() else confirmed_at end,
         cancelled_at = case when new_status = 'cancelled' then now() else cancelled_at end,
         completed_at = case when new_status = 'completed' then now() else completed_at end,
         deposit_status = case when act = 'deposit_received' then 'received'
                               when act = 'confirm' and deposit_status = 'requested' then 'waived'
                               else deposit_status end,
         deposit_received_at = case when act = 'deposit_received' then now() else deposit_received_at end
   where id = k.id returning * into k;

  if act = 'deposit_received' then
    perform app.notify_booking(k, 'deposit_received', 'customer');
  elsif new_status in ('confirmed','declined','cancelled') then
    perform app.notify_booking(k, new_status, 'customer');
  end if;
  v_dep := case when act = 'deposit_received' then 'booking.deposit_received' else 'booking.' || new_status end;
  perform app.audit(k.salon_id, k.professional_id, auth.uid(), app.actor_label(m), v_dep, 'booking',
                    k.id::text, jsonb_build_object('ref', k.ref, 'from', old, 'to', new_status, 'reason', app.clean_text(p_reason, 300)));
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k));
end $$;

-- ---------------------------------------------------------------------
-- Customer manage page: show the payment details while a deposit is requested
-- ---------------------------------------------------------------------
create or replace function public.salon_public_manage(p_token text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k app.bookings; s app.salons; c app.clients; v_code text; v_detail text;
begin
  k := app.booking_by_token(p_token, false);
  select * into s from app.salons where id = k.salon_id;
  select * into c from app.clients where id = k.client_id;
  return jsonb_build_object('ok', true,
    'booking', app.booking_json(k, false) || jsonb_build_object(
       'first_name', split_part(btrim(c.name), ' ', 1),
       'can_cancel', k.status in ('pending','confirmed') and k.starts_at > now(),
       'deposit_instructions', case when k.status = 'pending' and k.deposit_status = 'requested'
                                    then nullif(btrim(s.deposit_instructions), '') end),
    'salon', jsonb_build_object('name', s.name, 'phone', s.phone, 'whatsapp', s.whatsapp, 'email', s.email,
                                'address', s.address, 'booking_policy', s.booking_policy, 'timezone', s.timezone));
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
-- Owner settings for deposits (payment details, hold time, amount per service)
-- ---------------------------------------------------------------------
create or replace function public.salon_owner_deposits(p_salon uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; s app.salons;
begin
  m := app.require_owner(p_salon);
  select * into s from app.salons where id = p_salon;
  return jsonb_build_object('ok', true,
    'instructions', s.deposit_instructions, 'hours', s.deposit_hours,
    'services', (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', v.id, 'name', v.name, 'professional', p.short_name, 'category', v.category,
                   'price_label', app.fmt_price(v.price_pence, v.price_kind), 'deposit_pence', v.deposit_pence,
                   'active', v.active, 'bookable_online', v.bookable_online)
                 order by p.sort_order, p.short_name, v.sort_order, v.name), '[]'::jsonb)
                 from app.services v join app.professionals p on p.id = v.professional_id
                 where v.salon_id = p_salon));
end $$;

create or replace function public.salon_owner_deposits_save(p_salon uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); x jsonb; v_pence int;
begin
  m := app.require_owner(p_salon);
  if a ? 'hours' and coalesce((a->>'hours')::int, 0) not between 1 and 168 then
    perform app.fail('invalid_hours', 'The deposit hold time must be between 1 and 168 hours.');
  end if;
  if a ? 'instructions' then
    update app.salons set deposit_instructions = app.clean_text(a->>'instructions', 1000), updated_at = now()
     where id = p_salon;
  end if;
  if a ? 'hours' then
    update app.salons set deposit_hours = (a->>'hours')::int, updated_at = now() where id = p_salon;
  end if;
  if jsonb_typeof(a->'services') = 'array' then
    for x in select * from jsonb_array_elements(a->'services') loop
      v_pence := (x->>'deposit_pence')::int;
      if v_pence is null or v_pence not between 0 and 100000 then
        perform app.fail('invalid_deposit', 'A deposit must be between £0 and £1,000.');
      end if;
      update app.services set deposit_pence = v_pence, updated_at = now()
       where id = (x->>'id')::uuid and salon_id = p_salon;
    end loop;
  end if;
  -- the payment details are not copied into the audit log
  perform app.audit(p_salon, null, m.user_id, 'owner', 'deposits.updated', 'salon', p_salon::text,
                    jsonb_build_object('hours', a->'hours', 'services_changed', coalesce(jsonb_array_length(a->'services'), 0),
                                       'instructions_changed', a ? 'instructions'));
  return jsonb_build_object('ok', true);
end $$;

do $$
begin
  revoke all on function public.salon_owner_deposits(uuid) from public;
  revoke all on function public.salon_owner_deposits_save(uuid, jsonb) from public;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.salon_owner_deposits(uuid) from anon;
    revoke all on function public.salon_owner_deposits_save(uuid, jsonb) from anon;
    grant execute on function public.salon_owner_deposits(uuid) to authenticated;
    grant execute on function public.salon_owner_deposits_save(uuid, jsonb) to authenticated;
  end if;
end $$;
