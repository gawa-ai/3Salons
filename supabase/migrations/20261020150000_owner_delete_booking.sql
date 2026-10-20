-- Owner-only: permanently delete a booking that is no longer active (cancelled, declined, expired,
-- completed, no-show). Active bookings must be cancelled first so the client is told and the time is released.
-- A snapshot is kept in the audit log. Re-runnable.
create or replace function public.salon_owner_booking_delete(p_booking uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k app.bookings; m app.memberships; c app.clients; v_code text; v_detail text;
begin
  select * into k from app.bookings where id = p_booking;
  if k.id is null then perform app.fail('not_found', 'Booking not found.'); end if;
  m := app.require_owner(k.salon_id);
  if k.status in ('pending', 'confirmed') then
    perform app.fail('still_active', 'Cancel or decline this booking first, so the client is told and the time is released. Then you can delete it.');
  end if;
  select * into c from app.clients where id = k.client_id;
  perform app.audit(k.salon_id, k.professional_id, m.user_id, 'owner', 'booking.deleted', 'booking', k.id::text,
    jsonb_build_object('ref', k.ref, 'status', k.status, 'service', k.service_name, 'starts_at', k.starts_at, 'client', c.name));
  delete from app.bookings where id = k.id;
  return jsonb_build_object('ok', true);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

do $$
begin
  revoke all on function public.salon_owner_booking_delete(uuid) from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.salon_owner_booking_delete(uuid) from anon;
    grant execute on function public.salon_owner_booking_delete(uuid) to authenticated;
  end if;
end $$;
