-- Everyone on the team can SEE everyone's bookings (client request, Nov 2026).
-- Re-runnable. Nothing is deleted or changed in the data.
--
--  * Seeing is read-only. Confirming, declining, moving, cancelling, notes and "Deposit received"
--    still belong to the booking's own professional and the owner (app.can_see is unchanged for writes).
--  * Another professional's private "Studio note", their booking history and their message log are
--    NOT shown; the rest of the booking is.
--  * Notifications (push alerts, the Messages page, the badge counts) stay per professional: each
--    login is only told about its own bookings and enquiries. The owner still gets everything.
--  * Clients, enquiries, services, availability, gallery and reports stay private to each professional.

-- Which professional the caller may LOOK at. Any active member may look at any professional of the salon
-- (NULL = everyone). Writes keep using app.scope_pro.
create or replace function app.view_scope(m app.memberships, p_requested uuid)
returns uuid language plpgsql stable set search_path = '' as $$
begin
  if p_requested is not null and not exists
     (select 1 from app.professionals where id = p_requested and salon_id = m.salon_id) then
    perform app.fail('forbidden', 'That profile is not part of this salon.');
  end if;
  return p_requested;
end $$;

-- booking_json for a viewer: the private studio note is only for the owner and the booking's own professional.
create or replace function app.booking_json_for(m app.memberships, k app.bookings)
returns jsonb language sql stable set search_path = '' as $$
  select case when app.can_see(m, k.professional_id) then app.booking_json(k)
              else app.booking_json(k) - 'internal_note' end
$$;

-- A clear message when someone can see a booking but may not change it.
create or replace function app.booking_for_caller(p_booking uuid, p_lock boolean default false)
returns app.bookings language plpgsql set search_path = '' as $$
declare k app.bookings; m app.memberships; uid uuid := auth.uid(); v_name text;
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
  if k.id is null or m.id is null then
    perform app.fail('not_found', 'Booking not found.');
  end if;
  if not app.can_see(m, k.professional_id) then
    if p_lock then
      select display_name into v_name from app.professionals where id = k.professional_id;
      perform app.fail('forbidden', 'You can see this booking, but only ' || coalesce(v_name, 'its professional') || ' or the owner can change it.');
    end if;
    perform app.fail('not_found', 'Booking not found.');
  end if;
  return k;
end $$;

-- Read-only load of one booking for the drawer.
create or replace function public.salon_dash_booking(p_booking uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare k app.bookings; m app.memberships; uid uuid := auth.uid(); own boolean;
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  select * into k from app.bookings where id = p_booking;
  if k.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = k.salon_id and status = 'active';
  end if;
  if k.id is null or m.id is null then perform app.fail('not_found', 'Booking not found.'); end if;
  own := app.can_see(m, k.professional_id);
  return jsonb_build_object('ok', true, 'booking', app.booking_json_for(m, k), 'can_edit', own,
    'client_visits', (select count(*) from app.bookings x where x.client_id = k.client_id and x.status = 'completed'),
    'history', case when not own then '[]'::jsonb else (
                select coalesce(jsonb_agg(jsonb_build_object('at', a.created_at, 'action', a.action,
                  'actor', a.actor_label, 'detail', a.detail) order by a.created_at), '[]'::jsonb)
                from app.audit_log a where a.entity = 'booking' and a.entity_id = k.id::text) end,
    'messages', case when not own then '[]'::jsonb else (
                select coalesce(jsonb_agg(jsonb_build_object('at', n.created_at, 'purpose', n.purpose,
                  'audience', n.audience, 'status', n.status, 'body', n.body) order by n.created_at), '[]'::jsonb)
                from app.notifications n where n.booking_id = k.id) end);
end $$;

-- The login's professional list: owners get everyone; everyone else gets the whole active team
-- (names and colours only) so the calendar can show every column.
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
          where p.salon_id = s.id and (m.role = 'owner' or p.active or p.id = m.professional_id))
      ) order by s.name), '[]'::jsonb)
      from app.memberships m join app.salons s on s.id = m.salon_id
      where m.user_id = uid and m.status = 'active'));
end $$;

-- Overview: counts, today and awaiting-confirmation for the chosen professional (or everyone)
create or replace function public.salon_dash_overview(p_salon uuid, p_professional uuid default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; s app.salons; today date; t0 timestamptz; t1 timestamptz;
begin
  m := app.my_membership(p_salon);
  pro := app.view_scope(m, p_professional);
  select * into s from app.salons where id = p_salon;
  perform app.expire_stale(s.id);
  today := (now() at time zone s.timezone)::date;
  t0 := today::timestamp at time zone s.timezone;
  t1 := (today + 1)::timestamp at time zone s.timezone;

  return jsonb_build_object('ok', true, 'scope', pro, 'today', to_char(today, 'YYYY-MM-DD'),
    'today_items', (select coalesce(jsonb_agg(app.booking_json_for(m, k) order by k.starts_at), '[]'::jsonb)
                    from app.bookings k where k.salon_id = s.id and (pro is null or k.professional_id = pro)
                      and k.starts_at >= t0 and k.starts_at < t1
                      and k.status in ('pending','confirmed','completed','no_show')),
    'needs_confirming', (select coalesce(jsonb_agg(x.j order by x.st), '[]'::jsonb) from (
                           select app.booking_json_for(m, k) j, k.starts_at st from app.bookings k
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
    'by_professional', case when pro is null then (
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

-- Bookings list and calendar feed
create or replace function public.salon_dash_bookings(p_salon uuid, p_professional uuid default null,
                                                      p_from timestamptz default null, p_to timestamptz default null,
                                                      p_statuses text[] default null, p_search text default null,
                                                      p_limit int default 500)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; q text := lower(btrim(coalesce(p_search, ''))); qd text;
begin
  m := app.my_membership(p_salon);
  pro := app.view_scope(m, p_professional);
  perform app.expire_stale(p_salon);
  qd := regexp_replace(q, '[^0-9]', '', 'g');
  return jsonb_build_object('ok', true, 'items', (
    select coalesce(jsonb_agg(x.j order by x.st), '[]'::jsonb) from (
      select app.booking_json_for(m, k) j, k.starts_at st
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

-- Schedule (calendar shading and time off)
create or replace function public.salon_dash_schedule(p_salon uuid, p_professional uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; pro uuid; s app.salons;
begin
  m := app.my_membership(p_salon);
  pro := app.view_scope(m, p_professional);
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

do $$
begin
  revoke all on function public.salon_dash_booking(uuid) from public;
  revoke all on function public.salon_me() from public;
  revoke all on function public.salon_dash_overview(uuid, uuid) from public;
  revoke all on function public.salon_dash_bookings(uuid, uuid, timestamptz, timestamptz, text[], text, int) from public;
  revoke all on function public.salon_dash_schedule(uuid, uuid) from public;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.salon_dash_booking(uuid), public.salon_me(), public.salon_dash_overview(uuid, uuid),
      public.salon_dash_bookings(uuid, uuid, timestamptz, timestamptz, text[], text, int),
      public.salon_dash_schedule(uuid, uuid) from anon;
    grant execute on function public.salon_dash_booking(uuid), public.salon_me(), public.salon_dash_overview(uuid, uuid),
      public.salon_dash_bookings(uuid, uuid, timestamptz, timestamptz, text[], text, int),
      public.salon_dash_schedule(uuid, uuid) to authenticated;
  end if;
end $$;
