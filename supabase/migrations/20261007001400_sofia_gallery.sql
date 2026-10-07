-- Sofia MUA portfolio: static media committed under web/public/gallery/sofia-mua (site-relative paths).
-- Re-runnable: storage_path is unique, so repeats are no-ops.
insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text, caption, sort_order)
select p.salon_id, p.id, v.path, v.mt, v.alt, v.cap, v.ord
from app.professionals p
join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
cross join (values
  ('/gallery/sofia-mua/look-1.mp4',  'video', 'Bridal makeup in silver embellished veil with bold red lip, behind the scenes', 'Bridal glam', 10),
  ('/gallery/sofia-mua/photo-1.jpg', 'image', 'Three models in soft neutral outfits with glowing makeup', 'Soft glam', 20),
  ('/gallery/sofia-mua/look-2.mp4',  'video', 'Makeup and styling session in the salon', 'Behind the scenes', 30),
  ('/gallery/sofia-mua/photo-2.jpg', 'image', 'Three models in rust, ivory and chocolate looks', 'Editorial looks', 40),
  ('/gallery/sofia-mua/look-3.mp4',  'video', 'Rust turban styling with natural glam makeup', 'Turban styling', 50),
  ('/gallery/sofia-mua/look-4.mp4',  'video', 'Red and gold bridal look with traditional jewellery', 'Red bridal', 60),
  ('/gallery/sofia-mua/look-5.mp4',  'video', 'Hair-up styling for a party look', 'Hair-up styling', 70),
  ('/gallery/sofia-mua/look-6.mp4',  'video', 'Bridal hair-up with pearl detail', 'Bridal hair', 80)
) as v(path, mt, alt, cap, ord)
where p.slug = 'sofia-mua'
on conflict (storage_path) do nothing;
