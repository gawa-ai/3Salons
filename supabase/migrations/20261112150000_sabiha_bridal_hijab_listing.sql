-- Sabiha's public service list: show "Bridal Hijab, from £100 (plus travel), 1 hr" under Party Hijab.
-- It stays enquiry-only (not bookable online); the card links to the bridal enquiry form. Re-runnable.
update app.services v
   set name = 'Bridal Hijab',
       description = 'Bridal hijab styling. Please send an enquiry.',
       duration_min = 60, price_pence = 10000, price_kind = 'from', bookable_online = false,
       updated_at = now()
  from app.professionals p join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
 where v.professional_id = p.id and p.slug = 'mi-hijabby-sabiha' and v.category = 'bridal'
   and not exists (select 1 from app.services y
                    where y.professional_id = p.id and lower(y.name) = 'bridal hijab' and y.id <> v.id);
