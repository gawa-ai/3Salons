-- Round 3c (client, 2026-10-14): customer messages go out by text AND email.
-- Every customer message is now also recorded as an email row when the client left an email address.
-- Nothing is sent until the salon's email service is connected (salons.email_connected, default false),
-- same as SMS today. Re-runnable; no data is changed or removed.
alter table app.salons add column if not exists email_connected boolean not null default false;

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
  if p_audience = 'customer' and nullif(btrim(coalesce(c.email, '')), '') is not null then
    insert into app.notifications (salon_id, professional_id, booking_id, audience, channel, purpose, to_addr, body, status, dedupe_key)
    values (k.salon_id, k.professional_id, k.id, 'customer', 'email', p_purpose, btrim(c.email), body,
            case when s.email_connected then 'queued' else 'not_connected' end,
            k.id::text || ':v' || k.version || ':' || p_purpose || ':customer:email')
    on conflict (dedupe_key) do nothing;
  end if;
  -- a cancelled/declined/moved booking must never get a stale queued message
  if p_purpose in ('cancelled','declined','rescheduled','cancelled_pro') then
    update app.notifications set status = 'cancelled', updated_at = now()
     where booking_id = k.id and status = 'queued'
       and dedupe_key not like k.id::text || ':v' || k.version || ':%';
  end if;
end $$;
