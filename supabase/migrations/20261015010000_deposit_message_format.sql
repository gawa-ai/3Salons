-- Round 5 (client, 2026-10-15): the deposit message must read exactly like Shahina's own wording
-- (line breaks kept, her name, address and number at the bottom). Only the deposit request text changes;
-- the payment details are still typed by the owner in Studio > Settings (never in git).
-- {payment} is the owner's text followed by a line break; {signature} is name, title, address lines, private number.
-- Re-runnable.

create or replace function app.message_body(p_purpose text, s app.salons, p app.professionals,
                                            k app.bookings, c app.clients)
returns text language sql stable set search_path = '' as $$
  select replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
    case p_purpose
      when 'request_received' then 'Hi {first}, thank you for your booking request with {pro} at {salon}: {service} on {when}. It is provisional until {pro_short} confirms. Ref {ref}.'
      when 'new_request'      then 'New booking request: {service} on {when} for {client}. Ref {ref}. Please confirm or decline in your dashboard.'
      when 'confirmed'        then 'Hi {first}, {pro_short} has confirmed your {service} on {when} at {salon}. Ref {ref}.{contact}'
      when 'deposit_request'  then E'Hi {first},\n\n{pro_short} is available for {service} on {when}.\n\nPlease note all bookings take place at the studio unless discussed otherwise\n(Please see below for address)\n\nTo secure your booking please pay a {deposit} non refundable deposit within {hours} hours, which will be deducted on the day.\n\n{payment}Please leave your ref {ref} as the payment reference.\n\n{signature}'
      when 'deposit_received' then 'Hi {first}, thank you, we have received your {deposit} deposit. Your {service} with {pro_short} on {when} at {salon} is confirmed. Ref {ref}.{contact}'
      when 'deposit_expired'  then 'Hi {first}, we did not receive the deposit for your {service} on {when}, so the time has been released. You are welcome to book again on our website. Ref {ref}.'
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
    '{contact}', coalesce(' Questions? Call ' || nullif(btrim(s.private_phone), '') || '.', '')),
    '{deposit}', app.fmt_price(k.deposit_pence, 'fixed')),
    '{hours}', s.deposit_hours::text),
    '{payment}', coalesce(nullif(btrim(s.deposit_instructions), '') || E'\n', '')),
    '{signature}', s.name || E'\nMakeup Artist' ||
                   coalesce(E'\n' || nullif(replace(btrim(coalesce(s.address, '')), ', ', E'\n'), ''), '') ||
                   coalesce(E'\n' || nullif(btrim(s.private_phone), ''), ''))
$$;
