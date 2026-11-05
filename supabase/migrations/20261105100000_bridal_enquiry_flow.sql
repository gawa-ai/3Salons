-- Bridal enquiry flow (Mohsin's spec). Re-runnable.
--  1. Customer enquiry  -> artist notified (already) + client gets an automatic "thank you" text.
--  2. Artist talks to the client, then presses "Agreed" and enters date, start time, length and deposit.
--     That holds the time in the calendar (a pending booking) and sends the client the deposit message.
--  3. Studio presses "Deposit received" on that booking -> client gets the confirmation text, the booking
--     becomes confirmed and the enquiry changes from Agreed to Booked.
--  4. If the booking is declined / cancelled / expires, the enquiry goes back to Contacted.

alter table app.enquiries add column if not exists booking_id uuid references app.bookings(id) on delete set null;
alter table app.enquiries add column if not exists agreed_at timestamptz;
create index if not exists enquiries_booking_idx on app.enquiries (booking_id) where booking_id is not null;

alter table app.enquiries drop constraint if exists enquiries_status_check;
alter table app.enquiries add constraint enquiries_status_check
  check (status in ('new','contacted','agreed','booked','closed'));

-- Text types: add the two that exist in code but not in the owner toggle list.
update app.salons set sms_purposes = '{"enquiry_received":true,"declined":true}'::jsonb || sms_purposes;
alter table app.salons alter column sms_purposes set default
  '{"request_received":false,"confirmed":true,"deposit_request":true,"deposit_received":true,"deposit_expired":false,"rescheduled":true,"cancelled":true,"declined":true,"enquiry_received":true}'::jsonb;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.salon_owner_sms_save(uuid,jsonb)'::regprocedure);
  if position('''cancelled'')' in d) > 0 and position('enquiry_received' in d) = 0 then
    d := replace(d, '''cancelled'')', '''cancelled'',''declined'',''enquiry_received'')');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Public enquiry: also text the client (purpose enquiry_received).
-- ---------------------------------------------------------------------
do $$
declare d text; o text := $o$  perform app.audit(s.id, p.id, auth.uid(), 'customer', 'enquiry.created'$o$;
begin
  d := pg_get_functiondef('public.salon_public_enquiry(text,jsonb)'::regprocedure);
  if position('enquiry_received' in d) = 0 then
    if position(o in d) = 0 then raise exception 'salon_public_enquiry anchor not found'; end if;
    d := replace(d, o, $n$  insert into app.notifications (salon_id, professional_id, enquiry_id, audience, channel, purpose, to_addr, body, status, dedupe_key)
  values (s.id, p.id, e.id, 'customer', 'sms', 'enquiry_received', e.phone,
          'Hi ' || coalesce(nullif(split_part(btrim(e.name), ' ', 1), ''), 'there') || ', thank you for your ' ||
          case when e.kind = 'bridal' then 'bridal ' else '' end || 'enquiry with ' || coalesce(p.display_name, s.name) ||
          '. Someone will get back to you soon.',
          case when s.sms_connected then 'queued' else 'not_connected' end, 'enquiry-ack:' || e.id::text);
$n$ || o);
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Enquiry list: show the linked booking / deposit
-- ---------------------------------------------------------------------
create or replace function public.salon_dash_enquiries(p_salon uuid, p_professional uuid default null, p_status text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; pro uuid;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  return jsonb_build_object('ok', true, 'items', (
    select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'kind', e.kind, 'name', e.name, 'phone', e.phone,
             'email', e.email, 'event_date', e.event_date, 'event_location', e.event_location,
             'services_wanted', e.services_wanted, 'message', e.message, 'status', e.status,
             'internal_note', e.internal_note, 'created_at', e.created_at,
             'professional_id', e.professional_id, 'professional', p.display_name, 'professional_color', p.color,
             'booking_id', e.booking_id, 'booking_ref', k.ref, 'booking_status', k.status,
             'booking_starts_at', k.starts_at, 'booking_duration_min', k.duration_min,
             'deposit_pence', k.deposit_pence, 'deposit_status', k.deposit_status)
             order by e.created_at desc), '[]'::jsonb)
    from app.enquiries e
    left join app.professionals p on p.id = e.professional_id
    left join app.bookings k on k.id = e.booking_id
    where e.salon_id = p_salon
      and (case when m.role = 'owner' then (pro is null or e.professional_id = pro)
                else e.professional_id = m.professional_id end)
      and (p_status is null or e.status = p_status)));
end $$;

-- ---------------------------------------------------------------------
-- Manual update: 'agreed' only via the Agree action; locked while a deposit is awaited.
-- ---------------------------------------------------------------------
create or replace function public.salon_dash_enquiry_update(p_enquiry uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare e app.enquiries; m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); uid uuid := auth.uid(); new_pro uuid;
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  select * into e from app.enquiries where id = p_enquiry for update;
  if e.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = e.salon_id and status = 'active';
  end if;
  if e.id is null or m.id is null or not (m.role = 'owner' or e.professional_id = m.professional_id) then
    perform app.fail('not_found', 'Enquiry not found.');
  end if;
  if a ? 'professional_id' then
    if m.role <> 'owner' then perform app.fail('forbidden', 'Only the owner can reassign an enquiry.'); end if;
    new_pro := nullif(a->>'professional_id', '')::uuid;
    if new_pro is not null and not exists (select 1 from app.professionals where id = new_pro and salon_id = e.salon_id) then
      perform app.fail('forbidden', 'That profile is not part of this salon.');
    end if;
    if new_pro is distinct from e.professional_id and e.status = 'agreed' then
      perform app.fail('locked', 'This enquiry is waiting for a deposit. Decline or cancel its booking first.');
    end if;
  else
    new_pro := e.professional_id;
  end if;
  if a ? 'status' and a->>'status' is distinct from e.status then
    if a->>'status' not in ('new','contacted','booked','closed') then
      perform app.fail('invalid_status', case when a->>'status' = 'agreed'
        then 'Use "Agreed, request deposit" to mark an enquiry as agreed.' else 'Unknown status.' end);
    end if;
    if e.status = 'agreed' then
      perform app.fail('locked', 'This enquiry is waiting for a deposit. It becomes Booked when you press "Deposit received" on its booking.');
    end if;
  end if;
  update app.enquiries set status = coalesce(a->>'status', status),
         internal_note = case when a ? 'internal_note' then app.clean_text(a->>'internal_note', 2000) else internal_note end,
         professional_id = new_pro, updated_at = now()
   where id = e.id returning * into e;
  perform app.audit(e.salon_id, e.professional_id, uid, app.actor_label(m), 'enquiry.updated', 'enquiry', e.id::text,
                    jsonb_build_object('status', e.status));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Agree: hold the time and send the deposit request
-- payload: date (YYYY-MM-DD), time (HH:MM), duration_min, deposit_pence
-- ---------------------------------------------------------------------
create or replace function public.salon_dash_enquiry_agree(p_enquiry uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  e app.enquiries; m app.memberships; s app.salons; v app.services; c app.clients; k app.bookings;
  a jsonb := coalesce(p_payload, '{}'::jsonb); uid uuid := auth.uid();
  d date; t time; st timestamptz; dur int; dep int; problem text;
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  select * into e from app.enquiries where id = p_enquiry for update;
  if e.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = e.salon_id and status = 'active';
  end if;
  if e.id is null or m.id is null or not (m.role = 'owner' or e.professional_id = m.professional_id) then
    perform app.fail('not_found', 'Enquiry not found.');
  end if;
  if e.status not in ('new','contacted') then
    perform app.fail('invalid_status', case when e.status = 'agreed' then 'This enquiry is already agreed and waiting for the deposit.'
                                            else 'This enquiry is already ' || e.status || '.' end);
  end if;
  if e.professional_id is null then
    perform app.fail('professional_required', 'Assign this enquiry to an artist first (Update status or note).');
  end if;
  select * into s from app.salons where id = e.salon_id;
  select * into v from app.services where professional_id = e.professional_id and category = 'bridal' and active
   order by sort_order limit 1;
  if v.id is null then perform app.fail('service_not_found', 'This artist has no Bridal service set up.'); end if;

  d := app.parse_date_strict(a->>'date');
  t := app.parse_time(a->>'time');
  if t is null then perform app.fail('time_required', 'Enter the start time.'); end if;
  dur := nullif(a->>'duration_min', '')::int;
  if dur is null or dur < 15 or dur > 720 then perform app.fail('duration_invalid', 'Enter how long it takes, between 15 minutes and 12 hours.'); end if;
  dep := nullif(a->>'deposit_pence', '')::int;
  if dep is null or dep <= 0 or dep > 1000000 then perform app.fail('deposit_invalid', 'Enter the deposit amount.'); end if;
  if app.deposit_payment_text(s, e.professional_id) is null then
    perform app.fail('deposit_details_missing', 'Add your payment details in Settings first, so the client knows where to pay the deposit.');
  end if;

  st := (d + t) at time zone s.timezone;
  if st <= now() then perform app.fail('too_late', 'That time has already passed.'); end if;
  v.duration_min := dur;
  perform app.lock_pro(e.professional_id);
  problem := app.slot_problem(s, v, st, null, false, false);
  if problem is not null then
    perform app.fail(case when problem = 'taken' then 'slot_taken' else 'slot_unavailable' end, app.problem_message(problem));
  end if;

  c := app.upsert_client(s.id, e.professional_id, e.phone, e.name, e.email, false, true);
  k := app.insert_booking(s, v, c, st, 'pending', 'dashboard', null,
                          app.clean_text('From bridal enquiry' || coalesce(': ' || e.event_location, ''), 2000), uid, 1);
  update app.bookings
     set deposit_pence = dep, deposit_status = 'requested',
         deposit_due_at = least(now() + make_interval(hours => s.deposit_hours), k.starts_at),
         version = version + 1, updated_at = now()
   where id = k.id returning * into k;
  perform app.notify_booking(k, 'deposit_request', 'customer');
  update app.enquiries set status = 'agreed', booking_id = k.id, agreed_at = now(), updated_at = now() where id = e.id;
  perform app.audit(e.salon_id, e.professional_id, uid, app.actor_label(m), 'enquiry.agreed', 'enquiry', e.id::text,
                    jsonb_build_object('ref', k.ref, 'deposit_pence', dep));
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k));
end $$;

-- ---------------------------------------------------------------------
-- Keep the enquiry in step with its booking
-- ---------------------------------------------------------------------
create or replace function app.enquiry_follow_booking()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'confirmed' then
    update app.enquiries set status = 'booked', updated_at = now()
     where booking_id = new.id and status = 'agreed';
  elsif new.status in ('declined','cancelled','expired') then
    update app.enquiries set status = 'contacted', booking_id = null, updated_at = now()
     where booking_id = new.id and status in ('agreed','booked');
  end if;
  return new;
end $$;

drop trigger if exists bookings_enquiry_follow on app.bookings;
create trigger bookings_enquiry_follow after update of status on app.bookings
  for each row when (old.status is distinct from new.status) execute function app.enquiry_follow_booking();

do $$
begin
  revoke all on function public.salon_dash_enquiry_agree(uuid, jsonb) from public;
  revoke all on function public.salon_dash_enquiries(uuid, uuid, text) from public;
  revoke all on function public.salon_dash_enquiry_update(uuid, jsonb) from public;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.salon_dash_enquiry_agree(uuid, jsonb) from anon;
    grant execute on function public.salon_dash_enquiry_agree(uuid, jsonb) to authenticated;
    grant execute on function public.salon_dash_enquiries(uuid, uuid, text) to authenticated;
    grant execute on function public.salon_dash_enquiry_update(uuid, jsonb) to authenticated;
  end if;
end $$;
