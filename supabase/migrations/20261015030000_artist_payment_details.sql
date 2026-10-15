-- Round 6 (client, 2026-10-15): each artist can be paid into their own bank account.
-- The deposit request and the customer's booking page use the artist's own payment details when the owner has
-- typed them in Studio > Settings, otherwise the studio's details. Stored in their own table (never in the
-- professionals row), so they cannot leak through the professional audit entries. Never in git.
-- Re-runnable.

create table if not exists app.professional_payment_details (
  professional_id uuid primary key references app.professionals(id) on delete cascade,
  instructions    text not null check (length(btrim(instructions)) > 0),
  updated_at      timestamptz not null default now()
);
alter table app.professional_payment_details enable row level security;
revoke all on table app.professional_payment_details from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table app.professional_payment_details from anon, authenticated';
  end if;
end $$;

create or replace function app.deposit_payment_text(s app.salons, p_pro uuid)
returns text language sql stable set search_path = '' as $$
  select coalesce(
    (select nullif(btrim(d.instructions), '') from app.professional_payment_details d where d.professional_id = p_pro),
    nullif(btrim(s.deposit_instructions), ''))
$$;

create or replace function app.message_body(p_purpose text, s app.salons, p app.professionals,
                                            k app.bookings, c app.clients)
returns text language sql stable set search_path = '' as $$
  select replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
    case p_purpose
      when 'request_received' then 'Hi {first}, thank you for your booking request with {pro} at {salon}: {service} on {when}. It is provisional until {pro_short} confirms. Ref {ref}.'
      when 'new_request'      then 'New booking request: {service} on {when} for {client}. Ref {ref}. Please confirm or decline in your dashboard.'
      when 'confirmed'        then 'Hi {first}, {pro_short} has confirmed your {service} on {when} at {salon}. Ref {ref}.{contact}'
      when 'deposit_request'  then E'Hi {first},\n\n{pro_short} is available for {service} on {when}.\n\nPlease note all bookings take place at the studio unless discussed otherwise\n(Please see below for address)\n\nTo secure your booking please pay a {deposit} non refundable deposit within {hours} hours, which will be deducted on the day.\n\n{payment}Please leave your ref {ref} as the payment reference.\n\n{signature}'
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
    '{contact}', coalesce(' Questions? Call ' || nullif(btrim(s.private_phone), '') || '.', '')),
    '{deposit}', app.fmt_price(k.deposit_pence, 'fixed')),
    '{hours}', s.deposit_hours::text),
    '{payment}', coalesce(app.deposit_payment_text(s, p.id) || E'\n', '')),
    '{signature}', s.name || E'\nMakeup Artist' ||
                   coalesce(E'\n' || nullif(replace(btrim(coalesce(s.address, '')), ', ', E'\n'), ''), '') ||
                   coalesce(E'\n' || nullif(btrim(s.private_phone), ''), ''))
$$;

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
    if app.deposit_payment_text(s, k.professional_id) is null then
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
                                    then app.deposit_payment_text(s, k.professional_id) end),
    'salon', jsonb_build_object('name', s.name, 'phone', s.phone, 'whatsapp', s.whatsapp, 'email', s.email,
                                'address', s.address, 'booking_policy', s.booking_policy, 'timezone', s.timezone,
                                'private_phone', case when k.status in ('confirmed','completed')
                                                      then nullif(btrim(s.private_phone), '') end));
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

create or replace function public.salon_owner_deposits(p_salon uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; s app.salons;
begin
  m := app.require_owner(p_salon);
  select * into s from app.salons where id = p_salon;
  return jsonb_build_object('ok', true,
    'instructions', s.deposit_instructions, 'hours', s.deposit_hours,
    'professionals', (select coalesce(jsonb_agg(jsonb_build_object(
                        'id', p.id, 'name', p.display_name, 'short_name', p.short_name,
                        'instructions', d.instructions) order by p.sort_order, p.short_name), '[]'::jsonb)
                      from app.professionals p
                      left join app.professional_payment_details d on d.professional_id = p.id
                      where p.salon_id = p_salon),
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
declare m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); x jsonb; v_pence int; v_text text; v_changed int := 0;
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
  -- each artist may be paid into their own account; blank = fall back to the studio details
  if jsonb_typeof(a->'professionals') = 'array' then
    for x in select * from jsonb_array_elements(a->'professionals') loop
      if not exists (select 1 from app.professionals where id = (x->>'id')::uuid and salon_id = p_salon) then
        perform app.fail('invalid_professional', 'That artist does not belong to this studio.');
      end if;
      v_text := app.clean_text(x->>'instructions', 1000);
      if v_text is null then
        delete from app.professional_payment_details where professional_id = (x->>'id')::uuid;
      else
        insert into app.professional_payment_details as d (professional_id, instructions)
        values ((x->>'id')::uuid, v_text)
        on conflict (professional_id) do update set instructions = excluded.instructions, updated_at = now();
      end if;
      v_changed := v_changed + 1;
    end loop;
  end if;
  -- the payment details are not copied into the audit log
  perform app.audit(p_salon, null, m.user_id, 'owner', 'deposits.updated', 'salon', p_salon::text,
                    jsonb_build_object('hours', a->'hours', 'services_changed', coalesce(jsonb_array_length(a->'services'), 0),
                                       'instructions_changed', a ? 'instructions', 'artist_accounts_changed', v_changed));
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
