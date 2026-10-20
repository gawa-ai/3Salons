-- One deposit for a multi-service request (several bookings sharing group_id):
--  * the deposit request asks for the TOTAL of the whole group and lists the services, once;
--  * "Deposit received" on one booking marks the whole group paid and confirmed, with one thank-you text;
--  * if the deposit is missed, the client gets one "released" text, not one per booking.
-- Re-runnable. Functions are patched from their live definition and fail loudly if the expected text is missing.

-- Members of k's group that share the deposit (still open or paid, with a deposit).
create or replace function app.group_members(k app.bookings)
returns setof app.bookings language sql stable set search_path = '' as $$
  select b.* from app.bookings b
   where k.group_id is not null and b.group_id = k.group_id
     and b.status in ('pending', 'confirmed') and b.deposit_pence > 0
     and b.deposit_status in ('none', 'requested', 'received')
   order by b.starts_at, b.ref
$$;

-- Rewrites a deposit text so it covers the whole group. Single bookings are returned unchanged.
create or replace function app.group_body(p_purpose text, k app.bookings, p_body text)
returns text language plpgsql stable set search_path = '' as $$
declare n int; total int; lines text; tz text; first text; tail text;
begin
  if p_purpose not in ('deposit_request', 'deposit_received') or k.group_id is null then return p_body; end if;
  select s.timezone into tz from app.salons s where s.id = k.salon_id;
  select count(*), coalesce(sum(m.deposit_pence), 0),
         string_agg('- ' || m.service_name || ' with ' || pr.short_name || ', ' || app.fmt_when(m.starts_at, tz)
                    || ' (' || app.fmt_price(m.price_pence, m.price_kind) || ')', E'\n' order by m.starts_at, m.ref)
    into n, total, lines
    from app.group_members(k) m join app.professionals pr on pr.id = m.professional_id;
  if n < 2 then return p_body; end if;

  if p_purpose = 'deposit_request' then
    p_body := regexp_replace(p_body, '^(Hi [^\n]*\n\n)[^\n]*\n\n', E'\\1Your bookings are available:\n' || replace(lines, '\', '\\') || E'\n\n');
    p_body := replace(p_body, 'To secure your booking please pay a ' || app.fmt_price(k.deposit_pence, 'fixed') || ' non refundable deposit',
                              'To secure your bookings please pay a ' || app.fmt_price(total, 'fixed') || ' non refundable deposit');
    return p_body;
  end if;

  first := substring(p_body from '^Hi [^,]+,');
  tail := substring(p_body from position('Ref ' || k.ref || '.' in p_body));
  return first || ' thank you, we have received your ' || app.fmt_price(total, 'fixed')
         || E' deposit. Your bookings are confirmed:\n' || lines || E'\n' || tail;
end $$;

do $$
declare d text; marker text := 'app.group_body';
begin
  -- 1) texts: build the group wording
  d := pg_get_functiondef('app.notify_booking(app.bookings,text,text)'::regprocedure);
  if position(marker in d) = 0 then
    if position($o$body := replace(app.message_body(p_purpose, s, p, k, c), '{ref}', k.ref);$o$ in d) = 0 then
      raise exception 'notify_booking changed: cannot patch'; end if;
    d := replace(d, $o$body := replace(app.message_body(p_purpose, s, p, k, c), '{ref}', k.ref);$o$,
                    $n$body := app.group_body(p_purpose, k, replace(app.message_body(p_purpose, s, p, k, c), '{ref}', k.ref));$n$);
    execute d;
  end if;

  -- 2) asking for the deposit / receiving it
  d := pg_get_functiondef('public.salon_dash_booking_action(uuid,text,text,integer)'::regprocedure);
  if position('group_id' in d) = 0 then
    if position($o$    perform app.notify_booking(k, 'deposit_request', 'customer');$o$ in d) = 0
       or position($o$  if act = 'deposit_received' then
    perform app.notify_booking(k, 'deposit_received', 'customer');$o$ in d) = 0 then
      raise exception 'salon_dash_booking_action changed: cannot patch'; end if;
    d := replace(d, $o$    perform app.notify_booking(k, 'deposit_request', 'customer');$o$,
$n$    update app.bookings
       set deposit_status = 'requested', deposit_due_at = k.deposit_due_at, version = version + 1, updated_at = now()
     where k.group_id is not null and group_id = k.group_id and id <> k.id
       and status = 'pending' and deposit_pence > 0 and deposit_status = 'none';
    perform app.notify_booking(k, 'deposit_request', 'customer');$n$);
    d := replace(d, $o$  if act = 'deposit_received' then
    perform app.notify_booking(k, 'deposit_received', 'customer');$o$,
$n$  if act = 'deposit_received' then
    if k.group_id is not null then
      update app.bookings
         set status = 'confirmed', confirmed_at = now(), version = version + 1, updated_at = now(),
             deposit_status = case when deposit_pence > 0 then 'received' else deposit_status end,
             deposit_received_at = case when deposit_pence > 0 then now() else deposit_received_at end
       where group_id = k.group_id and id <> k.id and status = 'pending' and starts_at > now();
    end if;
    perform app.notify_booking(k, 'deposit_received', 'customer');$n$);
    execute d;
  end if;

  -- 3) a missed deposit releases the group with one text
  d := pg_get_functiondef('app.expire_stale(uuid)'::regprocedure);
  if position('group_id' in d) = 0 then
    if position($o$    perform app.notify_booking(k, 'deposit_expired', 'customer');$o$ in d) = 0 then
      raise exception 'expire_stale changed: cannot patch'; end if;
    d := replace(d, $o$    perform app.notify_booking(k, 'deposit_expired', 'customer');$o$,
$n$    if k.group_id is null or not exists (select 1 from app.notifications n join app.bookings b on b.id = n.booking_id
                                          where b.group_id = k.group_id and n.purpose = 'deposit_expired') then
      perform app.notify_booking(k, 'deposit_expired', 'customer');
    end if;$n$);
    execute d;
  end if;
end $$;
