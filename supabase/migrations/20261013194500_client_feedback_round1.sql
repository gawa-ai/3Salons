-- =====================================================================
-- Client feedback, round 1 (Shahina, WhatsApp 2026-10-13). Re-runnable, non-destructive.
--   * Homepage headline: "Your Beauty. Your Style. Your Special Moment."
--   * Address confirmed by the client: 199 Preston New Road, Blackburn BB2 6BN
--   * Sofia's name is "Sofia Musa" (client confirmed). The slug stays 'sofia-mua' so existing
--     links, logo and gallery paths keep working.
--   * Gallery: only the four photos the client sent are public for now. Everything else is
--     UNPUBLISHED (published = false), never deleted, so it can be switched back on later.
--     Only the static, committed media (paths starting with '/gallery/') is touched, so photos
--     the owner uploads later through Studio -> Gallery are never hidden by a re-run.
-- =====================================================================

-- Headline: only replaces the earlier staging headlines, so an owner-edited headline survives.
update app.salons
   set tagline = 'Your Beauty. Your Style. Your Special Moment.', updated_at = now()
 where slug = 'shahina-ahmed'
   and (tagline is null
        or tagline in ('Your moment. Your signature look.', 'Hair, makeup and hijab styling for the moments that matter.'));

-- Address: only fills a blank, never overwrites one the owner typed.
update app.salons
   set address = '199 Preston New Road, Blackburn, BB2 6BN', updated_at = now()
 where slug = 'shahina-ahmed' and (address is null or btrim(address) = '');

-- Sofia's display name (only the original label is replaced).
update app.professionals p
   set display_name = 'Sofia Musa', updated_at = now()
  from app.salons s
 where s.id = p.salon_id and s.slug = 'shahina-ahmed'
   and p.slug = 'sofia-mua' and p.display_name = 'Sofia MUA';

-- The four photos the client sent (one collage per artist).
insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text, caption, published, sort_order)
select p.salon_id, p.id, v.path, 'image', v.alt, v.cap, true, 10
  from app.professionals p
  join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
  join (values
    ('shahina-ahmed',     '/gallery/shahina-ahmed/featured-1.jpg',     'Four looks in soft blush hijabs with glowing makeup and pearl details', null),
    ('sofia-mua',         '/gallery/sofia-mua/featured-1.jpg',         'Four close-ups of bronze, glowing makeup with gold jewellery', null),
    ('shirin-jal',        '/gallery/shirin-jal/featured-1.jpg',        'Four close-ups of soft glam makeup with loose waves and gold earrings', null),
    ('mi-hijabby-sabiha', '/gallery/mi-hijabby-sabiha/featured-1.jpg', 'Four looks in chocolate brown turbans with leather jackets and a bold red lip', 'Makeup by Shahina Ahmed, hijab by Sabiha')
  ) as v(slug, path, alt, cap) on v.slug = p.slug
on conflict (storage_path) do update set published = true;

-- Hide the earlier static gallery items (kept in the table, not deleted).
update app.gallery_items g
   set published = false
  from app.salons s
 where s.id = g.salon_id and s.slug = 'shahina-ahmed'
   and g.storage_path like '/gallery/%'
   and g.storage_path not like '%/featured-1.jpg'
   and g.published;
