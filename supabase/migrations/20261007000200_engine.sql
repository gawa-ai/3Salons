-- =====================================================================
-- Engine: helpers, access resolution, availability, booking core,
-- notifications outbox and audit trail. Internal (schema app).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------

-- Business-rule failure. code goes in MESSAGE (machine-readable), human text in DETAIL.
create or replace function app.fail(p_code text, p_message text)
returns void language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = 'P0001', message = p_code, detail = p_message;
end $$;

create or replace function app.norm_phone(p text, p_cc text default '44')
returns text language sql immutable set search_path = '' as $$
  select case
    when p is null or btrim(p) = '' then null
    else (
      select case
        when s like '+%'  then '+' || regexp_replace(s, '[^0-9]', '', 'g')
        when s like '00%' then '+' || substr(s, 3)
        when s like '0%'  then '+' || coalesce(p_cc, '44') || substr(s, 2)
        when length(s) >= 11 then '+' || s
        else '+' || coalesce(p_cc, '44') || s
      end
      from (select regexp_replace(btrim(p), '[^0-9+]', '', 'g') as s) x
    )
  end
$$;

create or replace function app.valid_phone(p text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p ~ '^\+[1-9][0-9]{7,14}$', false)
$$;

create or replace function app.valid_email(p text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p ~* '^[^@\s<>]+@[^@\s<>]+\.[a-z]{2,}$' and length(p) <= 254, false)
$$;

-- '14:30', '2:30pm', '9', '0930'. NULL when empty/unparseable.
create or replace function app.parse_time(p text)
returns time language plpgsql immutable set search_path = '' as $$
declare s text; m text[]; h int; mi int := 0; ampm text;
begin
  if p is null or btrim(p) = '' then return null; end if;
  s := lower(regexp_replace(btrim(p), '\s+', '', 'g'));
  s := replace(replace(s, 'a.m.', 'am'), 'p.m.', 'pm');
  m := regexp_match(s, '^([0-9]{1,2})(?::|\.)?([0-9]{2})?(?::[0-9]{2})?(am|pm)?$');
  if m is null then return null; end if;
  h := m[1]::int; if m[2] is not null then mi := m[2]::int; end if; ampm := m[3];
  if ampm = 'pm' and h < 12 then h := h + 12; end if;
  if ampm = 'am' and h = 12 then h := 0; end if;
  if h > 23 or mi > 59 then return null; end if;
  return make_time(h, mi, 0);
end $$;

create or replace function app.fmt_when(p_ts timestamptz, p_tz text)
returns text language sql stable set search_path = '' as $$
  select to_char(p_ts at time zone p_tz, 'Dy FMDD Mon') || ' at ' ||
         lower(to_char(p_ts at time zone p_tz, 'FMHH12:MIam'))
$$;

create or replace function app.fmt_price(p_pence int, p_kind text)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_kind = 'enquire' or p_pence is null then 'Please enquire'
    else case when p_kind = 'from' then 'from ' else '' end ||
         '£' || case when p_pence % 100 = 0 then (p_pence / 100)::text
                     else to_char(p_pence / 100.0, 'FM999990.00') end
  end
$$;

create or replace function app.hash_token(p text)
returns text language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(coalesce(p, ''), 'UTF8'), 'sha256'), 'hex')
$$;

create or replace function app.random_token(p_bytes int default 24)
returns text language sql volatile set search_path = '' as $$
  select translate(rtrim(encode(extensions.gen_random_bytes(p_bytes), 'base64'), '='), '+/', '-_')
$$;

-- Human-friendly invite code, e.g. 'K7MP-3QXT-9WHC-R2FD' (31^16 combinations).
create or replace function app.random_code()
returns text language plpgsql volatile set search_path = '' as $$
declare alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; b bytea := extensions.gen_random_bytes(16); r text := ''; i int;
begin
  for i in 0..15 loop
    r := r || substr(alphabet, 1 + (get_byte(b, i) % 31), 1);
    if i in (3, 7, 11) then r := r || '-'; end if;
  end loop;
  return r;
end $$;

create or replace function app.norm_code(p text)
returns text language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

create or replace function app.new_ref(p_salon uuid)
returns text language plpgsql volatile set search_path = '' as $$
declare alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; r text; i int; b bytea;
begin
  loop
    b := extensions.gen_random_bytes(6); r := '';
    for i in 0..5 loop r := r || substr(alphabet, 1 + (get_byte(b, i) % 31), 1); end loop;
    exit when not exists (select 1 from app.bookings where salon_id = p_salon and ref = r);
  end loop;
  return r;
end $$;

create or replace function app.clean_text(p text, p_max int)
returns text language sql immutable set search_path = '' as $$
  select nullif(left(btrim(regexp_replace(coalesce(p, ''), '[\u0001-\u0008\u000B\u000C\u000E-\u001F\u007F]', '', 'g')), p_max), '')
$$;

-- ---------------------------------------------------------------------
-- Rate limiting for public endpoints
-- ---------------------------------------------------------------------
create or replace function app.request_ip()
returns text language sql stable set search_path = '' as $$
  select nullif(btrim(split_part(coalesce(
    nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for',
    nullif(current_setting('request.headers', true), '')::json ->> 'cf-connecting-ip', ''), ',', 1)), '')
$$;

create or replace function app.rate_check(p_bucket text, p_max int, p_window interval)
returns void language plpgsql set search_path = '' as $$
declare n int;
begin
  delete from app.rate_events where created_at < now() - interval '1 day';
  select count(*) into n from app.rate_events where bucket = p_bucket and created_at > now() - p_window;
  if n >= p_max then
    perform app.fail('rate_limited', 'Too many requests. Please wait a little and try again.');
  end if;
  insert into app.rate_events (bucket) values (p_bucket);
end $$;

-- ---------------------------------------------------------------------
-- Resolution & access control
-- ---------------------------------------------------------------------
create or replace function app.resolve_salon(p_salon text)
returns app.salons language plpgsql stable set search_path = '' as $$
declare s app.salons;
begin
  if p_salon ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into s from app.salons where id = p_salon::uuid;
  else
    select * into s from app.salons where slug = lower(btrim(coalesce(p_salon, '')));
  end if;
  if s.id is null then perform app.fail('salon_not_found', 'This salon is not configured.'); end if;
  return s;
end $$;

-- Public view of a professional (slug or id), must be public + active.
create or replace function app.resolve_public_pro(p_salon uuid, p_pro text)
returns app.professionals language plpgsql stable set search_path = '' as $$
declare p app.professionals;
begin
  if p_pro ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into p from app.professionals where salon_id = p_salon and id = p_pro::uuid;
  else
    select * into p from app.professionals where salon_id = p_salon and slug = lower(btrim(coalesce(p_pro, '')));
  end if;
  if p.id is null or not p.active or not p.is_public then
    perform app.fail('professional_not_found', 'Please choose one of our professionals.');
  end if;
  return p;
end $$;

-- The caller's active membership in a salon. Identity comes only from auth.uid().
create or replace function app.my_membership(p_salon uuid)
returns app.memberships language plpgsql stable set search_path = '' as $$
declare m app.memberships; uid uuid := auth.uid();
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  select * into m from app.memberships
   where user_id = uid and salon_id = p_salon and status = 'active';
  if m.id is null then perform app.fail('forbidden', 'You do not have access to this salon.'); end if;
  return m;
end $$;

create or replace function app.require_owner(p_salon uuid)
returns app.memberships language plpgsql stable set search_path = '' as $$
declare m app.memberships := app.my_membership(p_salon);
begin
  if m.role <> 'owner' then perform app.fail('forbidden', 'Only the salon owner can do this.'); end if;
  return m;
end $$;

-- Which professional the caller may see.
--   owner:        p_requested (NULL = all), must belong to the salon
--   professional: always their own profile; asking for another one is refused
create or replace function app.scope_pro(m app.memberships, p_requested uuid)
returns uuid language plpgsql stable set search_path = '' as $$
begin
  if m.role = 'owner' then
    if p_requested is not null and not exists
       (select 1 from app.professionals where id = p_requested and salon_id = m.salon_id) then
      perform app.fail('forbidden', 'That profile is not part of this salon.');
    end if;
    return p_requested;
  end if;
  if p_requested is not null and p_requested is distinct from m.professional_id then
    perform app.fail('forbidden', 'You can only view your own bookings.');
  end if;
  return m.professional_id;
end $$;

create or replace function app.can_see(m app.memberships, p_pro uuid)
returns boolean language sql stable set search_path = '' as $$
  select m.role = 'owner' or (p_pro is not null and p_pro = m.professional_id)
$$;

-- Load a booking the caller may act on. Same error whether it does not exist
-- or belongs to someone else, so other profiles' records cannot be probed.
create or replace function app.booking_for_caller(p_booking uuid, p_lock boolean default false)
returns app.bookings language plpgsql set search_path = '' as $$
declare k app.bookings; m app.memberships; uid uuid := auth.uid();
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  if p_lock then
    select * into k from app.bookings where id = p_booking for update;
  else
    select * into k from app.bookings where id = p_booking;
  end if;
  if k.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = k.salon_id and status = 'active';
  end if;
  if k.id is null or m.id is null or not app.can_see(m, k.professional_id) then
    perform app.fail('not_found', 'Booking not found.');
  end if;
  return k;
end $$;

create or replace function app.actor_label(m app.memberships)
returns text language sql immutable set search_path = '' as $$
  select coalesce(m.role, 'system')
$$;

create or replace function app.audit(p_salon uuid, p_pro uuid, p_actor uuid, p_label text,
                                     p_action text, p_entity text, p_entity_id text, p_detail jsonb default '{}'::jsonb)
returns void language sql set search_path = '' as $$
  insert into app.audit_log (salon_id, professional_id, actor_user_id, actor_label, action, entity, entity_id, detail)
  values (p_salon, p_pro, p_actor, p_label, p_action, p_entity, p_entity_id, coalesce(p_detail, '{}'::jsonb))
$$;

-- ---------------------------------------------------------------------
-- Availability
-- ---------------------------------------------------------------------

-- NULL when the slot is allowed, otherwise a reason code.
--   p_enforce_hours : salon opening hours, professional working hours, time off, online booking horizon
--   p_enforce_notice: minimum notice + maximum days ahead (public bookings)
create or replace function app.slot_problem(s app.salons, v app.services, p_start timestamptz,
                                            p_exclude uuid default null,
                                            p_enforce_hours boolean default true,
                                            p_enforce_notice boolean default true)
returns text language plpgsql stable set search_path = '' as $$
declare
  l_start timestamp := p_start at time zone s.timezone;
  e timestamptz := p_start + make_interval(mins => v.duration_min);
  b timestamptz := p_start + make_interval(mins => v.duration_min + v.buffer_min);
  l_end timestamp := e at time zone s.timezone;
  dow int := extract(dow from l_start);
begin
  if p_start < now() - interval '30 minutes' then return 'in_past'; end if;
  if p_enforce_notice then
    if p_start < now() + make_interval(mins => s.min_notice_min) then return 'too_soon'; end if;
    if p_start > now() + make_interval(days => s.max_days_ahead) then return 'too_far'; end if;
  end if;
  if l_end::date <> l_start::date then return 'crosses_midnight'; end if;
  if p_enforce_hours then
    if not exists (select 1 from app.opening_hours h
                   where h.salon_id = s.id and h.weekday = dow
                     and l_start::time >= h.opens and l_end::time <= h.closes) then
      return 'salon_closed';
    end if;
    if not exists (select 1 from app.working_hours w
                   where w.professional_id = v.professional_id and w.weekday = dow
                     and l_start::time >= w.opens and l_end::time <= w.closes) then
      return 'not_working';
    end if;
    if exists (select 1 from app.time_off t
               where t.salon_id = s.id and (t.professional_id is null or t.professional_id = v.professional_id)
                 and tstzrange(t.starts_at, t.ends_at, '[)') && tstzrange(p_start, b, '[)')) then
      return 'time_off';
    end if;
  end if;
  if exists (select 1 from app.bookings k
             where k.professional_id = v.professional_id
               and k.status in ('pending','confirmed')
               and k.id is distinct from p_exclude
               and tstzrange(k.starts_at, k.block_end, '[)') && tstzrange(p_start, b, '[)')) then
    return 'taken';
  end if;
  return null;
end $$;

create or replace function app.problem_message(p_code text)
returns text language sql immutable set search_path = '' as $$
  select case p_code
    when 'in_past'          then 'That time has already passed.'
    when 'too_soon'         then 'That time is too soon to book online. Please choose a later time.'
    when 'too_far'          then 'That date is too far ahead to book online.'
    when 'crosses_midnight' then 'That appointment would run past midnight.'
    when 'salon_closed'     then 'The salon is closed at that time.'
    when 'not_working'      then 'This professional is not working at that time.'
    when 'time_off'         then 'This professional is unavailable at that time.'
    when 'taken'            then 'Sorry, that time has just been taken. Please choose another time.'
    else 'That time is not available.' end
$$;

-- Bookable start times for one service on one local date.
create or replace function app.free_starts(s app.salons, v app.services, p_date date,
                                           p_exclude uuid default null, p_enforce_notice boolean default true)
returns setof timestamptz language sql stable set search_path = '' as $$
  select distinct c.st
  from (
    select (g at time zone s.timezone) as st
    from app.working_hours w
    cross join lateral generate_series(
      p_date + w.opens,
      p_date + w.closes - make_interval(mins => v.duration_min),
      make_interval(mins => s.slot_interval_min)) g
    where w.professional_id = v.professional_id
      and w.weekday = extract(dow from p_date)
  ) c
  where app.slot_problem(s, v, c.st, p_exclude, true, p_enforce_notice) is null
  order by c.st
$$;

-- ---------------------------------------------------------------------
-- Notifications outbox
-- ---------------------------------------------------------------------
create or replace function app.message_body(p_purpose text, s app.salons, p app.professionals,
                                            k app.bookings, c app.clients)
returns text language sql stable set search_path = '' as $$
  select replace(replace(replace(replace(replace(replace(replace(
    case p_purpose
      when 'request_received' then 'Hi {first}, thank you for your booking request with {pro} at {salon}: {service} on {when}. It is provisional until {pro_short} confirms. Ref {ref}.'
      when 'new_request'      then 'New booking request: {service} on {when} for {client}. Ref {ref}. Please confirm or decline in your dashboard.'
      when 'confirmed'        then 'Hi {first}, {pro_short} has confirmed your {service} on {when} at {salon}. Ref {ref}.'
      when 'declined'         then 'Hi {first}, sorry, {pro_short} cannot take your {service} request for {when}. Please choose another time on our website. Ref {ref}.'
      when 'cancelled'        then 'Hi {first}, your {service} with {pro_short} on {when} has been cancelled. Ref {ref}.'
      when 'cancelled_pro'    then 'Booking cancelled by the customer: {service} on {when} for {client}. Ref {ref}.'
      when 'rescheduled'      then 'Hi {first}, your {service} with {pro_short} has moved to {when}. Ref {ref}.'
      else '' end,
    '{first}', coalesce(nullif(split_part(btrim(coalesce(c.name, '')), ' ', 1), ''), 'there')),
    '{client}', coalesce(c.name, 'a client')),
    '{pro_short}', p.short_name),
    '{pro}', p.display_name),
    '{salon}', s.name),
    '{service}', k.service_name),
    '{when}', app.fmt_when(k.starts_at, s.timezone))
  -- {ref} replaced last so it cannot be injected through names
  -- (names are replaced before ref; ref is system generated)
$$;

create or replace function app.notify_booking(k app.bookings, p_purpose text, p_audience text)
returns void language plpgsql set search_path = '' as $$
declare s app.salons; p app.professionals; c app.clients; body text;
begin
  select * into s from app.salons where id = k.salon_id;
  select * into p from app.professionals where id = k.professional_id;
  select * into c from app.clients where id = k.client_id;
  body := replace(app.message_body(p_purpose, s, p, k, c), '{ref}', k.ref);
  insert into app.notifications (salon_id, professional_id, booking_id, audience, channel, purpose, to_addr, body, status, dedupe_key)
  values (k.salon_id, k.professional_id, k.id, p_audience, 'sms', p_purpose,
          case when p_audience = 'customer' then c.phone else null end,
          body,
          case when s.sms_connected then 'queued' else 'not_connected' end,
          k.id::text || ':v' || k.version || ':' || p_purpose || ':' || p_audience)
  on conflict (dedupe_key) do nothing;
  -- a cancelled/declined/moved booking must never get a stale queued message
  if p_purpose in ('cancelled','declined','rescheduled','cancelled_pro') then
    update app.notifications set status = 'cancelled', updated_at = now()
     where booking_id = k.id and status = 'queued'
       and dedupe_key not like k.id::text || ':v' || k.version || ':%';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Clients
-- ---------------------------------------------------------------------
-- Finds or creates the client record for (professional, phone). Never overwrites an
-- existing name/notes from an untrusted channel; only fills blanks.
create or replace function app.upsert_client(p_salon uuid, p_pro uuid, p_phone text, p_name text,
                                             p_email text, p_marketing boolean, p_trusted boolean)
returns app.clients language plpgsql set search_path = '' as $$
declare c app.clients;
begin
  insert into app.clients as cl (salon_id, professional_id, phone, name, email, marketing_consent, marketing_consent_at)
  values (p_salon, p_pro, p_phone, p_name, p_email, coalesce(p_marketing, false),
          case when coalesce(p_marketing, false) then now() end)
  on conflict (professional_id, phone) do update
    set name  = case when p_trusted then coalesce(excluded.name, cl.name) else coalesce(cl.name, excluded.name) end,
        email = case when p_trusted then coalesce(excluded.email, cl.email) else coalesce(cl.email, excluded.email) end,
        marketing_consent = cl.marketing_consent or coalesce(p_marketing, false),
        marketing_consent_at = case when not cl.marketing_consent and coalesce(p_marketing, false) then now()
                                    else cl.marketing_consent_at end,
        updated_at = now()
  returning * into c;
  return c;
end $$;

-- ---------------------------------------------------------------------
-- Booking core
-- ---------------------------------------------------------------------
-- Serialises writes for one professional so two requests for the same time
-- cannot deadlock on the exclusion constraint: the second waits, then sees the
-- first booking and gets a clean "slot_taken".
create or replace function app.lock_pro(p_pro uuid)
returns void language sql volatile set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended('salon-pro:' || p_pro::text, 0))
$$;

create or replace function app.insert_booking(s app.salons, v app.services, c app.clients, p_start timestamptz,
                                              p_status text, p_source text, p_note text, p_internal text,
                                              p_actor uuid)
returns app.bookings language plpgsql set search_path = '' as $$
declare k app.bookings;
begin
  perform app.lock_pro(v.professional_id);
  if app.slot_problem(s, v, p_start, null, false, false) = 'taken' then
    perform app.fail('slot_taken', app.problem_message('taken'));
  end if;
  begin
    insert into app.bookings (salon_id, professional_id, service_id, client_id, ref, starts_at, ends_at, block_end,
                              status, source, service_name, duration_min, buffer_min, price_pence, price_kind,
                              customer_note, internal_note, confirmed_at, created_by)
    values (s.id, v.professional_id, v.id, c.id, app.new_ref(s.id), p_start,
            p_start + make_interval(mins => v.duration_min),
            p_start + make_interval(mins => v.duration_min + v.buffer_min),
            p_status, p_source, v.name, v.duration_min, v.buffer_min, v.price_pence, v.price_kind,
            p_note, p_internal, case when p_status = 'confirmed' then now() end, p_actor)
    returning * into k;
  exception when exclusion_violation or deadlock_detected then
    perform app.fail('slot_taken', app.problem_message('taken'));
  end;
  return k;
end $$;

-- Pending requests whose start time has passed can no longer be confirmed.
create or replace function app.expire_stale(p_salon uuid)
returns void language plpgsql set search_path = '' as $$
declare r record;
begin
  for r in update app.bookings set status = 'expired', version = version + 1, updated_at = now(),
                                   status_reason = 'Not confirmed before the appointment time'
           where salon_id = p_salon and status = 'pending' and starts_at < now()
           returning id, professional_id loop
    perform app.audit(p_salon, r.professional_id, null, 'system', 'booking.expired', 'booking', r.id::text);
  end loop;
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
    'duration_min', k.duration_min, 'buffer_min', k.buffer_min,
    'price_pence', k.price_pence, 'price_kind', k.price_kind, 'price_label', app.fmt_price(k.price_pence, k.price_kind),
    'version', k.version, 'created_at', k.created_at, 'confirmed_at', k.confirmed_at,
    'cancelled_at', k.cancelled_at, 'status_reason', k.status_reason
  ) || case when p_include_private then jsonb_build_object(
    'client_id', c.id, 'client_name', c.name, 'client_phone', c.phone, 'client_email', c.email,
    'customer_note', k.customer_note, 'internal_note', k.internal_note) else '{}'::jsonb end
  from app.salons s, app.professionals p, app.clients c
  where s.id = k.salon_id and p.id = k.professional_id and c.id = k.client_id
$$;
