-- Shirin Jal portfolio: static media under web/public/gallery/shirin-jal. Re-runnable (storage_path unique).
insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text, caption, sort_order)
select p.salon_id, p.id, v.path, 'video', v.alt, v.cap, v.ord
from app.professionals p
join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
cross join (values
  ('/gallery/shirin-jal/look-1.mp4', 'Bridal makeup being applied in the salon', 'Bridal makeup', 10),
  ('/gallery/shirin-jal/look-2.mp4', 'Collage of hijab and bridal styling looks', 'Hijab styling', 20),
  ('/gallery/shirin-jal/look-3.mp4', 'Soft textured hair-up in a sequin outfit', 'Hair-up styling', 30),
  ('/gallery/shirin-jal/look-4.mp4', 'Glam makeup portrait', 'Glam makeup', 40),
  ('/gallery/shirin-jal/look-5.mp4', 'Bridal look with smoky eyes and silver embellished dupatta', 'Bridal glam', 50),
  ('/gallery/shirin-jal/look-6.mp4', 'Bride in a pink lehenga on a stone staircase', 'Bridal styling', 60),
  ('/gallery/shirin-jal/look-7.mp4', 'Smoky eye makeup with gold earrings', 'Smoky eyes', 70),
  ('/gallery/shirin-jal/look-8.mp4', 'Bridal hair and makeup in a red outfit', 'Bridal hair', 80)
) as v(path, alt, cap, ord)
where p.slug = 'shirin-jal'
on conflict (storage_path) do nothing;
