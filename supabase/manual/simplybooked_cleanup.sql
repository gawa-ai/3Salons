-- =====================================================================
-- SIMPLYBOOKED PROD CLEANUP: remove the salon rows that were seeded there by mistake.
-- Run by JG only, in the SimplyBooked Supabase SQL Editor (project jdqidbgjlttojhseyugr).
-- It does NOT touch the new "3 Salons" project.
--
-- What it removes (and nothing else):
--   * bos.businesses  44444444-4444-4444-8444-444444444444 (the "glam-studio" salon) and every row that
--     cascades from it (hours, stylists, services, service links, customers, bookings, jobs, messages, calls,
--     idempotency). That includes the stray service_resources row from the ID collision, because one side
--     of that link belongs to the salon.
--   * the acq client row dddddddd-4444-4444-8444-444444444444 (found by id in whichever acq table holds it).
--
-- Safety:
--   * STEP 1 is read-only. Run it alone first and check the counts.
--   * STEP 2 copies every affected row into schema salon_cleanup_backup before anything is deleted.
--   * STEP 3 runs in a transaction that ends in ROLLBACK. Only after the counts look right,
--     change the last line to COMMIT and run STEP 3 again.
--   * If anything else in SimplyBooked still points at the salon without ON DELETE CASCADE,
--     the delete fails and the whole transaction is undone (nothing half-deleted).
--
-- Tested locally on a copy of the BOS schema with a second business that must survive.
-- See tests/db/30_simplybooked_cleanup.sh.
-- =====================================================================


-- ---------------------------------------------------------------- STEP 1: preview (read-only)
select 'bos.businesses' as table_name, count(*) from bos.businesses where id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.business_hours', count(*) from bos.business_hours where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.resources', count(*) from bos.resources where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.services', count(*) from bos.services where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.service_resources (salon side)', count(*) from bos.service_resources sr
  where sr.service_id in (select id from bos.services where business_id = '44444444-4444-4444-8444-444444444444')
     or sr.resource_id in (select id from bos.resources where business_id = '44444444-4444-4444-8444-444444444444')
union all select 'bos.service_resources (cross-business = stray)', count(*) from bos.service_resources sr
  join bos.services s on s.id = sr.service_id join bos.resources r on r.id = sr.resource_id
  where s.business_id <> r.business_id
union all select 'bos.blocked_times', count(*) from bos.blocked_times where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.customers', count(*) from bos.customers where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.bookings', count(*) from bos.bookings where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.jobs', count(*) from bos.jobs where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.messages', count(*) from bos.messages where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.calls', count(*) from bos.calls where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'bos.idempotency', count(*) from bos.idempotency where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'OTHER businesses (must stay)', count(*) from bos.businesses where id <> '44444444-4444-4444-8444-444444444444';

-- acq tables that contain the salon client row (read-only search by id)
select c.table_schema || '.' || c.table_name as acq_table
from information_schema.columns c
where c.table_schema = 'acq' and c.column_name = 'id' and c.data_type = 'uuid'
  and (xpath('/row/n/text()', query_to_xml(format(
        'select count(*) as n from %I.%I where id = %L', c.table_schema, c.table_name,
        'dddddddd-4444-4444-8444-444444444444'), false, true, '')))[1]::text::int > 0;


-- ---------------------------------------------------------------- STEP 2: backup (copies only, no deletes)
create schema if not exists salon_cleanup_backup;
create table if not exists salon_cleanup_backup.businesses as select * from bos.businesses where id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.business_hours as select * from bos.business_hours where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.resources as select * from bos.resources where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.services as select * from bos.services where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.service_resources as select sr.* from bos.service_resources sr
  where sr.service_id in (select id from bos.services where business_id = '44444444-4444-4444-8444-444444444444')
     or sr.resource_id in (select id from bos.resources where business_id = '44444444-4444-4444-8444-444444444444');
create table if not exists salon_cleanup_backup.blocked_times as select * from bos.blocked_times where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.customers as select * from bos.customers where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.bookings as select * from bos.bookings where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.jobs as select * from bos.jobs where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.messages as select * from bos.messages where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.calls as select * from bos.calls where business_id = '44444444-4444-4444-8444-444444444444';
create table if not exists salon_cleanup_backup.idempotency as select * from bos.idempotency where business_id = '44444444-4444-4444-8444-444444444444';
do $$
declare t record;
begin
  for t in select c.table_name from information_schema.columns c
           where c.table_schema = 'acq' and c.column_name = 'id' and c.data_type = 'uuid' loop
    execute format('create table if not exists salon_cleanup_backup.%I as select * from acq.%I where id = %L',
                   'acq_' || t.table_name, t.table_name, 'dddddddd-4444-4444-8444-444444444444');
  end loop;
end $$;
-- keep the backup private
revoke all on schema salon_cleanup_backup from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema salon_cleanup_backup from anon, authenticated';
  end if;
end $$;


-- ---------------------------------------------------------------- STEP 3: delete (ROLLBACK until you are sure)
begin;
delete from bos.businesses where id = '44444444-4444-4444-8444-444444444444';
do $$
declare t record; n int;
begin
  for t in select c.table_name from information_schema.columns c
           where c.table_schema = 'acq' and c.column_name = 'id' and c.data_type = 'uuid' loop
    execute format('delete from acq.%I where id = %L', t.table_name, 'dddddddd-4444-4444-8444-444444444444');
    get diagnostics n = row_count;
    if n > 0 then raise notice 'deleted % row(s) from acq.%', n, t.table_name; end if;
  end loop;
end $$;
-- after-check: everything below must be 0 except "OTHER businesses"
select 'salon business left' as check_name, count(*) from bos.businesses where id = '44444444-4444-4444-8444-444444444444'
union all select 'salon services left', count(*) from bos.services where business_id = '44444444-4444-4444-8444-444444444444'
union all select 'cross-business service links left', count(*) from bos.service_resources sr
  join bos.services s on s.id = sr.service_id join bos.resources r on r.id = sr.resource_id where s.business_id <> r.business_id
union all select 'OTHER businesses (unchanged)', count(*) from bos.businesses;
rollback;   -- change to COMMIT only after the counts above look right
