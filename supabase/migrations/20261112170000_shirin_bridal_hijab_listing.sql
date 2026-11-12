-- Shirin's public service list: same "Bridal Hijab, from £100 (plus travel), 1 hr" card as Sabiha.
-- Added as its own enquiry-only service in the hijab category (her "Bridal" service stays the one the
-- bridal deposit flow uses). Re-runnable.
insert into app.services (salon_id, professional_id, name, description, category, duration_min, buffer_min,
                          price_pence, price_kind, bookable_online, details_confirmed, sort_order)
select p.salon_id, p.id, 'Bridal Hijab', 'Bridal hijab styling. Please send an enquiry.', 'hijab', 60, 0,
       10000, 'from', false, false, 5
  from app.professionals p join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
 where p.slug = 'shirin-jal'
on conflict (professional_id, (lower(name))) do update
   set price_pence = 10000, price_kind = 'from', duration_min = 60, bookable_online = false, updated_at = now();
