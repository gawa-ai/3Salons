-- =====================================================================
-- Public API (callable by anon + authenticated). Exposes ONLY published
-- profile/service information and bare available times. Never returns
-- client identities, notes or other customers' bookings.
-- All functions return {ok:true,...} or {ok:false,error,message}.
-- =====================================================================

create or replace function app.public_service(p app.professionals, p_service text)
returns app.services language plpgsql stable set search_path = '' as $$
declare v app.services;
begin
  if p_service !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    perform app.fail('service_not_found', 'Please choose a service.');
  end if;
  select * into v from app.services
   where id = p_service::uuid and professional_id = p.id and active;
  if v.id is null then perform app.fail('service_not_found', 'Please choose one of this professional''s services.'); end if;
  if not v.bookable_online then
    perform app.fail('enquiry_only', 'This service is booked by enquiry. Please send an enquiry instead.');
  end if;
  return v;
end $$;

create or replace function app.parse_date_strict(p text)
returns date language plpgsql immutable set search_path = '' as $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}$' then
    perform app.fail('invalid_date', 'Please choose a date.');
  end if;
  return p::date;
exception when datetime_field_overflow or invalid_datetime_format then
  perform app.fail('invalid_date', 'That date is not valid.');
  return null;
end $$;

create or replace function app.err_json(p_code text, p_detail text)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('ok', false, 'error', p_code, 'message', coalesce(nullif(p_detail, ''), p_code))
$$;

-- ---------------------------------------------------------------------
create or replace function public.salon_public_profile(p_salon text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s app.salons; v_code text; v_detail text;
begin
  s := app.resolve_salon(p_salon);
  return jsonb_build_object(
    'ok', true,
    'salon', jsonb_build_object(
      'id', s.id, 'slug', s.slug, 'name', s.name, 'tagline', s.tagline, 'city', s.city,
      'address', s.address, 'phone', s.phone, 'whatsapp', s.whatsapp, 'email', s.email,
      'instagram_url', s.instagram_url, 'booking_mode', s.booking_mode, 'booking_policy', s.booking_policy,
      'timezone', s.timezone, 'hours_confirmed', s.hours_confirmed,
      'min_notice_min', s.min_notice_min, 'max_days_ahead', s.max_days_ahead,
      'today', to_char(now() at time zone s.timezone, 'YYYY-MM-DD'),
      'hours', case when s.hours_confirmed then (
        select coalesce(jsonb_agg(jsonb_build_object('weekday', h.weekday,
                 'opens', to_char(h.opens, 'HH24:MI'), 'closes', to_char(h.closes, 'HH24:MI'))
                 order by (h.weekday + 6) % 7, h.opens), '[]'::jsonb)
        from app.opening_hours h where h.salon_id = s.id) else null end),
    'professionals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'slug', p.slug, 'display_name', p.display_name, 'short_name', p.short_name,
        'specialty', p.specialty, 'bio', p.bio, 'instagram_url', p.instagram_url,
        'logo_path', p.logo_path, 'color', p.color, 'online_booking', p.online_booking,
        'services', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'id', v.id, 'name', v.name, 'description', v.description, 'category', v.category,
            'duration_min', v.duration_min, 'price_pence', case when v.price_kind = 'enquire' then null else v.price_pence end,
            'price_kind', v.price_kind, 'price_label', app.fmt_price(v.price_pence, v.price_kind),
            'bookable_online', v.bookable_online and p.online_booking)
            order by v.sort_order, v.name), '[]'::jsonb)
          from app.services v where v.professional_id = p.id and v.active))
        order by p.sort_order, p.display_name), '[]'::jsonb)
      from app.professionals p where p.salon_id = s.id and p.active and p.is_public));
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
-- Days that have at least one open slot (for the date picker). Max 42 days per call.
create or replace function public.salon_public_days(p_salon text, p_professional text, p_service text,
                                                    p_from date, p_days int default 35)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s app.salons; p app.professionals; v app.services; v_code text; v_detail text;
        d_from date; d_to date; res jsonb;
begin
  s := app.resolve_salon(p_salon);
  p := app.resolve_public_pro(s.id, p_professional);
  v := app.public_service(p, p_service);
  d_from := greatest(coalesce(p_from, (now() at time zone s.timezone)::date), (now() at time zone s.timezone)::date);
  d_to := least(d_from + least(greatest(coalesce(p_days, 35), 1), 42) - 1,
                (now() at time zone s.timezone)::date + s.max_days_ahead);
  select coalesce(jsonb_agg(jsonb_build_object('date', to_char(x.d, 'YYYY-MM-DD'), 'slots', x.n) order by x.d), '[]'::jsonb)
    into res
  from (
    select d::date as d, (select count(*) from app.free_starts(s, v, d::date)) as n
    from generate_series(d_from, d_to, interval '1 day') d
  ) x where x.n > 0;
  return jsonb_build_object('ok', true, 'from', to_char(d_from, 'YYYY-MM-DD'), 'to', to_char(d_to, 'YYYY-MM-DD'),
                            'days', res, 'duration_min', v.duration_min);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
create or replace function public.salon_public_slots(p_salon text, p_professional text, p_service text, p_date text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s app.salons; p app.professionals; v app.services; d date; v_code text; v_detail text; res jsonb;
begin
  s := app.resolve_salon(p_salon);
  p := app.resolve_public_pro(s.id, p_professional);
  v := app.public_service(p, p_service);
  d := app.parse_date_strict(p_date);
  select coalesce(jsonb_agg(jsonb_build_object(
           'time', to_char(f at time zone s.timezone, 'HH24:MI'),
           'label', lower(to_char(f at time zone s.timezone, 'FMHH12:MIam'))) order by f), '[]'::jsonb)
    into res from app.free_starts(s, v, d) f;
  return jsonb_build_object('ok', true, 'date', to_char(d, 'YYYY-MM-DD'), 'slots', res,
                            'timezone', s.timezone, 'duration_min', v.duration_min);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
-- Create a PROVISIONAL (pending) booking. The professional confirms or declines it.
-- Price, duration and availability are computed here, never taken from the client.
create or replace function public.salon_public_book(p_salon text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s app.salons; p app.professionals; v app.services; c app.clients; k app.bookings;
  d date; t time; st timestamptz; problem text; tok text; res jsonb; prior app.idempotency;
  v_name text; v_phone text; v_email text; v_note text; v_idem text; v_key text; v_ip text; n int;
  v_code text; v_detail text;
  a jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  s := app.resolve_salon(p_salon);
  if s.booking_mode = 'closed' then
    perform app.fail('booking_closed', 'Online booking is not open yet. Please contact the salon.');
  end if;
  if coalesce(a->>'company', '') <> '' then
    perform app.fail('rejected', 'Your request could not be accepted.');
  end if;

  p := app.resolve_public_pro(s.id, a->>'professional');
  if not p.online_booking then
    perform app.fail('online_booking_off', p.display_name || ' is not taking online bookings right now.');
  end if;
  v := app.public_service(p, a->>'service');
  d := app.parse_date_strict(a->>'date');
  t := app.parse_time(a->>'time');
  if t is null then perform app.fail('time_required', 'Please choose a time.'); end if;

  v_name := app.clean_text(a->>'name', 80);
  if v_name is null or length(v_name) < 2 then perform app.fail('name_required', 'Please enter your name.'); end if;
  v_phone := app.norm_phone(a->>'phone', s.country_code);
  if not app.valid_phone(v_phone) then
    perform app.fail('phone_required', 'Please enter a valid mobile number.');
  end if;
  v_email := lower(app.clean_text(a->>'email', 254));
  if v_email is not null and not app.valid_email(v_email) then
    perform app.fail('email_invalid', 'Please check your email address.');
  end if;
  v_note := app.clean_text(a->>'note', 500);
  if s.booking_policy is not null and not coalesce((a->>'policy_accepted')::boolean, false) then
    perform app.fail('policy_required', 'Please read and accept the booking policy.');
  end if;

  v_idem := a->>'idempotency_key';
  if v_idem is null or v_idem !~ '^[A-Za-z0-9_-]{16,64}$' then
    perform app.fail('invalid_request', 'Please refresh the page and try again.');
  end if;
  v_key := 'public-book:' || v_idem || ':' || md5(jsonb_build_object(
             'p', p.id, 's', v.id, 'd', d, 't', t, 'ph', v_phone, 'n', v_name)::text);
  insert into app.idempotency (salon_id, key) values (s.id, v_key) on conflict do nothing;
  if not found then
    select * into prior from app.idempotency where salon_id = s.id and key = v_key;
    if prior.result is not null then return prior.result || jsonb_build_object('duplicate', true); end if;
    return app.err_json('in_progress', 'We are still processing your booking. Please wait a moment.');
  end if;

  -- abuse limits (only successful-looking attempts count; failures roll back)
  v_ip := app.request_ip();
  if v_ip is not null then perform app.rate_check('book-ip:' || v_ip, 8, interval '1 hour'); end if;
  perform app.rate_check('book-salon:' || s.id::text, 60, interval '10 minutes');
  select count(*) into n from app.bookings k2 join app.clients c2 on c2.id = k2.client_id
   where k2.salon_id = s.id and c2.phone = v_phone and k2.source = 'website'
     and k2.status in ('pending','confirmed') and k2.starts_at > now();
  if n >= 3 then
    perform app.fail('too_many_bookings', 'You already have several upcoming bookings. Please contact the salon to book more.');
  end if;

  st := (d + t) at time zone s.timezone;
  perform app.lock_pro(p.id);
  problem := app.slot_problem(s, v, st, null, true, true);
  if problem is not null then
    perform app.fail(case when problem = 'taken' then 'slot_taken' else 'slot_unavailable' end, app.problem_message(problem));
  end if;

  c := app.upsert_client(s.id, p.id, v_phone, v_name, v_email, coalesce((a->>'marketing_consent')::boolean, false), false);
  k := app.insert_booking(s, v, c, st, 'pending', 'website', v_note, null, null);

  tok := app.random_token(24);
  update app.bookings set manage_token_hash = app.hash_token(tok),
                          manage_token_expires_at = k.ends_at + interval '1 day'
   where id = k.id returning * into k;

  perform app.notify_booking(k, 'request_received', 'customer');
  perform app.notify_booking(k, 'new_request', 'professional');
  perform app.audit(s.id, p.id, auth.uid(), 'customer', 'booking.requested', 'booking', k.id::text,
                    jsonb_build_object('ref', k.ref, 'source', 'website'));

  res := jsonb_build_object(
    'ok', true, 'ref', k.ref, 'status', k.status,
    'when', app.fmt_when(k.starts_at, s.timezone),
    'date', to_char(k.starts_at at time zone s.timezone, 'YYYY-MM-DD'),
    'time', to_char(k.starts_at at time zone s.timezone, 'HH24:MI'),
    'professional', p.display_name, 'professional_short', p.short_name,
    'service', k.service_name, 'duration_min', k.duration_min,
    'price_label', app.fmt_price(k.price_pence, k.price_kind),
    'manage_token', tok, 'preview', s.booking_mode = 'preview',
    'message', 'Your request is in. It is provisional until ' || p.short_name || ' confirms.');
  update app.idempotency set result = res where salon_id = s.id and key = v_key;
  return res;
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
-- Bridal / general enquiry
create or replace function public.salon_public_enquiry(p_salon text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s app.salons; p app.professionals; e app.enquiries; a jsonb := coalesce(p_payload, '{}'::jsonb);
  v_name text; v_phone text; v_email text; v_date date; v_ip text; v_idem text; v_key text; prior app.idempotency;
  res jsonb; v_code text; v_detail text;
begin
  s := app.resolve_salon(p_salon);
  if coalesce(a->>'company', '') <> '' then perform app.fail('rejected', 'Your request could not be accepted.'); end if;
  if coalesce(a->>'professional', '') not in ('', 'any') then
    p := app.resolve_public_pro(s.id, a->>'professional');
  end if;
  v_name := app.clean_text(a->>'name', 80);
  if v_name is null or length(v_name) < 2 then perform app.fail('name_required', 'Please enter your name.'); end if;
  v_phone := app.norm_phone(a->>'phone', s.country_code);
  if not app.valid_phone(v_phone) then perform app.fail('phone_required', 'Please enter a valid mobile number.'); end if;
  v_email := lower(app.clean_text(a->>'email', 254));
  if v_email is not null and not app.valid_email(v_email) then perform app.fail('email_invalid', 'Please check your email address.'); end if;
  if coalesce(a->>'event_date', '') <> '' then
    v_date := app.parse_date_strict(a->>'event_date');
    if v_date < (now() at time zone s.timezone)::date then perform app.fail('date_in_past', 'Please choose a future date.'); end if;
  end if;

  v_idem := a->>'idempotency_key';
  if v_idem is null or v_idem !~ '^[A-Za-z0-9_-]{16,64}$' then
    perform app.fail('invalid_request', 'Please refresh the page and try again.');
  end if;
  v_key := 'public-enquiry:' || v_idem;
  insert into app.idempotency (salon_id, key) values (s.id, v_key) on conflict do nothing;
  if not found then
    select * into prior from app.idempotency where salon_id = s.id and key = v_key;
    if prior.result is not null then return prior.result || jsonb_build_object('duplicate', true); end if;
    return app.err_json('in_progress', 'Still sending your enquiry.');
  end if;

  v_ip := app.request_ip();
  if v_ip is not null then perform app.rate_check('enq-ip:' || v_ip, 5, interval '1 hour'); end if;
  perform app.rate_check('enq-salon:' || s.id::text, 40, interval '10 minutes');

  insert into app.enquiries (salon_id, professional_id, kind, name, phone, email, event_date, event_location, services_wanted, message)
  values (s.id, p.id, case when a->>'kind' = 'general' then 'general' else 'bridal' end, v_name, v_phone, v_email, v_date,
          app.clean_text(a->>'event_location', 120), app.clean_text(a->>'services_wanted', 200), app.clean_text(a->>'message', 1500))
  returning * into e;

  insert into app.notifications (salon_id, professional_id, enquiry_id, audience, channel, purpose, body, status, dedupe_key)
  values (s.id, p.id, e.id, 'professional', 'sms', 'new_enquiry',
          'New ' || e.kind || ' enquiry from ' || e.name || coalesce(' for ' || to_char(e.event_date, 'Dy FMDD Mon YYYY'), '') ||
          '. See your dashboard.',
          case when s.sms_connected then 'queued' else 'not_connected' end, 'enquiry:' || e.id::text);
  perform app.audit(s.id, p.id, auth.uid(), 'customer', 'enquiry.created', 'enquiry', e.id::text, jsonb_build_object('kind', e.kind));

  res := jsonb_build_object('ok', true, 'professional', p.display_name,
                            'message', 'Thank you. Your enquiry has been sent and the team will be in touch.');
  update app.idempotency set result = res where salon_id = s.id and key = v_key;
  return res;
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
-- Customer self-service through the private link (token never stored in plain text).
create or replace function app.booking_by_token(p_token text, p_lock boolean)
returns app.bookings language plpgsql set search_path = '' as $$
declare k app.bookings; v_ip text := app.request_ip();
begin
  if v_ip is not null then perform app.rate_check('manage-ip:' || v_ip, 40, interval '10 minutes'); end if;
  if p_token is null or length(p_token) < 20 or length(p_token) > 100 then
    perform app.fail('link_invalid', 'This link is not valid or has expired.');
  end if;
  if p_lock then
    select * into k from app.bookings where manage_token_hash = app.hash_token(p_token) for update;
  else
    select * into k from app.bookings where manage_token_hash = app.hash_token(p_token);
  end if;
  if k.id is null or k.manage_token_expires_at < now() then
    perform app.fail('link_invalid', 'This link is not valid or has expired.');
  end if;
  return k;
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
       'can_cancel', k.status in ('pending','confirmed') and k.starts_at > now()),
    'salon', jsonb_build_object('name', s.name, 'phone', s.phone, 'whatsapp', s.whatsapp, 'email', s.email,
                                'address', s.address, 'booking_policy', s.booking_policy, 'timezone', s.timezone));
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

create or replace function public.salon_public_manage_cancel(p_token text, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k app.bookings; s app.salons; v_code text; v_detail text; old_status text;
begin
  k := app.booking_by_token(p_token, true);
  select * into s from app.salons where id = k.salon_id;
  if k.status = 'cancelled' then
    return jsonb_build_object('ok', true, 'already', true, 'booking', app.booking_json(k, false));
  end if;
  if k.status not in ('pending','confirmed') or k.starts_at <= now() then
    perform app.fail('not_cancellable', 'This booking can no longer be cancelled online. Please contact the salon.');
  end if;
  old_status := k.status;
  update app.bookings set status = 'cancelled', cancelled_at = now(), version = version + 1, updated_at = now(),
         status_reason = coalesce(app.clean_text(p_reason, 300), 'Cancelled by the customer')
   where id = k.id returning * into k;
  perform app.notify_booking(k, 'cancelled', 'customer');
  perform app.notify_booking(k, 'cancelled_pro', 'professional');
  perform app.audit(k.salon_id, k.professional_id, null, 'customer', 'booking.cancelled', 'booking', k.id::text,
                    jsonb_build_object('ref', k.ref, 'from', old_status, 'via', 'manage_link'));
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k, false));
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
create or replace function public.salon_public_gallery(p_salon text, p_professional text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s app.salons; p app.professionals; v_code text; v_detail text;
begin
  s := app.resolve_salon(p_salon);
  if coalesce(p_professional, '') <> '' then p := app.resolve_public_pro(s.id, p_professional); end if;
  return jsonb_build_object('ok', true, 'items', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', g.id, 'professional_slug', pr.slug, 'professional', pr.display_name,
      'storage_path', g.storage_path, 'media_type', g.media_type, 'alt_text', g.alt_text, 'caption', g.caption)
      order by g.sort_order, g.created_at desc), '[]'::jsonb)
    from app.gallery_items g join app.professionals pr on pr.id = g.professional_id
    where g.salon_id = s.id and g.published and pr.active and pr.is_public
      and (p.id is null or g.professional_id = p.id)));
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;
