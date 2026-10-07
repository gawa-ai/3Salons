-- Restore Shahina Ahmed as a public professional (first card) and add her portfolio. Re-runnable, non-destructive.
insert into app.professionals (salon_id, slug, display_name, short_name, specialty, color, sort_order)
select s.id, 'shahina-ahmed', 'Shahina Ahmed', 'Shahina', 'Makeup Artist', 'bronze', 1
  from app.salons s
 where s.slug = 'shahina-ahmed'
   and not exists (select 1 from app.professionals x where x.salon_id = s.id and x.slug = 'shahina-ahmed');

insert into app.services (salon_id, professional_id, name, category, duration_min, buffer_min, price_pence, price_kind, bookable_online, details_confirmed, sort_order)
select p.salon_id, p.id, v.name, v.cat, v.dur, 15, v.price, v.kind, v.online, false, v.ord
  from app.professionals p
 cross join (values ('Party Hair','hair',60,5000,'fixed',true,1), ('Party Makeup','makeup',60,5000,'fixed',true,2),
                    ('Party Hair & Makeup','hair_makeup',120,9500,'fixed',true,3), ('Bridal','bridal',60,null::int,'enquire',false,4)) v(name,cat,dur,price,kind,online,ord)
 where p.slug = 'shahina-ahmed'
   and not exists (select 1 from app.services x where x.professional_id = p.id);

update app.professionals
   set active = true, is_public = true, online_booking = true,
       specialty = 'Makeup Artist',
       instagram_url = 'https://www.instagram.com/shahinaahmedmua/',
       logo_path = '/brand/pros/shahina-ahmed.webp', sort_order = 1, updated_at = now()
 where slug = 'shahina-ahmed';

update app.services s set active = true
  from app.professionals p
 where p.id = s.professional_id and p.slug = 'shahina-ahmed';

insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text, caption, sort_order)
select p.salon_id, p.id, v.path, v.kind, v.alt, v.cap, v.ord
from app.professionals p
join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
cross join (values
  ('/gallery/shahina-ahmed/look-2.mp4', 'video', 'Soft blush hijab look with glowing makeup', 'Soft glam hijab', 10),
  ('/gallery/shahina-ahmed/look-3.mp4', 'video', 'Close-up of mauve eye makeup with a deep plum hijab', 'Mauve glam', 20),
  ('/gallery/shahina-ahmed/photo-9.jpg', 'image', 'Bridal look in burgundy velvet with a gold maang tikka', 'Burgundy bridal', 30),
  ('/gallery/shahina-ahmed/photo-13.jpg', 'image', 'Bride smiling in a white lace veil', 'White veil bride', 40),
  ('/gallery/shahina-ahmed/photo-4.jpg', 'image', 'Soft glam with loose waves and a grey embroidered outfit', 'Soft glam waves', 50),
  ('/gallery/shahina-ahmed/photo-3.jpg', 'image', 'Vintage-inspired turban look with a bold red lip', 'Retro glam', 60),
  ('/gallery/shahina-ahmed/photo-2.jpg', 'image', 'Glowing glam portrait with pink flowers behind', 'Fresh glam', 70),
  ('/gallery/shahina-ahmed/photo-6.jpg', 'image', 'Bride in a burgundy lehenga with her mother', 'Bride and mum', 80),
  ('/gallery/shahina-ahmed/photo-7.jpg', 'image', 'Two guests in colourful lehengas at the SA studio wall', 'Wedding guests', 90),
  ('/gallery/shahina-ahmed/photo-12.jpg', 'image', 'Two guests styled for a celebration, one in a pink saree', 'Celebration styling', 100),
  ('/gallery/shahina-ahmed/photo-1.jpg', 'image', 'Two guests styled in blush and mint', 'Party looks', 110),
  ('/gallery/shahina-ahmed/photo-10.jpg', 'image', 'Burgundy bridal makeup with a gold headpiece, seated', 'Bridal detail', 120),
  ('/gallery/shahina-ahmed/photo-14.jpg', 'image', 'Bridal makeup with a gold headpiece and ruffled velvet outfit', 'Bridal portrait', 130),
  ('/gallery/shahina-ahmed/photo-11.jpg', 'image', 'Soft glam with long waves and a grey embroidered outfit', 'Glam waves', 140),
  ('/gallery/shahina-ahmed/photo-8.jpg', 'image', 'Close-up of a vintage turban look with winged liner', 'Retro close-up', 150),
  ('/gallery/shahina-ahmed/photo-5.jpg', 'image', 'Behind the scenes at the studio with the SA logo', 'At the studio', 160),
  ('/gallery/shahina-ahmed/look-1.mp4', 'video', 'Shahina Ahmed makeup artist logo reveal', 'Shahina Ahmed', 170)
) as v(path, kind, alt, cap, ord)
where p.slug = 'shahina-ahmed'
on conflict (storage_path) do nothing;
