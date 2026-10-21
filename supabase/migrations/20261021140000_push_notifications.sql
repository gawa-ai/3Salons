-- Web push for the Studio (PWA): artists and the owner get a phone notification for new booking
-- requests, client cancellations and new enquiries. Re-runnable. No secrets in this file
-- (the VAPID private key lives only in the Edge Function secrets).
--
--   app.push_subscriptions  one row per browser/phone that turned notifications on
--   app.push_outbox         one row per alert to send; filled by a trigger on app.notifications
--   public.push_*           browser API (signed-in users only) + worker API (service_role only)
-- Who is told: every active owner login, plus the login of the professional the alert is about.
-- A push problem must never block a booking: the trigger swallows its own errors.

create table if not exists app.push_subscriptions (
  id           bigint generated always as identity primary key,
  salon_id     uuid not null references app.salons(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  endpoint     text not null unique check (length(endpoint) <= 1000),
  p256dh       text not null check (length(p256dh) between 80 and 120),
  auth         text not null check (length(auth) between 16 and 40),
  user_agent   text,
  active       boolean not null default true,
  failures     int not null default 0,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user on app.push_subscriptions (user_id) where active;
create index if not exists push_subscriptions_salon on app.push_subscriptions (salon_id) where active;

create table if not exists app.push_outbox (
  id              bigint generated always as identity primary key,
  salon_id        uuid not null references app.salons(id) on delete cascade,
  professional_id uuid,
  user_id         uuid references auth.users(id) on delete cascade,   -- set = only this login (test alerts)
  notification_id bigint unique references app.notifications(id) on delete cascade,
  purpose         text not null,
  title           text not null check (length(title) <= 120),
  body            text not null check (length(body) <= 300),
  url             text not null default '/studio' check (url like '/studio%'),
  tag             text,
  status          text not null default 'queued' check (status in ('queued','sent','failed','skipped')),
  attempts        int not null default 0,
  next_attempt_at timestamptz,
  locked_at       timestamptz,
  sent_at         timestamptz,
  last_error      text,
  created_at      timestamptz not null default now()
);
create index if not exists push_outbox_queue on app.push_outbox (id) where status = 'queued';

alter table app.push_subscriptions enable row level security;
alter table app.push_outbox enable row level security;
revoke all on app.push_subscriptions, app.push_outbox from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Trigger: a professional-facing notification also becomes a push alert
-- ---------------------------------------------------------------------
create or replace function app.push_enqueue()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  s app.salons; k app.bookings; c app.clients; e app.enquiries;
  v_title text; v_body text; v_url text; v_tag text;
begin
  select * into s from app.salons where id = new.salon_id;
  if new.booking_id is not null then
    select * into k from app.bookings where id = new.booking_id;
    select * into c from app.clients where id = k.client_id;
    v_body := concat_ws(' · ', k.service_name, app.fmt_when(k.starts_at, s.timezone), nullif(btrim(coalesce(c.name, '')), ''));
    v_tag := 'b:' || k.id::text || ':' || new.purpose;
    if new.purpose = 'new_request' then
      v_title := 'New booking request'; v_url := '/studio/bookings?view=pending';
    else
      v_title := 'Booking cancelled by client'; v_url := '/studio/bookings';
    end if;
  elsif new.enquiry_id is not null then
    select * into e from app.enquiries where id = new.enquiry_id;
    v_title := 'New enquiry';
    v_body := concat_ws(' · ', initcap(e.kind) || ' enquiry', nullif(btrim(coalesce(e.name, '')), ''),
                        case when e.event_date is not null then to_char(e.event_date, 'Dy FMDD Mon YYYY') end);
    v_url := '/studio/enquiries'; v_tag := 'e:' || e.id::text;
  else
    return new;
  end if;
  insert into app.push_outbox (salon_id, professional_id, notification_id, purpose, title, body, url, tag)
  values (new.salon_id, new.professional_id, new.id, new.purpose, left(v_title, 120), left(v_body, 300), v_url, v_tag)
  on conflict (notification_id) do nothing;
  return new;
exception when others then
  return new;     -- never block a booking or an enquiry because of an alert
end $$;

drop trigger if exists notifications_push_enqueue on app.notifications;
create trigger notifications_push_enqueue
  after insert on app.notifications
  for each row
  when (new.audience = 'professional' and new.purpose in ('new_request', 'new_enquiry', 'cancelled_pro'))
  execute function app.push_enqueue();

-- ---------------------------------------------------------------------
-- Browser API (signed-in studio users only)
-- ---------------------------------------------------------------------
create or replace function public.push_subscribe(p_salon uuid, p_sub jsonb, p_user_agent text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  m app.memberships; v_end text := p_sub->>'endpoint'; v_p text := p_sub#>>'{keys,p256dh}'; v_a text := p_sub#>>'{keys,auth}';
  v_code text; v_detail text;
begin
  m := app.my_membership(p_salon);
  -- Only the real browser push services are accepted, so nobody can make our server call another address.
  if v_end is null or v_end !~ '^https://(fcm\.googleapis\.com|web\.push\.apple\.com|[a-z0-9-]+\.push\.apple\.com|updates\.push\.services\.mozilla\.com|[a-z0-9.-]+\.notify\.windows\.com)/[A-Za-z0-9_\-/=.~%:]+$'
     or length(v_end) > 1000 then
    perform app.fail('invalid_subscription', 'This browser sent notification details we cannot use.');
  end if;
  if v_p is null or v_a is null or v_p !~ '^[A-Za-z0-9_-]{80,120}$' or v_a !~ '^[A-Za-z0-9_-]{16,40}$' then
    perform app.fail('invalid_subscription', 'This browser sent notification details we cannot use.');
  end if;
  insert into app.push_subscriptions as ps (salon_id, user_id, endpoint, p256dh, auth, user_agent)
  values (p_salon, m.user_id, v_end, v_p, v_a, left(p_user_agent, 300))
  on conflict (endpoint) do update
    set salon_id = excluded.salon_id, user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
        user_agent = excluded.user_agent, active = true, failures = 0, last_seen_at = now();
  -- keep the newest 8 devices per login
  delete from app.push_subscriptions
   where user_id = m.user_id
     and id not in (select id from app.push_subscriptions where user_id = m.user_id order by last_seen_at desc, id desc limit 8);
  return jsonb_build_object('ok', true);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

create or replace function public.push_unsubscribe(p_endpoint text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  delete from app.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- Is this browser (endpoint) subscribed for the signed-in user? Also how many devices the login has.
create or replace function public.push_status(p_salon uuid, p_endpoint text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; v_code text; v_detail text;
begin
  m := app.my_membership(p_salon);
  return jsonb_build_object('ok', true,
    'this_device', exists (select 1 from app.push_subscriptions where user_id = m.user_id and endpoint = p_endpoint and active),
    'devices', (select count(*) from app.push_subscriptions where user_id = m.user_id and active));
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- "Send me a test": queues one alert for the caller's own devices only.
create or replace function public.push_test(p_salon uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; v_code text; v_detail text;
begin
  m := app.my_membership(p_salon);
  if not exists (select 1 from app.push_subscriptions where user_id = m.user_id and active) then
    perform app.fail('no_device', 'Turn notifications on for this phone first.');
  end if;
  if (select count(*) from app.push_outbox where user_id = m.user_id and purpose = 'test' and created_at > now() - interval '1 hour') >= 5 then
    perform app.fail('too_many_tests', 'You have sent a few tests already. Please try again later.');
  end if;
  insert into app.push_outbox (salon_id, user_id, purpose, title, body, url, tag)
  values (p_salon, m.user_id, 'test', 'Notifications are on', 'You will be told here about new requests and enquiries.', '/studio',
          'test:' || extract(epoch from clock_timestamp())::bigint::text);
  return jsonb_build_object('ok', true);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
-- Worker API (Edge Function, service_role only)
-- ---------------------------------------------------------------------
create or replace function public.push_claim(p_limit int default 10)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r app.push_outbox; subs jsonb; res jsonb := '[]'::jsonb;
begin
  -- a worker that died mid-send: let the row be picked up again (it has at most 3 attempts)
  update app.push_outbox set locked_at = null
   where status = 'queued' and locked_at is not null and locked_at < now() - interval '5 minutes';
  update app.push_outbox set status = 'failed', last_error = 'max_attempts', locked_at = null
   where status = 'queued' and attempts >= 3;

  for r in
    select * from app.push_outbox
     where status = 'queued' and locked_at is null and (next_attempt_at is null or next_attempt_at <= now())
     order by id limit greatest(1, least(coalesce(p_limit, 10), 25))
       for update skip locked
  loop
    if r.created_at < now() - interval '2 hours' then       -- too old to be useful
      update app.push_outbox set status = 'skipped', last_error = 'stale' where id = r.id;
      continue;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)), '[]'::jsonb)
      into subs
      from app.push_subscriptions s
     where s.active and s.salon_id = r.salon_id
       and (case when r.user_id is not null then s.user_id = r.user_id
                 else exists (select 1 from app.memberships m
                               where m.user_id = s.user_id and m.salon_id = r.salon_id and m.status = 'active'
                                 and (m.role = 'owner' or m.professional_id = r.professional_id)) end);
    if jsonb_array_length(subs) = 0 then
      update app.push_outbox set status = 'skipped', last_error = 'no_subscribers' where id = r.id;
      continue;
    end if;
    update app.push_outbox set locked_at = now(), attempts = attempts + 1 where id = r.id;
    res := res || jsonb_build_object('id', r.id, 'title', r.title, 'body', r.body, 'url', r.url, 'tag', r.tag, 'subs', subs);
  end loop;
  return res;
end $$;

-- p_results: [{ "sub_id": 12, "status": 201, "error": "..." }]  (status null = network error)
create or replace function public.push_complete(p_id bigint, p_results jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare x jsonb; v_status int; v_sub bigint; v_ok boolean := false; v_transient boolean := false; v_err text; r app.push_outbox;
begin
  select * into r from app.push_outbox where id = p_id for update;
  if r.id is null or r.status <> 'queued' then return; end if;
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    v_sub := nullif(x->>'sub_id', '')::bigint;
    v_status := nullif(x->>'status', '')::int;
    if v_status between 200 and 299 then
      v_ok := true;
      update app.push_subscriptions set failures = 0, last_seen_at = now() where id = v_sub;
    elsif v_status in (404, 410) then                      -- the phone removed the subscription
      update app.push_subscriptions set active = false where id = v_sub;
    else
      v_err := left(coalesce(x->>'error', 'http_' || coalesce(v_status::text, 'none')), 300);
      if v_status is null or v_status = 429 or v_status >= 500 then v_transient := true; end if;
      update app.push_subscriptions set failures = failures + 1, active = (failures + 1 < 10) where id = v_sub;
    end if;
  end loop;
  if v_ok then
    update app.push_outbox set status = 'sent', sent_at = now(), locked_at = null, last_error = null where id = p_id;
  elsif v_transient and r.attempts < 3 then
    update app.push_outbox set locked_at = null, last_error = v_err,
           next_attempt_at = now() + r.attempts * interval '1 minute' where id = p_id;
  else
    update app.push_outbox set status = 'failed', locked_at = null, last_error = coalesce(v_err, 'subscription_gone') where id = p_id;
  end if;
end $$;

do $$
begin
  execute 'revoke all on function app.push_enqueue() from public, anon, authenticated';
  execute 'revoke all on function public.push_subscribe(uuid, jsonb, text) from public, anon, authenticated';
  execute 'revoke all on function public.push_unsubscribe(text) from public, anon, authenticated';
  execute 'revoke all on function public.push_status(uuid, text) from public, anon, authenticated';
  execute 'revoke all on function public.push_test(uuid) from public, anon, authenticated';
  execute 'revoke all on function public.push_claim(int) from public, anon, authenticated';
  execute 'revoke all on function public.push_complete(bigint, jsonb) from public, anon, authenticated';
  execute 'grant execute on function public.push_subscribe(uuid, jsonb, text) to authenticated';
  execute 'grant execute on function public.push_unsubscribe(text) to authenticated';
  execute 'grant execute on function public.push_status(uuid, text) to authenticated';
  execute 'grant execute on function public.push_test(uuid) to authenticated';
  execute 'grant execute on function public.push_claim(int) to service_role';
  execute 'grant execute on function public.push_complete(bigint, jsonb) to service_role';
end $$;
