-- Round 7 (client, 2026-10-16): group bookings.
-- A booking has a party size (1-6). Duration and price scale with it, so one booking holds
-- party_size x the service time with ONE artist (no overlap possible, same constraint as before).
-- Deposit stays one fixed amount per booking.  Re-runnable.

alter table app.bookings add column if not exists party_size int not null default 1;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'bookings_party_size_range') then
    alter table app.bookings add constraint bookings_party_size_range check (party_size between 1 and 6);
  end if;
end $$;

create or replace function app.parse_party(p text)
returns int language plpgsql immutable set search_path = '' as $$
begin
  if p is null or btrim(p) = '' then return 1; end if;
  if btrim(p) !~ '^[0-9]{1,2}$' or btrim(p)::int not between 1 and 6 then
    perform app.fail('party_invalid', 'Group size must be between 1 and 6 people. For larger groups please send an enquiry.');
  end if;
  return btrim(p)::int;
end $$;

create or replace function app.scale_service(v app.services, n int)
returns app.services language plpgsql immutable set search_path = '' as $$
begin
  v.duration_min := v.duration_min * greatest(coalesce(n, 1), 1);
  if v.price_pence is not null then v.price_pence := v.price_pence * greatest(coalesce(n, 1), 1); end if;
  return v;
end $$;

drop function if exists app.insert_booking(app.salons, app.services, app.clients, timestamptz, text, text, text, text, uuid);

create or replace function app.insert_booking(s app.salons, v app.services, c app.clients, p_start timestamptz,
                                              p_status text, p_source text, p_note text, p_internal text,
                                              p_actor uuid, p_party int default 1)
returns app.bookings language plpgsql set search_path = '' as $$
declare k app.bookings;
begin
  p_party := coalesce(p_party, 1);
  v := app.scale_service(v, p_party);
  perform app.lock_pro(v.professional_id);
  if app.slot_problem(s, v, p_start, null, false, false) = 'taken' then
    perform app.fail('slot_taken', app.problem_message('taken'));
  end if;
  begin
    insert into app.bookings (salon_id, professional_id, service_id, client_id, ref, starts_at, ends_at, block_end,
                              status, source, service_name, duration_min, buffer_min, price_pence, price_kind,
                              customer_note, internal_note, confirmed_at, created_by, party_size)
    values (s.id, v.professional_id, v.id, c.id, app.new_ref(s.id), p_start,
            p_start + make_interval(mins => v.duration_min),
            p_start + make_interval(mins => v.duration_min + v.buffer_min),
            p_status, p_source, v.name, v.duration_min, v.buffer_min, v.price_pence, v.price_kind,
            p_note, p_internal, case when p_status = 'confirmed' then now() end, p_actor, p_party)
    returning * into k;
  exception when exclusion_violation or deadlock_detected then
    perform app.fail('slot_taken', app.problem_message('taken'));
  end;
  return k;
end $$;

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
    'party_size', k.party_size, 'duration_min', k.duration_min, 'buffer_min', k.buffer_min,
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

drop function if exists public.salon_public_days(text, text, text, date, int);
create or replace function public.salon_public_days(p_salon text, p_professional text, p_service text,
                                                    p_from date, p_days int default 35, p_party int default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s app.salons; p app.professionals; v app.services; v_code text; v_detail text;
        d_from date; d_to date; res jsonb;
begin
  s := app.resolve_salon(p_salon);
  p := app.resolve_public_pro(s.id, p_professional);
  v := app.scale_service(app.public_service(p, p_service), app.parse_party(p_party::text));
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

drop function if exists public.salon_public_slots(text, text, text, text);
create or replace function public.salon_public_slots(p_salon text, p_professional text, p_service text, p_date text, p_party int default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s app.salons; p app.professionals; v app.services; d date; v_code text; v_detail text; res jsonb;
begin
  s := app.resolve_salon(p_salon);
  p := app.resolve_public_pro(s.id, p_professional);
  v := app.scale_service(app.public_service(p, p_service), app.parse_party(p_party::text));
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

create or replace function public.salon_public_book(p_salon text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s app.salons; p app.professionals; v app.services; c app.clients; k app.bookings;
  d date; t time; st timestamptz; problem text; tok text; res jsonb; prior app.idempotency;
  v_name text; v_phone text; v_email text; v_note text; v_idem text; v_key text; v_ip text; n int;
  v_code text; v_detail text; v_party int;
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
  v_party := app.parse_party(a->>'party_size');
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
             'p', p.id, 's', v.id, 'd', d, 't', t, 'ph', v_phone, 'n', v_name, 'g', v_party)::text);
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
  problem := app.slot_problem(s, app.scale_service(v, v_party), st, null, true, true);
  if problem is not null then
    perform app.fail(case when problem = 'taken' then 'slot_taken' else 'slot_unavailable' end, app.problem_message(problem));
  end if;

  c := app.upsert_client(s.id, p.id, v_phone, v_name, v_email, coalesce((a->>'marketing_consent')::boolean, false), false);
  k := app.insert_booking(s, v, c, st, 'pending', 'website', v_note, null, null, v_party);

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
    'service', k.service_name, 'party_size', k.party_size, 'duration_min', k.duration_min,
    'price_label', app.fmt_price(k.price_pence, k.price_kind),
    'manage_token', tok, 'preview', s.booking_mode = 'preview',
    'message', 'Your request is in. It is provisional until ' || p.short_name || ' confirms.');
  update app.idempotency set result = res where salon_id = s.id and key = v_key;
  return res;
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

create or replace function public.salon_dash_booking_create(p_salon uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  m app.memberships; s app.salons; pro uuid; v app.services; c app.clients; k app.bookings;
  a jsonb := coalesce(p_payload, '{}'::jsonb); d date; t time; st timestamptz; problem text;
  v_party int; v_phone text; v_name text; v_status text; v_source text; v_idem text; v_key text; prior app.idempotency; res jsonb;
begin
  m := app.my_membership(p_salon);
  select * into s from app.salons where id = p_salon;
  if m.role = 'owner' then
    if coalesce(a->>'professional_id', '') = '' then perform app.fail('professional_required', 'Choose a professional.'); end if;
    pro := app.scope_pro(m, (a->>'professional_id')::uuid);
  else
    pro := app.scope_pro(m, nullif(a->>'professional_id', '')::uuid);
  end if;

  v_idem := a->>'idempotency_key';
  if v_idem is not null then
    if v_idem !~ '^[A-Za-z0-9_-]{16,64}$' then perform app.fail('invalid_request', 'Invalid request key.'); end if;
    v_key := 'dash-book:' || v_idem;
    insert into app.idempotency (salon_id, key) values (s.id, v_key) on conflict do nothing;
    if not found then
      select * into prior from app.idempotency where salon_id = s.id and key = v_key;
      if prior.result is not null then return prior.result || jsonb_build_object('duplicate', true); end if;
      perform app.fail('in_progress', 'Still saving this booking.');
    end if;
  end if;

  select * into v from app.services where id = nullif(a->>'service_id', '')::uuid and professional_id = pro and active;
  if v.id is null then perform app.fail('service_not_found', 'Choose a service offered by this professional.'); end if;
  v_party := app.parse_party(a->>'party_size');
  d := app.parse_date_strict(a->>'date');
  t := app.parse_time(a->>'time');
  if t is null then perform app.fail('time_required', 'Choose a time.'); end if;
  st := (d + t) at time zone s.timezone;
  perform app.lock_pro(pro);
  problem := app.slot_problem(s, app.scale_service(v, v_party), st, null, not coalesce((a->>'allow_outside_hours')::boolean, false), false);
  if problem is not null then
    perform app.fail(case when problem = 'taken' then 'slot_taken' else 'slot_unavailable' end, app.problem_message(problem));
  end if;

  if coalesce(a->>'client_id', '') <> '' then
    select * into c from app.clients where id = (a->>'client_id')::uuid and professional_id = pro;
    if c.id is null then perform app.fail('client_not_found', 'Client not found.'); end if;
  else
    v_name := app.clean_text(a->>'name', 80);
    v_phone := app.norm_phone(a->>'phone', s.country_code);
    if v_name is null or length(v_name) < 2 then perform app.fail('name_required', 'Enter the client''s name.'); end if;
    if not app.valid_phone(v_phone) then perform app.fail('phone_required', 'Enter a valid mobile number.'); end if;
    if coalesce(a->>'email', '') <> '' and not app.valid_email(lower(a->>'email')) then
      perform app.fail('email_invalid', 'Check the email address.');
    end if;
    c := app.upsert_client(s.id, pro, v_phone, v_name, lower(app.clean_text(a->>'email', 254)), false, true);
  end if;

  v_status := case when a->>'status' = 'pending' then 'pending' else 'confirmed' end;
  v_source := case when a->>'source' in ('phone','walk_in','other') then a->>'source' else 'dashboard' end;
  k := app.insert_booking(s, v, c, st, v_status, v_source, app.clean_text(a->>'customer_note', 500),
                          app.clean_text(a->>'internal_note', 2000), auth.uid(), v_party);
  if v_status = 'confirmed' then perform app.notify_booking(k, 'confirmed', 'customer'); end if;
  perform app.audit(s.id, pro, auth.uid(), app.actor_label(m), 'booking.created', 'booking', k.id::text,
                    jsonb_build_object('ref', k.ref, 'status', v_status, 'source', v_source,
                                       'outside_hours', coalesce((a->>'allow_outside_hours')::boolean, false)));
  res := jsonb_build_object('ok', true, 'booking', app.booking_json(k));
  if v_key is not null then update app.idempotency set result = res where salon_id = s.id and key = v_key; end if;
  return res;
end $$;

drop function if exists public.salon_dash_slots(uuid, uuid, uuid, text, uuid);
create or replace function public.salon_dash_slots(p_salon uuid, p_professional uuid, p_service uuid, p_date text,
                                                   p_exclude_booking uuid default null, p_party int default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; s app.salons; pro uuid; v app.services; d date; ex app.bookings;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  if pro is null then perform app.fail('professional_required', 'Choose a professional.'); end if;
  select * into s from app.salons where id = p_salon;
  select * into v from app.services where id = p_service and professional_id = pro;
  if v.id is null then perform app.fail('service_not_found', 'Choose a service.'); end if;
  if p_exclude_booking is not null then
    ex := app.booking_for_caller(p_exclude_booking, false);
    if ex.service_id = v.id then v.duration_min := ex.duration_min; v.buffer_min := ex.buffer_min;
    else v := app.scale_service(v, app.parse_party(p_party::text)); end if;
  else
    v := app.scale_service(v, app.parse_party(p_party::text));
  end if;
  d := app.parse_date_strict(p_date);
  return jsonb_build_object('ok', true, 'date', to_char(d, 'YYYY-MM-DD'), 'slots', (
    select coalesce(jsonb_agg(jsonb_build_object('time', to_char(f at time zone s.timezone, 'HH24:MI'),
             'label', lower(to_char(f at time zone s.timezone, 'FMHH12:MIam'))) order by f), '[]'::jsonb)
    from app.free_starts(s, v, d, p_exclude_booking, false) f));
end $$;


-- permissions: public RPCs for visitors, dashboard RPC for signed-in staff only
do $$
begin
  revoke all on function public.salon_public_days(text, text, text, date, int, int) from public;
  revoke all on function public.salon_public_slots(text, text, text, text, int) from public;
  revoke all on function public.salon_dash_slots(uuid, uuid, uuid, text, uuid, int) from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.salon_dash_slots(uuid, uuid, uuid, text, uuid, int) from anon;
    grant execute on function public.salon_public_days(text, text, text, date, int, int) to anon, authenticated;
    grant execute on function public.salon_public_slots(text, text, text, text, int) to anon, authenticated;
    grant execute on function public.salon_dash_slots(uuid, uuid, uuid, text, uuid, int) to authenticated;
  end if;
end $$;
