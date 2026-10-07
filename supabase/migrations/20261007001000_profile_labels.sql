-- =====================================================================
-- Profile labels follow the build brief: "Sofia MUA", "Shirin Jal", "Mi Hijabby Sabiha".
-- The logo lettering differs ("sofia musa", "Mi hijab by Sabiha"); that is recorded in
-- docs/MISSING_INFO.md for the owner to confirm, not renamed silently.
-- Specialty/bio lines are limited to what the logos and the client's price list state.
--
-- Updates only rows that still hold the earlier staging values, so it never overwrites
-- anything the owner has edited since. No deletes. Safe to re-run.
-- =====================================================================

update app.professionals p
   set slug = 'sofia-mua', display_name = 'Sofia MUA', logo_path = '/brand/pros/sofia-mua.webp', updated_at = now()
  from app.salons s
 where s.id = p.salon_id and s.slug = 'shahina-ahmed' and p.slug = 'sofia-musa'
   and not exists (select 1 from app.professionals x where x.salon_id = s.id and x.slug = 'sofia-mua');

update app.professionals p
   set slug = 'mi-hijabby-sabiha', display_name = 'Mi Hijabby Sabiha', logo_path = '/brand/pros/mi-hijabby-sabiha.webp',
       specialty = 'Hijab Styling', bio = null, updated_at = now()
  from app.salons s
 where s.id = p.salon_id and s.slug = 'shahina-ahmed' and p.slug = 'mi-hijab-by-sabiha'
   and not exists (select 1 from app.professionals x where x.salon_id = s.id and x.slug = 'mi-hijabby-sabiha');

update app.professionals p
   set specialty = 'Hair & Makeup Artist', updated_at = now()
  from app.salons s
 where s.id = p.salon_id and s.slug = 'shahina-ahmed' and p.slug = 'shirin-jal'
   and p.specialty in ('Hair & Makeup Artist, Hijab Stylist', 'Hair & Makeup Artist · Hijab Stylist');

update app.services v
   set name = 'Bridal', description = 'Bridal styling. Please send an enquiry.', updated_at = now()
  from app.professionals p join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
 where v.professional_id = p.id and p.slug = 'mi-hijabby-sabiha' and v.name = 'Bridal Hijab'
   and not exists (select 1 from app.services y where y.professional_id = p.id and lower(y.name) = 'bridal');

update app.services v
   set description = 'Hijab styling for parties and occasions.', updated_at = now()
  from app.professionals p join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
 where v.professional_id = p.id and p.slug = 'mi-hijabby-sabiha' and v.name = 'Party Hijab'
   and v.description = 'Modest hijab styling for parties and occasions.';
