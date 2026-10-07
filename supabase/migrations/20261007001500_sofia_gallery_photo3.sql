insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text, caption, sort_order)
select p.salon_id, p.id, '/gallery/sofia-mua/photo-3.jpg', 'image', 'Light-blue hijab with pearl and crystal headpiece and embellished outfit', 'Occasion hijab styling', 90
from app.professionals p join app.salons s on s.id = p.salon_id and s.slug = 'shahina-ahmed'
where p.slug = 'sofia-mua'
on conflict (storage_path) do nothing;
