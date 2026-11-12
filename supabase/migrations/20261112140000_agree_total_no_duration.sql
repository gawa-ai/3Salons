-- Agree-and-request-deposit dialog: "How long" is no longer asked (3 hours is held by default)
-- and a "Total (including travel)" amount is recorded on the booking.
-- payload: date, time, deposit_pence, total_pence (optional, must be >= deposit); duration_min optional
create or replace function public.salon_dash_enquiry_agree(p_enquiry uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  e app.enquiries; m app.memberships; s app.salons; v app.services; c app.clients; k app.bookings;
  a jsonb := coalesce(p_payload, '{}'::jsonb); uid uuid := auth.uid();
  d date; t time; st timestamptz; dur int; dep int; tot int; problem text;
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
  dur := coalesce(nullif(a->>'duration_min', '')::int, 180);   -- length is no longer asked; hold 3 hours by default
  if dur < 15 or dur > 720 then perform app.fail('duration_invalid', 'Enter how long it takes, between 15 minutes and 12 hours.'); end if;
  dep := nullif(a->>'deposit_pence', '')::int;
  if dep is null or dep <= 0 or dep > 1000000 then perform app.fail('deposit_invalid', 'Enter the deposit amount.'); end if;
  tot := nullif(a->>'total_pence', '')::int;
  if tot is not null and (tot < dep or tot > 10000000) then
    perform app.fail('total_invalid', 'The total (including travel) cannot be less than the deposit.');
  end if;
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
         price_pence = coalesce(tot, price_pence), price_kind = case when tot is not null then 'fixed' else price_kind end,
         deposit_due_at = least(now() + make_interval(hours => s.deposit_hours), k.starts_at),
         version = version + 1, updated_at = now()
   where id = k.id returning * into k;
  perform app.notify_booking(k, 'deposit_request', 'customer');
  update app.enquiries set status = 'agreed', booking_id = k.id, agreed_at = now(), updated_at = now() where id = e.id;
  perform app.audit(e.salon_id, e.professional_id, uid, app.actor_label(m), 'enquiry.agreed', 'enquiry', e.id::text,
                    jsonb_build_object('ref', k.ref, 'deposit_pence', dep, 'total_pence', tot));
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k));
end $$;

do $$
begin
  revoke all on function public.salon_dash_enquiry_agree(uuid, jsonb) from public;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.salon_dash_enquiry_agree(uuid, jsonb) from anon;
    grant execute on function public.salon_dash_enquiry_agree(uuid, jsonb) to authenticated;
  end if;
end $$;
