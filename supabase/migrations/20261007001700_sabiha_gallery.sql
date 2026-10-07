-- Mi Hijabby Sabiha portfolio: static media under web/public/gallery/mi-hijabby-sabiha. Re-runnable.
insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text, caption, sort_order)
select p.salon_id, p.id, v.path, 'video', v.alt, v.cap, v.ord
from app.professionals p
join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
cross join (values
  ('/gallery/mi-hijabby-sabiha/look-1.mp4', 'Bridal hijab styling in ivory and gold with gold jewellery', 'Ivory bridal hijab', 10),
  ('/gallery/mi-hijabby-sabiha/look-2.mp4', 'Sage green hijab with pearl and crystal embellishment', 'Sage hijab styling', 20),
  ('/gallery/mi-hijabby-sabiha/look-3.mp4', 'Black turban styling with soft glam makeup', 'Turban styling', 30),
  ('/gallery/mi-hijabby-sabiha/look-4.mp4', 'Bride in sage green dress and veil being dressed', 'Bridal dressing', 40),
  ('/gallery/mi-hijabby-sabiha/look-5.mp4', 'Red bridal hijab with matha patti, nose ring and mehndi', 'Red bridal hijab', 50),
  ('/gallery/mi-hijabby-sabiha/look-6.mp4', 'Red hijab with crystal headpiece and embellished outfit', 'Red hijab styling', 60),
  ('/gallery/mi-hijabby-sabiha/look-7.mp4', 'Dusky rose bridal hijab with silver embroidery', 'Rose bridal hijab', 70),
  ('/gallery/mi-hijabby-sabiha/look-8.mp4', 'Red and gold bridal hijab with nath and green stone jewellery', 'Red and gold bridal', 80)
) as v(path, alt, cap, ord)
where p.slug = 'mi-hijabby-sabiha'
on conflict (storage_path) do nothing;
