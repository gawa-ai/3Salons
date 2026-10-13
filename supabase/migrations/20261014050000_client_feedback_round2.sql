-- =====================================================================
-- Client feedback, round 2 (Shahina's amendments PDF, 2026-10-14). Re-runnable, non-destructive.
--   * "Mi Hijabby Sabiha" -> "Sabiha Patel" (slug 'mi-hijabby-sabiha' unchanged so links keep working)
--   * Artist roles: Shahina / Sofia = Hair and Makeup Artist; Shirin = Hair and Makeup Artist / Hijab Stylist;
--     Sabiha = Hijab Stylist
--   * Service descriptions no longer show under the title. The description field is now shown only as a
--     short pricing note beside the price, so every old sentence is cleared (the text is kept in git history
--     of the earlier migrations) and the one real pricing note is added.
--   * Training added for Shahina (enquiry only, no price)
--   * Gallery: Shahina's photo first; captions credit hijab by Sabiha Patel
-- =====================================================================
update app.professionals p
   set display_name = 'Sabiha Patel', updated_at = now()
  from app.salons s
 where s.id = p.salon_id and s.slug = 'shahina-ahmed' and p.slug = 'mi-hijabby-sabiha' and p.display_name <> 'Sabiha Patel';

update app.professionals p
   set specialty = v.role, updated_at = now()
  from app.salons s, (values
    ('shahina-ahmed',     'Hair and Makeup Artist'),
    ('sofia-mua',         'Hair and Makeup Artist'),
    ('shirin-jal',        'Hair and Makeup Artist / Hijab Stylist'),
    ('mi-hijabby-sabiha', 'Hijab Stylist')) as v(slug, role)
 where s.id = p.salon_id and s.slug = 'shahina-ahmed' and p.slug = v.slug and p.specialty is distinct from v.role;

-- Old descriptive sentences (only the seeded wording is cleared; anything the owner wrote is kept).
update app.services sv set description = null, updated_at = now()
  from app.salons s
 where s.id = sv.salon_id and s.slug = 'shahina-ahmed'
   and sv.description in ('Hair styling for parties and occasions.', 'Makeup for parties and occasions.',
       'Hair styling and makeup together.', 'Saree draping and styling.', 'Hijab styling for parties and occasions.',
       'Bridal styling. Please send an enquiry.');

-- Pricing note shown beside Shahina's Party Hair price.
update app.services sv set description = 'Hair extensions available at an extra cost', updated_at = now()
  from app.professionals p
 where p.id = sv.professional_id and p.slug = 'shahina-ahmed' and sv.name = 'Party Hair' and sv.description is null;

-- Training (enquiry only).
insert into app.services (salon_id, professional_id, name, description, category, duration_min, price_kind, bookable_online, sort_order)
select p.salon_id, p.id, 'Training', null, 'other', 60, 'enquire', false, 8
  from app.professionals p join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
 where p.slug = 'shahina-ahmed'
on conflict (professional_id, lower(name)) do nothing;

-- Gallery order and credits.
update app.gallery_items g set caption = 'Makeup by Shahina Ahmed, hijab by Sabiha Patel', sort_order = 1
  from app.professionals p
 where p.id = g.professional_id and p.slug = 'shahina-ahmed' and g.storage_path = '/gallery/shahina-ahmed/featured-1.jpg';
update app.gallery_items g set caption = 'Makeup by Shahina Ahmed, hijab by Sabiha Patel'
 where g.storage_path = '/gallery/mi-hijabby-sabiha/featured-1.jpg';
