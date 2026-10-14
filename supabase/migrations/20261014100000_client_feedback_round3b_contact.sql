-- Round 3b (client, 2026-10-14): the confirmation text carries the studio contact number.
-- The number comes from the salon record (Studio > Settings > Phone). Until it is filled in, nothing is
-- added to the text, so no placeholder or invented number can ever be sent. Re-runnable; template only.
create or replace function app.message_body(p_purpose text, s app.salons, p app.professionals,
                                            k app.bookings, c app.clients)
returns text language sql stable set search_path = '' as $$
  select replace(replace(replace(replace(replace(replace(replace(replace(
    case p_purpose
      when 'request_received' then 'Hi {first}, thank you for your booking request with {pro} at {salon}: {service} on {when}. It is provisional until {pro_short} confirms. Ref {ref}.'
      when 'new_request'      then 'New booking request: {service} on {when} for {client}. Ref {ref}. Please confirm or decline in your dashboard.'
      when 'confirmed'        then 'Hi {first}, {pro_short} has confirmed your {service} on {when} at {salon}. Ref {ref}.{contact}'
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
    '{contact}', coalesce(' Questions? Call ' || nullif(btrim(s.phone), '') || '.', ''))
$$;
