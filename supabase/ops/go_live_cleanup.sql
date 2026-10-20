-- GO-LIVE CLEANUP: removes test bookings, clients, enquiries and their messages/audit rows.
-- NOT a migration (kept out of supabase/migrations on purpose). Run by hand, once, after JG says OK.
-- It first copies everything into schema "backup_golive" so it can be restored. Nothing else is touched:
-- services, hours, artists, gallery, bank details, logins and settings stay exactly as they are.
-- STEP 1: run the whole file. STEP 2: check the counts it prints. STEP 3 (only when happy): drop schema backup_golive cascade;
begin;

create schema if not exists backup_golive;
create table backup_golive.bookings      as select * from app.bookings;
create table backup_golive.clients       as select * from app.clients;
create table backup_golive.enquiries     as select * from app.enquiries;
create table backup_golive.notifications as select * from app.notifications;
create table backup_golive.audit_log     as select * from app.audit_log;
revoke all on schema backup_golive from public, anon, authenticated;

-- notifications go with their bookings/enquiries (cascade); remove any left over, then the rest
delete from app.notifications;
delete from app.bookings;
delete from app.enquiries;
delete from app.clients;
delete from app.audit_log;

select (select count(*) from backup_golive.bookings) as backed_up_bookings,
       (select count(*) from backup_golive.clients) as backed_up_clients,
       (select count(*) from app.bookings) as bookings_left,
       (select count(*) from app.clients) as clients_left,
       (select count(*) from app.enquiries) as enquiries_left;
commit;

-- RESTORE (only if needed), in this order:
--   insert into app.clients       select * from backup_golive.clients;
--   insert into app.bookings      select * from backup_golive.bookings;
--   insert into app.enquiries     select * from backup_golive.enquiries;
--   insert into app.notifications overriding system value select * from backup_golive.notifications;
--   insert into app.audit_log overriding system value select * from backup_golive.audit_log;
