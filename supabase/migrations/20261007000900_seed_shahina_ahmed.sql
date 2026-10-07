-- =====================================================================
-- Seed: Shahina Ahmed Luxury Salon (Blackburn)
--
-- SOURCE OF EACH VALUE
--   Prices / services ........ client's WhatsApp price list (2026-10-07)
--   Instagram links .......... client's WhatsApp message (tracking params removed)
--   Profile labels ........... the build brief ("Sofia MUA", "Shirin Jal", "Mi Hijabby Sabiha").
--                              Logo lettering differs ("sofia musa", "Mi hijab by Sabiha"): to be
--                              confirmed by the owner, NOT silently renamed.
--   Specialty lines .......... logo lettering (Sofia, Shirin) or the services they list (Shahina, Sabiha)
--   City ..................... Instagram bios of Sofia MUA and Shirin Jal ("Blackburn")
--   Durations, buffers ....... STAGING VALUES, NOT CONFIRMED  -> services.details_confirmed = false
--   Opening/working hours .... STAGING VALUES, NOT CONFIRMED  -> salons.hours_confirmed = false
--   Address/phone/policy ..... unknown -> NULL (never shown as fact)
-- Safe to re-run: inserts skip existing rows.
-- =====================================================================

insert into app.salons (slug, name, tagline, timezone, country_code, booking_mode, city,
                        slot_interval_min, min_notice_min, max_days_ahead, hours_confirmed)
values ('shahina-ahmed', 'Shahina Ahmed Luxury Salon',
        'Hair, makeup and hijab styling for the moments that matter.',
        'Europe/London', '44', 'preview', 'Blackburn', 15, 120, 90, false)
on conflict (slug) do nothing;

with s as (select id from app.salons where slug = 'shahina-ahmed')
insert into app.professionals (salon_id, slug, display_name, short_name, specialty, bio, instagram_url, logo_path, color, sort_order)
select s.id, x.slug, x.display_name, x.short_name, x.specialty, x.bio, x.ig, x.logo, x.color, x.ord
from s, (values
  ('shahina-ahmed', 'Shahina Ahmed', 'Shahina', 'Hair & Makeup', null, null, '/brand/sa-monogram.svg', 'bronze', 1),
  ('sofia-mua', 'Sofia MUA', 'Sofia', 'Makeup Artist', null,
     'https://www.instagram.com/sofimusamua/', '/brand/pros/sofia-mua.webp', 'rose', 2),
  ('shirin-jal', 'Shirin Jal', 'Shirin', 'Hair & Makeup Artist', null,
     'https://www.instagram.com/shirin_jal/', '/brand/pros/shirin-jal.webp', 'slate', 3),
  ('mi-hijabby-sabiha', 'Mi Hijabby Sabiha', 'Sabiha', 'Hijab Styling', null,
     'https://www.instagram.com/mi.hijabbysabiha/', '/brand/pros/mi-hijabby-sabiha.webp', 'plum', 4)
) as x(slug, display_name, short_name, specialty, bio, ig, logo, color, ord)
on conflict (salon_id, slug) do nothing;

-- Services (prices from the client's list). Durations/buffers are placeholders to confirm.
with s as (select id from app.salons where slug = 'shahina-ahmed')
insert into app.services (salon_id, professional_id, name, description, category, duration_min, buffer_min,
                          price_pence, price_kind, bookable_online, details_confirmed, sort_order)
select s.id, p.id, x.name, x.descr, x.cat, x.dur, x.buf, x.price, x.kind, x.kind <> 'enquire', false, x.ord
from s
join app.professionals p on p.salon_id = s.id
join (values
  ('shahina-ahmed',      'Party Hair',          'Hair styling for parties and occasions.',                  'hair',        60, 15, 5000, 'fixed',   1),
  ('shahina-ahmed',      'Party Makeup',        'Makeup for parties and occasions.',                        'makeup',      60, 15, 5000, 'fixed',   2),
  ('shahina-ahmed',      'Party Hair & Makeup', 'Hair styling and makeup together.',                        'hair_makeup', 120, 15, 9500, 'fixed',  3),
  ('shahina-ahmed',      'Bridal',              'Bridal styling. Please send an enquiry.',                  'bridal',      60, 0, null, 'enquire',  9),
  ('sofia-mua',         'Party Hair',          'Hair styling for parties and occasions.',                  'hair',        60, 15, 5000, 'fixed',   1),
  ('sofia-mua',         'Party Makeup',        'Makeup for parties and occasions.',                        'makeup',      60, 15, 5000, 'fixed',   2),
  ('sofia-mua',         'Party Hair & Makeup', 'Hair styling and makeup together.',                        'hair_makeup', 120, 15, 9500, 'fixed',  3),
  ('sofia-mua',         'Saree Styling',       'Saree draping and styling.',                               'saree',       30, 15, 2500, 'fixed',   4),
  ('sofia-mua',         'Bridal',              'Bridal styling. Please send an enquiry.',                  'bridal',      60, 0, null, 'enquire',  9),
  ('shirin-jal',         'Party Hair',          'Hair styling for parties and occasions.',                  'hair',        60, 15, 5000, 'fixed',   1),
  ('shirin-jal',         'Party Makeup',        'Makeup for parties and occasions.',                        'makeup',      60, 15, 5000, 'fixed',   2),
  ('shirin-jal',         'Party Hair & Makeup', 'Hair styling and makeup together.',                        'hair_makeup', 120, 15, 9500, 'fixed',  3),
  ('shirin-jal',         'Party Hijab',         'Hijab styling for parties and occasions.',                 'hijab',       30, 15, 3000, 'fixed',   4),
  ('shirin-jal',         'Bridal',              'Bridal styling. Please send an enquiry.',                  'bridal',      60, 0, null, 'enquire',  9),
  ('mi-hijabby-sabiha', 'Party Hijab',         'Hijab styling for parties and occasions.',                   'hijab',       30, 15, 3000, 'fixed',   1),
  ('mi-hijabby-sabiha', 'Bridal',              'Bridal styling. Please send an enquiry.',                  'bridal',      60, 0, null, 'enquire',  9)
) as x(pro, name, descr, cat, dur, buf, price, kind, ord) on x.pro = p.slug
on conflict (professional_id, (lower(name))) do nothing;

-- STAGING hours (to confirm with the owner): salon and every professional 10:00-18:00, Mon-Sun.
with s as (select id from app.salons where slug = 'shahina-ahmed')
insert into app.opening_hours (salon_id, weekday, opens, closes)
select s.id, d, '10:00', '18:00' from s, generate_series(0, 6) d
on conflict do nothing;

insert into app.working_hours (professional_id, weekday, opens, closes)
select p.id, d, '10:00', '18:00'
from app.professionals p join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed', generate_series(0, 6) d
where not exists (select 1 from app.working_hours w where w.professional_id = p.id)
on conflict do nothing;
