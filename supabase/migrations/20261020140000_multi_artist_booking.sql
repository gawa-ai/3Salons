-- Book 2 or 3 services with DIFFERENT artists at the same start time, in one go (all-or-nothing).
-- Each artist still gets and handles her own booking request (own confirmation, deposit, manage link).
-- Built on salon_public_book, so every rule (hours, notice, overlap, policy, rate limits, idempotency) is unchanged.
-- Re-runnable.
alter table app.bookings add column if not exists group_id uuid;
create index if not exists bookings_group_idx on app.bookings (group_id) where group_id is not null;

create or replace function public.salon_public_book_multi(p_salon text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a jsonb := coalesce(p_payload, '{}'::jsonb);
  s app.salons; items jsonb; n int; i int; one jsonb; r jsonb;
  res jsonb[] := '{}'; names text[] := '{}'; refs text[] := '{}';
  pro_ids uuid[] := '{}'; pro app.professionals; base text; gid uuid := gen_random_uuid();
  any_dup boolean := false; ord int[]; j int; v_code text; v_detail text; out_items jsonb := '[]'::jsonb;
begin
  s := app.resolve_salon(p_salon);
  items := a->'items';
  if items is null or jsonb_typeof(items) <> 'array' then
    perform app.fail('invalid_request', 'Please choose the artists and services again.');
  end if;
  n := jsonb_array_length(items);
  if n < 2 or n > 3 then
    perform app.fail('invalid_request', 'Choose two or three services, each with a different artist.');
  end if;
  base := a->>'idempotency_key';
  if base is null or base !~ '^[A-Za-z0-9_-]{16,64}$' then
    perform app.fail('invalid_request', 'Please refresh the page and try again.');
  end if;

  -- every item needs a different artist (several people with the same artist = use "people", one longer booking)
  for i in 0 .. n - 1 loop
    pro := app.resolve_public_pro(s.id, items->i->>'professional');
    if pro.id = any (pro_ids) then
      perform app.fail('same_artist', 'Each service must be with a different artist. For two people with the same artist, choose "2 people" instead.');
    end if;
    pro_ids := pro_ids || pro.id;
  end loop;

  -- process in a fixed artist order so two simultaneous requests can never deadlock
  select array_agg(x.i order by pid::text) into ord
    from (select g as i, pro_ids[g + 1] as pid from generate_series(0, n - 1) g) x;

  res := array_fill(null::jsonb, array[n]);
  foreach j in array ord loop
    one := (a - 'items') || jsonb_build_object(
      'professional', items->j->>'professional',
      'service',      items->j->>'service',
      'party_size',   coalesce(items->j->>'party_size', '1'),
      'idempotency_key', left(base, 56) || '-m' || (j + 1));
    r := public.salon_public_book(p_salon, one);
    if coalesce((r->>'ok')::boolean, false) is not true then
      -- undo every booking made so far in this request
      perform app.fail(coalesce(r->>'error', 'booking_failed'), coalesce(r->>'message', 'We could not make this booking.'));
    end if;
    res[j + 1] := r;
    if coalesce((r->>'duplicate')::boolean, false) then any_dup := true; end if;
  end loop;

  if not any_dup then
    for i in 1 .. n loop
      names := names || (res[i]->>'professional');
      refs := refs || (res[i]->>'ref');
    end loop;
    for i in 1 .. n loop
      update app.bookings
         set group_id = gid,
             internal_note = concat_ws(E'\n', internal_note,
               'Booked together at the same time with: ' ||
               (select string_agg(names[k] || ' (ref ' || refs[k] || ')', ', ' order by k) from generate_series(1, n) k where k <> i) || '.')
       where salon_id = s.id and ref = refs[i];
    end loop;
  end if;

  for i in 1 .. n loop out_items := out_items || jsonb_build_array(res[i]); end loop;
  return jsonb_build_object('ok', true, 'group', true, 'bookings', out_items,
                            'preview', s.booking_mode = 'preview',
                            'message', 'Your requests are in. Each artist will confirm her own appointment.');
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

do $$
begin
  revoke all on function public.salon_public_book_multi(text, jsonb) from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.salon_public_book_multi(text, jsonb) to anon, authenticated;
  end if;
end $$;
