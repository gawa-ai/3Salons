-- =====================================================================
-- Dashboard API (authenticated only). Every function:
--   1. resolves the caller's active membership from auth.uid()
--   2. narrows to the professional scope the caller is allowed to see
--   3. returns only rows inside that scope
-- Business-rule failures raise P0001 with MESSAGE = code, DETAIL = human text.
-- =====================================================================

create or replace function public.salon_me()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); v_email text;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select email into v_email from auth.users where id = uid;
  return jsonb_build_object('ok', true,
    'user', jsonb_build_object('id', uid, 'email', v_email),
    'memberships', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'membership_id', m.id, 'role', m.role, 'display_name', m.display_name,
        'salon', jsonb_build_object('id', s.id, 'slug', s.slug, 'name', s.name, 'timezone', s.timezone,
                                    'booking_mode', s.booking_mode, 'sms_connected', s.sms_connected),
        'professional_id', m.professional_id,
        'professionals', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'id', p.id, 'slug', p.slug, 'display_name', p.display_name, 'short_name', p.short_name,
            'specialty', p.specialty, 'color', p.color, 'logo_path', p.logo_path, 'active', p.active)
            order by p.sort_order, p.display_name), '[]'::jsonb)
          from app.professionals p
          where p.salon_id = s.id and (m.role = 'owner' or p.id = m.professional_id))
      ) order by s.name), '[]'::jsonb)
      from app.memberships m join app.salons s on s.id = m.salon_id
      where m.user_id = uid and m.status = 'active'));
end $$;

-- ---------------------------------------------------------------------
create or replace function public.salon_dash_overview(p_salon uuid, p_professional uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; s app.salons; today date; t0 timestamptz; t1 timestamptz;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  select * into s from app.salons where id = p_salon;
  perform app.expire_stale(s.id);
  today := (now() at time zone s.timezone)::date;
  t0 := today::timestamp at time zone s.timezone;
  t1 := (today + 1)::timestamp at time zone s.timezone;

  return jsonb_build_object('ok', true, 'scope', pro, 'today', to_char(today, 'YYYY-MM-DD'),
    'today_items', (select coalesce(jsonb_agg(app.booking_json(k) order by k.starts_at), '[]'::jsonb)
                    from app.bookings k where k.salon_id = s.id and (pro is null or k.professional_id = pro)
                      and k.starts_at >= t0 and k.starts_at < t1
                      and k.status in ('pending','confirmed','completed','no_show')),
    'needs_confirming', (select coalesce(jsonb_agg(x.j order by x.st), '[]'::jsonb) from (
                           select app.booking_json(k) j, k.starts_at st from app.bookings k
                           where k.salon_id = s.id and (pro is null or k.professional_id = pro)
                             and k.status = 'pending' and k.starts_at > now()
                           order by k.starts_at limit 25) x),
    'counts', (select jsonb_build_object(
        'pending', count(*) filter (where k.status = 'pending' and k.starts_at > now()),
        'upcoming_7d', count(*) filter (where k.status in ('pending','confirmed') and k.starts_at > now()
                                          and k.starts_at < now() + interval '7 days'),
        'awaiting_outcome', count(*) filter (where k.status = 'confirmed' and k.ends_at < now()),
        'completed_30d', count(*) filter (where k.status = 'completed' and k.starts_at >= now() - interval '30 days' and k.starts_at < now()),
        'cancelled_30d', count(*) filter (where k.status = 'cancelled' and k.cancelled_at >= now() - interval '30 days'),
        'declined_30d', count(*) filter (where k.status = 'declined' and k.updated_at >= now() - interval '30 days'),
        'no_show_30d', count(*) filter (where k.status = 'no_show' and k.starts_at >= now() - interval '30 days'),
        'completed_value_30d_pence', coalesce(sum(k.price_pence) filter (where k.status = 'completed'
                                       and k.price_kind <> 'enquire' and k.starts_at >= now() - interval '30 days' and k.starts_at < now()), 0),
        'scheduled_value_30d_pence', coalesce(sum(k.price_pence) filter (where k.status in ('pending','confirmed')
                                       and k.price_kind <> 'enquire' and k.starts_at > now() and k.starts_at < now() + interval '30 days'), 0))
      from app.bookings k where k.salon_id = s.id and (pro is null or k.professional_id = pro)),
    'new_enquiries', (select count(*) from app.enquiries e where e.salon_id = s.id and e.status = 'new'
                        and (case when m.role = 'owner' then (pro is null or e.professional_id = pro)
                                  else e.professional_id = m.professional_id end)),
    'by_professional', case when m.role = 'owner' and pro is null then (
        select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name, 'short_name', p.short_name,
                 'color', p.color,
                 'today', (select count(*) from app.bookings k where k.professional_id = p.id and k.starts_at >= t0 and k.starts_at < t1
                             and k.status in ('pending','confirmed','completed','no_show')),
                 'pending', (select count(*) from app.bookings k where k.professional_id = p.id and k.status = 'pending' and k.starts_at > now()),
                 'upcoming_7d', (select count(*) from app.bookings k where k.professional_id = p.id and k.status in ('pending','confirmed')
                                   and k.starts_at > now() and k.starts_at < now() + interval '7 days'))
               order by p.sort_order), '[]'::jsonb)
        from app.professionals p where p.salon_id = s.id and p.active) else null end);
end $$;

-- ---------------------------------------------------------------------
create or replace function public.salon_dash_bookings(p_salon uuid, p_professional uuid default null,
                                                      p_from timestamptz default null, p_to timestamptz default null,
                                                      p_statuses text[] default null, p_search text default null,
                                                      p_limit int default 500)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; q text := lower(btrim(coalesce(p_search, ''))); qd text;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  perform app.expire_stale(p_salon);
  qd := regexp_replace(q, '[^0-9]', '', 'g');
  return jsonb_build_object('ok', true, 'items', (
    select coalesce(jsonb_agg(x.j order by x.st), '[]'::jsonb) from (
      select app.booking_json(k) j, k.starts_at st
      from app.bookings k join app.clients c on c.id = k.client_id
      where k.salon_id = p_salon and (pro is null or k.professional_id = pro)
        and (p_from is null or k.starts_at >= p_from)
        and (p_to is null or k.starts_at < p_to)
        and (p_statuses is null or k.status = any (p_statuses))
        and (q = '' or lower(k.ref) = q or lower(c.name) like '%' || q || '%'
             or lower(k.service_name) like '%' || q || '%'
             or (length(qd) >= 4 and regexp_replace(c.phone, '[^0-9]', '', 'g') like '%' || qd || '%'))
      order by k.starts_at
      limit least(greatest(coalesce(p_limit, 500), 1), 2000)) x));
end $$;

create or replace function public.salon_dash_booking(p_booking uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare k app.bookings;
begin
  k := app.booking_for_caller(p_booking, false);
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k),
    'client_visits', (select count(*) from app.bookings x where x.client_id = k.client_id and x.status = 'completed'),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', a.created_at, 'action', a.action,
                  'actor', a.actor_label, 'detail', a.detail) order by a.created_at), '[]'::jsonb)
                from app.audit_log a where a.entity = 'booking' and a.entity_id = k.id::text),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('at', n.created_at, 'purpose', n.purpose,
                  'audience', n.audience, 'status', n.status, 'body', n.body) order by n.created_at), '[]'::jsonb)
                 from app.notifications n where n.booking_id = k.id));
end $$;

-- ---------------------------------------------------------------------
-- Status transitions
--   pending   -> confirmed | declined | cancelled
--   confirmed -> cancelled | completed | no_show (completed/no_show only once it has started)
--   completed <-> no_show (correction)
create or replace function public.salon_dash_booking_action(p_booking uuid, p_action text,
                                                            p_reason text default null, p_version int default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k app.bookings; m app.memberships; old text; new_status text; act text := lower(coalesce(p_action, ''));
begin
  k := app.booking_for_caller(p_booking, true);
  m := app.my_membership(k.salon_id);
  if p_version is not null and p_version <> k.version then
    perform app.fail('stale', 'This booking was changed by someone else. Please refresh.');
  end if;
  old := k.status;
  new_status := case
    when act = 'confirm'  and old = 'pending' then 'confirmed'
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
         completed_at = case when new_status = 'completed' then now() else completed_at end
   where id = k.id returning * into k;

  if new_status in ('confirmed','declined','cancelled') then
    perform app.notify_booking(k, new_status, 'customer');
  end if;
  perform app.audit(k.salon_id, k.professional_id, auth.uid(), app.actor_label(m), 'booking.' || new_status, 'booking',
                    k.id::text, jsonb_build_object('ref', k.ref, 'from', old, 'to', new_status, 'reason', app.clean_text(p_reason, 300)));
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k));
end $$;

-- ---------------------------------------------------------------------
-- Reschedule and (owner only) reassign to another professional.
create or replace function public.salon_dash_booking_reschedule(p_booking uuid, p_date text, p_time text,
                                                                p_professional uuid default null, p_service uuid default null,
                                                                p_allow_outside_hours boolean default false,
                                                                p_version int default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k app.bookings; old app.bookings; m app.memberships; s app.salons; v app.services; c app.clients; oc app.clients;
        target_pro uuid; target_svc uuid; d date; t time; st timestamptz; problem text; same_service boolean;
begin
  k := app.booking_for_caller(p_booking, true);
  old := k;
  m := app.my_membership(k.salon_id);
  select * into s from app.salons where id = k.salon_id;
  if p_version is not null and p_version <> k.version then
    perform app.fail('stale', 'This booking was changed by someone else. Please refresh.');
  end if;
  if k.status not in ('pending','confirmed') then
    perform app.fail('not_active', 'Only pending or confirmed bookings can be moved.');
  end if;

  target_pro := coalesce(p_professional, k.professional_id);
  if target_pro <> k.professional_id then
    if m.role <> 'owner' then
      perform app.fail('forbidden', 'Only the owner can move a booking to another professional.');
    end if;
    if not exists (select 1 from app.professionals where id = target_pro and salon_id = s.id and active) then
      perform app.fail('forbidden', 'That profile is not part of this salon.');
    end if;
    if p_service is null then
      perform app.fail('service_required', 'Choose the service for the new professional.');
    end if;
  end if;
  target_svc := coalesce(p_service, k.service_id);
  select * into v from app.services where id = target_svc and professional_id = target_pro;
  if v.id is null or (not v.active and v.id <> k.service_id) then
    perform app.fail('service_not_found', 'That service is not offered by this professional.');
  end if;
  same_service := v.id = k.service_id;
  if same_service then           -- keep the booked snapshot, not the current catalogue
    v.duration_min := k.duration_min; v.buffer_min := k.buffer_min; v.name := k.service_name;
    v.price_pence := k.price_pence; v.price_kind := k.price_kind;
  end if;

  d := app.parse_date_strict(p_date);
  t := app.parse_time(p_time);
  if t is null then perform app.fail('time_required', 'Choose a time.'); end if;
  st := (d + t) at time zone s.timezone;
  perform app.lock_pro(target_pro);
  problem := app.slot_problem(s, v, st, k.id, not coalesce(p_allow_outside_hours, false), false);
  if problem is not null then
    perform app.fail(case when problem = 'taken' then 'slot_taken' else 'slot_unavailable' end, app.problem_message(problem));
  end if;

  c := null;
  if target_pro <> k.professional_id then
    select * into oc from app.clients where id = k.client_id;
    -- copy contact details only; the original professional's notes stay private to them
    c := app.upsert_client(s.id, target_pro, oc.phone, oc.name, oc.email, oc.marketing_consent, true);
  end if;

  begin
    update app.bookings
       set professional_id = target_pro, service_id = v.id, client_id = coalesce(c.id, client_id),
           starts_at = st, ends_at = st + make_interval(mins => v.duration_min),
           block_end = st + make_interval(mins => v.duration_min + v.buffer_min),
           service_name = v.name, duration_min = v.duration_min, buffer_min = v.buffer_min,
           price_pence = v.price_pence, price_kind = v.price_kind,
           manage_token_expires_at = case when manage_token_hash is not null
                                          then st + make_interval(mins => v.duration_min) + interval '1 day' end,
           version = version + 1, updated_at = now()
     where id = k.id returning * into k;
  exception when exclusion_violation or deadlock_detected then
    perform app.fail('slot_taken', app.problem_message('taken'));
  end;

  perform app.notify_booking(k, 'rescheduled', 'customer');
  perform app.audit(k.salon_id, k.professional_id, auth.uid(), app.actor_label(m),
                    case when old.professional_id <> k.professional_id then 'booking.reassigned' else 'booking.rescheduled' end,
                    'booking', k.id::text, jsonb_build_object('ref', k.ref,
                      'from', app.fmt_when(old.starts_at, s.timezone), 'to', app.fmt_when(k.starts_at, s.timezone),
                      'from_professional', old.professional_id, 'to_professional', k.professional_id,
                      'outside_hours', coalesce(p_allow_outside_hours, false)));
  if old.professional_id <> k.professional_id then
    perform app.audit(k.salon_id, old.professional_id, auth.uid(), app.actor_label(m), 'booking.reassigned_away',
                      'booking', k.id::text, jsonb_build_object('ref', k.ref));
  end if;
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k));
end $$;

create or replace function public.salon_dash_booking_note(p_booking uuid, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k app.bookings; m app.memberships;
begin
  k := app.booking_for_caller(p_booking, true);
  m := app.my_membership(k.salon_id);
  update app.bookings set internal_note = app.clean_text(p_note, 2000), updated_at = now()
   where id = k.id returning * into k;
  perform app.audit(k.salon_id, k.professional_id, auth.uid(), app.actor_label(m), 'booking.note', 'booking', k.id::text,
                    jsonb_build_object('ref', k.ref));
  return jsonb_build_object('ok', true, 'booking', app.booking_json(k));
end $$;

-- ---------------------------------------------------------------------
-- Manual booking from the dashboard (phone/walk-in/DM). Overlaps are always refused;
-- hours may be overridden explicitly.
create or replace function public.salon_dash_booking_create(p_salon uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  m app.memberships; s app.salons; pro uuid; v app.services; c app.clients; k app.bookings;
  a jsonb := coalesce(p_payload, '{}'::jsonb); d date; t time; st timestamptz; problem text;
  v_phone text; v_name text; v_status text; v_source text; v_idem text; v_key text; prior app.idempotency; res jsonb;
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
  d := app.parse_date_strict(a->>'date');
  t := app.parse_time(a->>'time');
  if t is null then perform app.fail('time_required', 'Choose a time.'); end if;
  st := (d + t) at time zone s.timezone;
  perform app.lock_pro(pro);
  problem := app.slot_problem(s, v, st, null, not coalesce((a->>'allow_outside_hours')::boolean, false), false);
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
                          app.clean_text(a->>'internal_note', 2000), auth.uid());
  if v_status = 'confirmed' then perform app.notify_booking(k, 'confirmed', 'customer'); end if;
  perform app.audit(s.id, pro, auth.uid(), app.actor_label(m), 'booking.created', 'booking', k.id::text,
                    jsonb_build_object('ref', k.ref, 'status', v_status, 'source', v_source,
                                       'outside_hours', coalesce((a->>'allow_outside_hours')::boolean, false)));
  res := jsonb_build_object('ok', true, 'booking', app.booking_json(k));
  if v_key is not null then update app.idempotency set result = res where salon_id = s.id and key = v_key; end if;
  return res;
end $$;

create or replace function public.salon_dash_slots(p_salon uuid, p_professional uuid, p_service uuid, p_date text,
                                                   p_exclude_booking uuid default null)
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
    if ex.service_id = v.id then v.duration_min := ex.duration_min; v.buffer_min := ex.buffer_min; end if;
  end if;
  d := app.parse_date_strict(p_date);
  return jsonb_build_object('ok', true, 'date', to_char(d, 'YYYY-MM-DD'), 'slots', (
    select coalesce(jsonb_agg(jsonb_build_object('time', to_char(f at time zone s.timezone, 'HH24:MI'),
             'label', lower(to_char(f at time zone s.timezone, 'FMHH12:MIam'))) order by f), '[]'::jsonb)
    from app.free_starts(s, v, d, p_exclude_booking, false) f));
end $$;

-- ---------------------------------------------------------------------
-- Clients (records are per professional)
create or replace function public.salon_dash_clients(p_salon uuid, p_professional uuid default null,
                                                     p_search text default null, p_limit int default 300)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; pro uuid; q text := lower(btrim(coalesce(p_search, ''))); qd text;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  qd := regexp_replace(q, '[^0-9]', '', 'g');
  return jsonb_build_object('ok', true, 'items', (
    select coalesce(jsonb_agg(x.j order by x.n), '[]'::jsonb) from (
      select jsonb_build_object('id', c.id, 'name', c.name, 'phone', c.phone, 'email', c.email,
               'professional_id', c.professional_id, 'professional', p.display_name, 'professional_color', p.color,
               'marketing_consent', c.marketing_consent, 'created_at', c.created_at,
               'completed', (select count(*) from app.bookings k where k.client_id = c.id and k.status = 'completed'),
               'upcoming', (select count(*) from app.bookings k where k.client_id = c.id and k.status in ('pending','confirmed') and k.starts_at > now()),
               'last_visit', (select max(k.starts_at) from app.bookings k where k.client_id = c.id and k.status = 'completed')) j,
             lower(c.name) n
      from app.clients c join app.professionals p on p.id = c.professional_id
      where c.salon_id = p_salon and (pro is null or c.professional_id = pro)
        and (q = '' or lower(c.name) like '%' || q || '%' or lower(coalesce(c.email, '')) like '%' || q || '%'
             or (length(qd) >= 4 and regexp_replace(c.phone, '[^0-9]', '', 'g') like '%' || qd || '%'))
      order by lower(c.name)
      limit least(greatest(coalesce(p_limit, 300), 1), 1000)) x));
end $$;

create or replace function app.client_for_caller(p_client uuid, p_lock boolean)
returns app.clients language plpgsql set search_path = '' as $$
declare c app.clients; m app.memberships; uid uuid := auth.uid();
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  if p_lock then select * into c from app.clients where id = p_client for update;
  else select * into c from app.clients where id = p_client; end if;
  if c.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = c.salon_id and status = 'active';
  end if;
  if c.id is null or m.id is null or not app.can_see(m, c.professional_id) then
    perform app.fail('not_found', 'Client not found.');
  end if;
  return c;
end $$;

create or replace function public.salon_dash_client(p_client uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c app.clients; p app.professionals;
begin
  c := app.client_for_caller(p_client, false);
  select * into p from app.professionals where id = c.professional_id;
  return jsonb_build_object('ok', true,
    'client', jsonb_build_object('id', c.id, 'name', c.name, 'phone', c.phone, 'email', c.email, 'notes', c.notes,
                                 'marketing_consent', c.marketing_consent, 'marketing_consent_at', c.marketing_consent_at,
                                 'professional_id', c.professional_id, 'professional', p.display_name, 'created_at', c.created_at),
    'bookings', (select coalesce(jsonb_agg(app.booking_json(k) order by k.starts_at desc), '[]'::jsonb)
                 from app.bookings k where k.client_id = c.id));
end $$;

create or replace function public.salon_dash_client_save(p_client uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare c app.clients; m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); v_name text; v_email text;
begin
  c := app.client_for_caller(p_client, true);
  m := app.my_membership(c.salon_id);
  v_name := coalesce(app.clean_text(a->>'name', 80), c.name);
  if length(v_name) < 2 then perform app.fail('name_required', 'Enter a name.'); end if;
  v_email := case when a ? 'email' then lower(app.clean_text(a->>'email', 254)) else c.email end;
  if v_email is not null and not app.valid_email(v_email) then perform app.fail('email_invalid', 'Check the email address.'); end if;
  update app.clients set name = v_name, email = v_email,
         notes = case when a ? 'notes' then app.clean_text(a->>'notes', 4000) else notes end,
         marketing_consent = case when a ? 'marketing_consent' then coalesce((a->>'marketing_consent')::boolean, false) else marketing_consent end,
         marketing_consent_at = case when a ? 'marketing_consent' and coalesce((a->>'marketing_consent')::boolean, false) and not marketing_consent then now()
                                     when a ? 'marketing_consent' and not coalesce((a->>'marketing_consent')::boolean, false) then null
                                     else marketing_consent_at end,
         updated_at = now()
   where id = c.id returning * into c;
  perform app.audit(c.salon_id, c.professional_id, auth.uid(), app.actor_label(m), 'client.updated', 'client', c.id::text);
  return public.salon_dash_client(c.id);
end $$;

-- ---------------------------------------------------------------------
-- Enquiries
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
             'professional_id', e.professional_id, 'professional', p.display_name, 'professional_color', p.color)
             order by e.created_at desc), '[]'::jsonb)
    from app.enquiries e left join app.professionals p on p.id = e.professional_id
    where e.salon_id = p_salon
      and (case when m.role = 'owner' then (pro is null or e.professional_id = pro)
                else e.professional_id = m.professional_id end)
      and (p_status is null or e.status = p_status)));
end $$;

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
  else
    new_pro := e.professional_id;
  end if;
  if a ? 'status' and a->>'status' not in ('new','contacted','booked','closed') then
    perform app.fail('invalid_status', 'Unknown status.');
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
-- Services
create or replace function public.salon_dash_services(p_salon uuid, p_professional uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; pro uuid;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  return jsonb_build_object('ok', true, 'can_edit_all', m.role = 'owner', 'items', (
    select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'professional_id', v.professional_id,
             'professional', p.display_name, 'professional_color', p.color,
             'name', v.name, 'description', v.description, 'category', v.category,
             'duration_min', v.duration_min, 'buffer_min', v.buffer_min, 'price_pence', v.price_pence,
             'price_kind', v.price_kind, 'price_label', app.fmt_price(v.price_pence, v.price_kind),
             'bookable_online', v.bookable_online, 'details_confirmed', v.details_confirmed,
             'active', v.active, 'sort_order', v.sort_order)
             order by p.sort_order, v.sort_order, v.name), '[]'::jsonb)
    from app.services v join app.professionals p on p.id = v.professional_id
    where v.salon_id = p_salon and (pro is null or v.professional_id = pro)));
end $$;

create or replace function public.salon_dash_service_save(p_salon uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); v app.services; before jsonb; pro uuid;
        v_kind text; v_price int;
begin
  m := app.my_membership(p_salon);
  if coalesce(a->>'id', '') = '' then
    if m.role <> 'owner' then perform app.fail('forbidden', 'Only the owner can add services.'); end if;
    pro := app.scope_pro(m, nullif(a->>'professional_id', '')::uuid);
    if pro is null then perform app.fail('professional_required', 'Choose a professional.'); end if;
    v_kind := coalesce(a->>'price_kind', 'fixed');
    v_price := nullif(a->>'price_pence', '')::int;
    if app.clean_text(a->>'name', 80) is null or length(app.clean_text(a->>'name', 80)) < 2 then
      perform app.fail('name_required', 'Enter a service name.');
    end if;
    if v_kind not in ('fixed','from','enquire') then perform app.fail('invalid_price', 'Unknown price type.'); end if;
    if v_kind <> 'enquire' and (v_price is null or v_price < 0) then
      perform app.fail('price_required', 'Enter a price, or choose "Please enquire".');
    end if;
    if coalesce((a->>'duration_min')::int, 60) not between 5 and 720 or coalesce((a->>'buffer_min')::int, 0) not between 0 and 240 then
      perform app.fail('invalid_duration', 'Duration must be 5–720 minutes and buffer 0–240 minutes.');
    end if;
    if exists (select 1 from app.services x where x.professional_id = pro and lower(x.name) = lower(app.clean_text(a->>'name', 80))) then
      perform app.fail('duplicate_name', 'This professional already has a service with that name.');
    end if;
    insert into app.services (salon_id, professional_id, name, description, category, duration_min, buffer_min,
                              price_pence, price_kind, bookable_online, details_confirmed, active, sort_order)
    values (p_salon, pro, app.clean_text(a->>'name', 80), app.clean_text(a->>'description', 500),
            coalesce(a->>'category', 'other'), coalesce((a->>'duration_min')::int, 60), coalesce((a->>'buffer_min')::int, 0),
            case when v_kind = 'enquire' then null else v_price end, v_kind,
            case when v_kind = 'enquire' then false else coalesce((a->>'bookable_online')::boolean, true) end,
            coalesce((a->>'details_confirmed')::boolean, false), coalesce((a->>'active')::boolean, true),
            coalesce((a->>'sort_order')::int, 0))
    returning * into v;
    perform app.audit(p_salon, pro, auth.uid(), 'owner', 'service.created', 'service', v.id::text, to_jsonb(v));
    return jsonb_build_object('ok', true, 'id', v.id);
  end if;

  select * into v from app.services where id = (a->>'id')::uuid and salon_id = p_salon for update;
  if v.id is null or not app.can_see(m, v.professional_id) then perform app.fail('not_found', 'Service not found.'); end if;
  before := to_jsonb(v);
  if a ? 'professional_id' and nullif(a->>'professional_id', '')::uuid is distinct from v.professional_id then
    perform app.fail('forbidden', 'A service cannot be moved to another professional. Add a new one instead.');
  end if;

  -- fields every profile may manage for its own services
  if a ? 'description' then v.description := app.clean_text(a->>'description', 500); end if;
  if a ? 'duration_min' then v.duration_min := (a->>'duration_min')::int; end if;
  if a ? 'buffer_min' then v.buffer_min := (a->>'buffer_min')::int; end if;
  if a ? 'active' then v.active := (a->>'active')::boolean; end if;
  if a ? 'bookable_online' then v.bookable_online := (a->>'bookable_online')::boolean; end if;

  -- owner-only fields
  if m.role = 'owner' then
    if a ? 'name' then v.name := app.clean_text(a->>'name', 80); end if;
    if a ? 'category' then v.category := a->>'category'; end if;
    if a ? 'price_kind' then v.price_kind := a->>'price_kind'; end if;
    if a ? 'price_pence' then v.price_pence := nullif(a->>'price_pence', '')::int; end if;
    if a ? 'details_confirmed' then v.details_confirmed := (a->>'details_confirmed')::boolean; end if;
    if a ? 'sort_order' then v.sort_order := (a->>'sort_order')::int; end if;
  elsif a ?| array['name','category','price_kind','price_pence','details_confirmed','sort_order'] then
    perform app.fail('forbidden', 'Only the owner can change the name, price or confirmation of a service.');
  end if;
  if v.price_kind = 'enquire' then v.price_pence := null; v.bookable_online := false; end if;
  if v.price_kind not in ('fixed','from','enquire') then perform app.fail('invalid_price', 'Unknown price type.'); end if;
  if v.price_kind <> 'enquire' and (v.price_pence is null or v.price_pence < 0) then
    perform app.fail('price_required', 'Enter a price, or choose "Please enquire".');
  end if;
  if v.duration_min is null or v.duration_min not between 5 and 720 or v.buffer_min is null or v.buffer_min not between 0 and 240 then
    perform app.fail('invalid_duration', 'Duration must be 5–720 minutes and buffer 0–240 minutes.');
  end if;
  if v.name is null or length(v.name) < 2 then perform app.fail('name_required', 'Enter a service name.'); end if;
  if v.category not in ('hair','makeup','hair_makeup','hijab','saree','bridal','other') then
    perform app.fail('invalid_category', 'Unknown category.');
  end if;

  update app.services set name = v.name, description = v.description, category = v.category,
         duration_min = v.duration_min, buffer_min = v.buffer_min, price_pence = v.price_pence,
         price_kind = v.price_kind, bookable_online = v.bookable_online, details_confirmed = v.details_confirmed,
         active = v.active, sort_order = v.sort_order, updated_at = now()
   where id = v.id returning * into v;
  perform app.audit(p_salon, v.professional_id, auth.uid(), app.actor_label(m), 'service.updated', 'service', v.id::text,
                    jsonb_build_object('before', before, 'after', to_jsonb(v)));
  return jsonb_build_object('ok', true, 'id', v.id);
end $$;

-- ---------------------------------------------------------------------
-- Schedule: salon hours, professional working hours, time off
create or replace function public.salon_dash_schedule(p_salon uuid, p_professional uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; pro uuid; s app.salons;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  select * into s from app.salons where id = p_salon;
  return jsonb_build_object('ok', true, 'hours_confirmed', s.hours_confirmed,
    'salon_hours', (select coalesce(jsonb_agg(jsonb_build_object('weekday', h.weekday,
                      'opens', to_char(h.opens, 'HH24:MI'), 'closes', to_char(h.closes, 'HH24:MI'))
                      order by h.weekday, h.opens), '[]'::jsonb) from app.opening_hours h where h.salon_id = p_salon),
    'salon_time_off', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'starts_at', t.starts_at, 'ends_at', t.ends_at,
                         'reason', t.reason) order by t.starts_at), '[]'::jsonb)
                       from app.time_off t where t.salon_id = p_salon and t.professional_id is null and t.ends_at > now()),
    'professionals', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name, 'color', p.color,
        'working_hours', (select coalesce(jsonb_agg(jsonb_build_object('weekday', w.weekday,
                            'opens', to_char(w.opens, 'HH24:MI'), 'closes', to_char(w.closes, 'HH24:MI'))
                            order by w.weekday, w.opens), '[]'::jsonb) from app.working_hours w where w.professional_id = p.id),
        'time_off', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'starts_at', t.starts_at, 'ends_at', t.ends_at,
                       'reason', t.reason) order by t.starts_at), '[]'::jsonb)
                     from app.time_off t where t.professional_id = p.id and t.ends_at > now()))
        order by p.sort_order), '[]'::jsonb)
      from app.professionals p where p.salon_id = p_salon and p.active and (pro is null or p.id = pro)));
end $$;

create or replace function app.validate_hours(p_rows jsonb)
returns table (weekday smallint, opens time, closes time) language plpgsql immutable set search_path = '' as $$
declare r jsonb; w smallint; o time; c time; seen jsonb := '[]'::jsonb; x jsonb;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then perform app.fail('invalid_hours', 'Hours must be a list.'); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    w := (r->>'weekday')::smallint; o := app.parse_time(r->>'opens'); c := app.parse_time(r->>'closes');
    if w is null or w < 0 or w > 6 or o is null or c is null or c <= o then
      perform app.fail('invalid_hours', 'Each day needs a start time before its end time.');
    end if;
    for x in select * from jsonb_array_elements(seen) loop
      if (x->>'w')::smallint = w and o < (x->>'c')::time and (x->>'o')::time < c then
        perform app.fail('invalid_hours', 'Two time ranges overlap on the same day.');
      end if;
    end loop;
    seen := seen || jsonb_build_array(jsonb_build_object('w', w, 'o', o, 'c', c));
    weekday := w; opens := o; closes := c; return next;
  end loop;
end $$;

create or replace function public.salon_dash_hours_save(p_salon uuid, p_professional uuid, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; before jsonb; n int;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  if pro is null then perform app.fail('professional_required', 'Choose a professional.'); end if;
  select coalesce(jsonb_agg(to_jsonb(w)), '[]'::jsonb) into before from app.working_hours w where w.professional_id = pro;
  delete from app.working_hours where professional_id = pro;
  insert into app.working_hours (professional_id, weekday, opens, closes)
  select pro, h.weekday, h.opens, h.closes from app.validate_hours(p_rows) h;
  -- upcoming bookings that now fall outside the new hours are kept, but reported
  select count(*) into n from app.bookings k where k.professional_id = pro and k.status in ('pending','confirmed')
    and k.starts_at > now() and not exists (select 1 from app.working_hours w where w.professional_id = pro
      and w.weekday = extract(dow from (k.starts_at at time zone (select timezone from app.salons where id = p_salon)))
      and (k.starts_at at time zone (select timezone from app.salons where id = p_salon))::time >= w.opens
      and (k.ends_at at time zone (select timezone from app.salons where id = p_salon))::time <= w.closes);
  perform app.audit(p_salon, pro, auth.uid(), app.actor_label(m), 'hours.updated', 'professional', pro::text,
                    jsonb_build_object('before', before, 'after', p_rows));
  return jsonb_build_object('ok', true, 'bookings_outside_hours', n);
end $$;

create or replace function public.salon_dash_time_off_add(p_salon uuid, p_professional uuid, p_starts timestamptz,
                                                          p_ends timestamptz, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; t app.time_off; n int;
begin
  m := app.my_membership(p_salon);
  if p_professional is null then
    if m.role <> 'owner' then perform app.fail('forbidden', 'Only the owner can close the whole salon.'); end if;
    pro := null;
  else
    pro := app.scope_pro(m, p_professional);
  end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then
    perform app.fail('invalid_range', 'The end must be after the start.');
  end if;
  if p_ends - p_starts > interval '120 days' then perform app.fail('invalid_range', 'Time off is limited to 120 days at a time.'); end if;
  insert into app.time_off (salon_id, professional_id, starts_at, ends_at, reason, created_by)
  values (p_salon, pro, p_starts, p_ends, app.clean_text(p_reason, 200), auth.uid()) returning * into t;
  select count(*) into n from app.bookings k where k.salon_id = p_salon and (pro is null or k.professional_id = pro)
    and k.status in ('pending','confirmed') and tstzrange(k.starts_at, k.block_end, '[)') && tstzrange(t.starts_at, t.ends_at, '[)');
  perform app.audit(p_salon, pro, auth.uid(), app.actor_label(m), 'time_off.added', 'time_off', t.id::text,
                    jsonb_build_object('starts_at', t.starts_at, 'ends_at', t.ends_at));
  return jsonb_build_object('ok', true, 'id', t.id, 'overlapping_bookings', n);
end $$;

create or replace function public.salon_dash_time_off_delete(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t app.time_off; m app.memberships; uid uuid := auth.uid();
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  select * into t from app.time_off where id = p_id;
  if t.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = t.salon_id and status = 'active';
  end if;
  if t.id is null or m.id is null or not (m.role = 'owner' or (t.professional_id is not null and t.professional_id = m.professional_id)) then
    perform app.fail('not_found', 'Not found.');
  end if;
  delete from app.time_off where id = t.id;
  perform app.audit(t.salon_id, t.professional_id, uid, app.actor_label(m), 'time_off.removed', 'time_off', t.id::text,
                    jsonb_build_object('starts_at', t.starts_at, 'ends_at', t.ends_at));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- Messages (outbox) and reports
create or replace function public.salon_dash_messages(p_salon uuid, p_professional uuid default null, p_limit int default 150)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; pro uuid; s app.salons;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  select * into s from app.salons where id = p_salon;
  return jsonb_build_object('ok', true, 'sms_connected', s.sms_connected, 'items', (
    select coalesce(jsonb_agg(x.j order by x.at desc), '[]'::jsonb) from (
      select jsonb_build_object('id', n.id, 'at', n.created_at, 'purpose', n.purpose, 'audience', n.audience,
               'channel', n.channel, 'to', n.to_addr, 'body', n.body, 'status', n.status,
               'professional_id', n.professional_id, 'professional', p.display_name, 'professional_color', p.color,
               'booking_ref', k.ref, 'booking_id', k.id) j, n.created_at at
      from app.notifications n
      left join app.professionals p on p.id = n.professional_id
      left join app.bookings k on k.id = n.booking_id
      where n.salon_id = p_salon
        and (case when m.role = 'owner' then (pro is null or n.professional_id = pro)
                  else n.professional_id = m.professional_id end)
      order by n.created_at desc
      limit least(greatest(coalesce(p_limit, 150), 1), 500)) x));
end $$;

create or replace function public.salon_dash_report(p_salon uuid, p_professional uuid default null,
                                                    p_from text default null, p_to text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; s app.salons; d0 date; d1 date; t0 timestamptz; t1 timestamptz; rows jsonb;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  select * into s from app.salons where id = p_salon;
  perform app.expire_stale(p_salon);
  d0 := coalesce(nullif(p_from, '')::date, (now() at time zone s.timezone)::date - 29);
  d1 := coalesce(nullif(p_to, '')::date, (now() at time zone s.timezone)::date);
  if d1 < d0 then perform app.fail('invalid_range', 'The end date must be after the start date.'); end if;
  if d1 - d0 > 366 then perform app.fail('invalid_range', 'Reports are limited to one year.'); end if;
  t0 := d0::timestamp at time zone s.timezone;
  t1 := (d1 + 1)::timestamp at time zone s.timezone;
  select coalesce(jsonb_agg(r order by r->>'sort'), '[]'::jsonb) into rows from (
    select jsonb_build_object('professional_id', p.id, 'professional', p.display_name, 'color', p.color,
             'sort', lpad(p.sort_order::text, 4, '0'),
             'total', count(k.id),
             'pending', count(k.id) filter (where k.status = 'pending'),
             'confirmed', count(k.id) filter (where k.status = 'confirmed'),
             'completed', count(k.id) filter (where k.status = 'completed'),
             'cancelled', count(k.id) filter (where k.status = 'cancelled'),
             'declined', count(k.id) filter (where k.status = 'declined'),
             'no_show', count(k.id) filter (where k.status = 'no_show'),
             'expired', count(k.id) filter (where k.status = 'expired'),
             'completed_value_pence', coalesce(sum(k.price_pence) filter (where k.status = 'completed' and k.price_kind <> 'enquire'), 0),
             'booked_value_pence', coalesce(sum(k.price_pence) filter (where k.status in ('confirmed','completed') and k.price_kind <> 'enquire'), 0),
             'website', count(k.id) filter (where k.source = 'website'),
             'dashboard', count(k.id) filter (where k.source <> 'website')) r
    from app.professionals p
    left join app.bookings k on k.professional_id = p.id and k.starts_at >= t0 and k.starts_at < t1
    where p.salon_id = p_salon and (pro is null or p.id = pro)
    group by p.id) x;
  return jsonb_build_object('ok', true, 'from', to_char(d0, 'YYYY-MM-DD'), 'to', to_char(d1, 'YYYY-MM-DD'), 'rows', rows,
    'totals', (select jsonb_object_agg(key, total) from (
       select key, sum((r->>key)::bigint) total from jsonb_array_elements(rows) r,
         unnest(array['total','pending','confirmed','completed','cancelled','declined','no_show','expired',
                      'completed_value_pence','booked_value_pence','website','dashboard']) key
       group by key) t));
end $$;

-- ---------------------------------------------------------------------
-- Gallery (portfolio). Files live in the public storage bucket 'portfolio'
-- under <salon_id>/<professional_id>/...; storage policies enforce the folder.
create or replace function public.salon_dash_gallery(p_salon uuid, p_professional uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; pro uuid;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  return jsonb_build_object('ok', true, 'items', (
    select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'professional_id', g.professional_id,
             'professional', p.display_name, 'storage_path', g.storage_path, 'media_type', g.media_type,
             'alt_text', g.alt_text, 'caption', g.caption, 'published', g.published, 'sort_order', g.sort_order,
             'created_at', g.created_at) order by p.sort_order, g.sort_order, g.created_at desc), '[]'::jsonb)
    from app.gallery_items g join app.professionals p on p.id = g.professional_id
    where g.salon_id = p_salon and (pro is null or g.professional_id = pro)));
end $$;

create or replace function public.salon_dash_gallery_add(p_salon uuid, p_professional uuid, p_path text,
                                                         p_media_type text default 'image', p_alt text default '',
                                                         p_caption text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; g app.gallery_items;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  if pro is null then perform app.fail('professional_required', 'Choose a professional.'); end if;
  if p_path is null or p_path !~ ('^' || p_salon::text || '/' || pro::text || '/[A-Za-z0-9._-]{1,120}$') then
    perform app.fail('invalid_path', 'Upload the file into this profile''s folder.');
  end if;
  insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text, caption, created_by)
  values (p_salon, pro, p_path, case when p_media_type = 'video' then 'video' else 'image' end,
          coalesce(app.clean_text(p_alt, 200), ''), app.clean_text(p_caption, 200), auth.uid())
  returning * into g;
  perform app.audit(p_salon, pro, auth.uid(), app.actor_label(m), 'gallery.added', 'gallery', g.id::text);
  return jsonb_build_object('ok', true, 'id', g.id);
end $$;

create or replace function app.gallery_for_caller(p_item uuid)
returns app.gallery_items language plpgsql set search_path = '' as $$
declare g app.gallery_items; m app.memberships; uid uuid := auth.uid();
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  select * into g from app.gallery_items where id = p_item for update;
  if g.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = g.salon_id and status = 'active';
  end if;
  if g.id is null or m.id is null or not app.can_see(m, g.professional_id) then perform app.fail('not_found', 'Not found.'); end if;
  return g;
end $$;

create or replace function public.salon_dash_gallery_update(p_item uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare g app.gallery_items; a jsonb := coalesce(p_payload, '{}'::jsonb); m app.memberships;
begin
  g := app.gallery_for_caller(p_item);
  m := app.my_membership(g.salon_id);
  update app.gallery_items set
    alt_text = case when a ? 'alt_text' then coalesce(app.clean_text(a->>'alt_text', 200), '') else alt_text end,
    caption = case when a ? 'caption' then app.clean_text(a->>'caption', 200) else caption end,
    published = case when a ? 'published' then (a->>'published')::boolean else published end,
    sort_order = case when a ? 'sort_order' then (a->>'sort_order')::int else sort_order end
  where id = g.id;
  perform app.audit(g.salon_id, g.professional_id, auth.uid(), app.actor_label(m), 'gallery.updated', 'gallery', g.id::text, a);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.salon_dash_gallery_delete(p_item uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare g app.gallery_items; m app.memberships;
begin
  g := app.gallery_for_caller(p_item);
  m := app.my_membership(g.salon_id);
  delete from app.gallery_items where id = g.id;
  perform app.audit(g.salon_id, g.professional_id, auth.uid(), app.actor_label(m), 'gallery.removed', 'gallery', g.id::text);
  return jsonb_build_object('ok', true, 'storage_path', g.storage_path);
end $$;
