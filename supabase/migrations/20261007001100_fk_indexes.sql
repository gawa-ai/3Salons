-- Covering indexes for foreign keys (Supabase performance advisor 0001). Additive only. Safe to re-run.
create index if not exists bookings_pro_client      on app.bookings (professional_id, client_id);
create index if not exists bookings_pro_service     on app.bookings (professional_id, service_id);
create index if not exists bookings_salon_pro       on app.bookings (salon_id, professional_id);
create index if not exists bookings_created_by      on app.bookings (created_by);
create index if not exists clients_salon_pro        on app.clients (salon_id, professional_id);
create index if not exists services_salon_pro       on app.services (salon_id, professional_id);
create index if not exists gallery_salon_pro        on app.gallery_items (salon_id, professional_id);
create index if not exists gallery_created_by       on app.gallery_items (created_by);
create index if not exists invitations_salon_pro    on app.invitations (salon_id, professional_id);
create index if not exists invitations_created_by   on app.invitations (created_by);
create index if not exists invitations_used_by      on app.invitations (used_by);
create index if not exists notifications_booking    on app.notifications (booking_id);
create index if not exists notifications_enquiry    on app.notifications (enquiry_id);
create index if not exists time_off_created_by      on app.time_off (created_by);
