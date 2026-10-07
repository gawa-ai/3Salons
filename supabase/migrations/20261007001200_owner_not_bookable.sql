-- =====================================================================
-- Shahina Ahmed is the owner and the brand, not a bookable artist.
-- Non-destructive and re-runnable: nothing is deleted. A legacy "shahina-ahmed"
-- professional (from the first seed) is hidden and closed to booking, and the
-- owner login is no longer tied to a professional profile.
-- =====================================================================

update app.professionals p
   set active = false, is_public = false, online_booking = false
  from app.salons s
 where s.id = p.salon_id and s.slug = 'shahina-ahmed' and p.slug = 'shahina-ahmed'
   and (p.active or p.is_public or p.online_booking);

update app.services v
   set active = false
  from app.professionals p
  join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
 where v.professional_id = p.id and p.slug = 'shahina-ahmed' and v.active;

-- an owner membership/invitation must not point at that profile
update app.memberships m set professional_id = null
  from app.professionals p
 where m.role = 'owner' and m.professional_id = p.id and p.slug = 'shahina-ahmed';
update app.invitations i set professional_id = null
  from app.professionals p
 where i.role = 'owner' and i.professional_id = p.id and p.slug = 'shahina-ahmed';

create or replace function app.create_owner_invitation(p_salon_slug text, p_email text)
returns text language plpgsql volatile set search_path = '' as $$
declare s app.salons := app.resolve_salon(p_salon_slug); r jsonb;
begin
  if exists (select 1 from app.memberships where salon_id = s.id and role = 'owner' and status = 'active') then
    perform app.fail('owner_exists', 'This salon already has an active owner. Use the dashboard instead.');
  end if;
  r := app.create_invitation(s.id, 'owner', null, p_email, null, 7);
  return 'Invitation code for ' || (r->>'email') || ': ' || (r->>'code') || '  (expires ' || (r->>'expires_at') || ')';
end $$;
