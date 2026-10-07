#!/usr/bin/env bash
# Tests supabase/manual/simplybooked_cleanup.sql on a THROWAWAY database that copies the BOS tables
# (column keys and every foreign-key / ON DELETE rule exactly as in BOOKING OS db/001_booking_os_schema.sql),
# plus an acq schema with the salon client row. A second business must survive untouched.
set -euo pipefail
cd "$(dirname "$0")"
P="psql -h ${PGHOST:-/var/tmp/bospg} -p ${PGPORT:-55432} -U postgres -X -q -v ON_ERROR_STOP=1"
$P -d postgres -c "drop database if exists sbclean" -c "create database sbclean" >/dev/null
$P -d sbclean >/dev/null <<'SQL'
create extension if not exists btree_gist;
create schema bos;
create table bos.businesses (id uuid primary key, slug text unique not null, name text not null);
create table bos.business_hours (business_id uuid not null references bos.businesses(id) on delete cascade,
  weekday smallint not null, opens time not null, closes time not null, primary key (business_id, weekday, opens));
create table bos.resources (id uuid primary key, business_id uuid not null references bos.businesses(id) on delete cascade, name text not null);
create table bos.services (id uuid primary key, business_id uuid not null references bos.businesses(id) on delete cascade, name text not null);
create table bos.service_resources (service_id uuid not null references bos.services(id) on delete cascade,
  resource_id uuid not null references bos.resources(id) on delete cascade, primary key (service_id, resource_id));
create table bos.blocked_times (id uuid primary key default gen_random_uuid(), business_id uuid not null references bos.businesses(id) on delete cascade,
  resource_id uuid references bos.resources(id) on delete cascade, starts_at timestamptz not null, ends_at timestamptz not null);
create table bos.customers (id uuid primary key, business_id uuid not null references bos.businesses(id) on delete cascade, phone text not null);
create table bos.bookings (id uuid primary key, business_id uuid not null references bos.businesses(id) on delete cascade,
  customer_id uuid not null references bos.customers(id), service_id uuid not null references bos.services(id),
  resource_id uuid not null references bos.resources(id), ref text not null);
create table bos.jobs (id bigint generated always as identity primary key, business_id uuid not null references bos.businesses(id) on delete cascade,
  booking_id uuid references bos.bookings(id) on delete cascade, kind text not null);
create table bos.messages (id bigint generated always as identity primary key, business_id uuid not null references bos.businesses(id) on delete cascade,
  customer_id uuid references bos.customers(id), booking_id uuid references bos.bookings(id) on delete set null, direction text not null);
create table bos.calls (id bigint generated always as identity primary key, business_id uuid references bos.businesses(id) on delete cascade,
  customer_id uuid references bos.customers(id), provider_call_id text not null unique);
create table bos.idempotency (business_id uuid not null references bos.businesses(id) on delete cascade, key text not null, tool text not null,
  primary key (business_id, key));
create schema acq;
create table acq.clients (id uuid primary key, name text);
create table acq.leads (id uuid primary key, name text);

-- SimplyBooked's own business (must survive) and the salon (to remove)
insert into bos.businesses values ('11111111-1111-4111-8111-111111111111','keep-barber','Keep Barber'),
                                  ('44444444-4444-4444-8444-444444444444','glam-studio','Glam Studio');
insert into bos.business_hours values ('11111111-1111-4111-8111-111111111111',1,'09:00','17:00'),('44444444-4444-4444-8444-444444444444',1,'10:00','18:00');
insert into bos.resources values ('a1111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111','Barber 1'),
                                 ('a4444444-4444-4444-8444-444444444441','44444444-4444-4444-8444-444444444444','Stylist 1');
insert into bos.services values ('c1111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111','Cut'),
                                ('c4444444-4444-4444-8444-444444444441','44444444-4444-4444-8444-444444444444','Party Hair');
insert into bos.service_resources values ('c1111111-1111-4111-8111-111111111111','a1111111-1111-4111-8111-111111111111'),
  ('c4444444-4444-4444-8444-444444444441','a4444444-4444-4444-8444-444444444441'),
  ('c1111111-1111-4111-8111-111111111111','a4444444-4444-4444-8444-444444444441');   -- the stray cross-business link
insert into bos.customers values ('e1111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111','+447700900001'),
                                 ('e4444444-4444-4444-8444-444444444441','44444444-4444-4444-8444-444444444444','+447700900004');
insert into bos.bookings values ('b1111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111','e1111111-1111-4111-8111-111111111111','c1111111-1111-4111-8111-111111111111','a1111111-1111-4111-8111-111111111111','KEEP01'),
                                ('b4444444-4444-4444-8444-444444444441','44444444-4444-4444-8444-444444444444','e4444444-4444-4444-8444-444444444441','c4444444-4444-4444-8444-444444444441','a4444444-4444-4444-8444-444444444441','GLAM01');
insert into bos.jobs (business_id, booking_id, kind) values ('11111111-1111-4111-8111-111111111111','b1111111-1111-4111-8111-111111111111','sms'),
                                                            ('44444444-4444-4444-8444-444444444444','b4444444-4444-4444-8444-444444444441','sms');
insert into bos.messages (business_id, customer_id, booking_id, direction) values ('44444444-4444-4444-8444-444444444444','e4444444-4444-4444-8444-444444444441','b4444444-4444-4444-8444-444444444441','out');
insert into bos.idempotency values ('44444444-4444-4444-8444-444444444444','k1','book'),('11111111-1111-4111-8111-111111111111','k2','book');
insert into acq.clients values ('dddddddd-4444-4444-8444-444444444444','Salon client'),('dddddddd-1111-4111-8111-111111111111','Keep client');
insert into acq.leads values ('eeeeeeee-1111-4111-8111-111111111111','Keep lead');
SQL

# 1) run the script exactly as written (STEP 3 ends in ROLLBACK): nothing may be deleted
$P -d sbclean -f ../../supabase/manual/simplybooked_cleanup.sql >/dev/null
r=$($P -d sbclean -At -c "select count(*) from bos.businesses")
[ "$r" = "2" ] && echo "PASS  C1 default run (ROLLBACK) deletes nothing" || { echo "FAIL C1 $r"; exit 1; }
r=$($P -d sbclean -At -c "select (select count(*) from salon_cleanup_backup.businesses)||','||(select count(*) from salon_cleanup_backup.service_resources)||','||(select count(*) from salon_cleanup_backup.bookings)||','||(select count(*) from salon_cleanup_backup.acq_clients)")
[ "$r" = "1,2,1,1" ] && echo "PASS  C2 backup holds the salon rows incl. the stray link and the acq client" || { echo "FAIL C2 $r"; exit 1; }

# 2) run it again with COMMIT (what JG does after checking the counts); backup step must be re-runnable
sed 's/^rollback;   -- change to COMMIT.*/commit;/' ../../supabase/manual/simplybooked_cleanup.sql > /tmp/sbclean_commit.sql
$P -d sbclean -f /tmp/sbclean_commit.sql >/dev/null
r=$($P -d sbclean -At -c "select (select count(*) from bos.businesses where id='44444444-4444-4444-8444-444444444444')+(select count(*) from bos.services where business_id='44444444-4444-4444-8444-444444444444')+(select count(*) from bos.bookings where business_id='44444444-4444-4444-8444-444444444444')+(select count(*) from bos.jobs where business_id='44444444-4444-4444-8444-444444444444')+(select count(*) from bos.messages where business_id='44444444-4444-4444-8444-444444444444')+(select count(*) from acq.clients where id='dddddddd-4444-4444-8444-444444444444')")
[ "$r" = "0" ] && echo "PASS  C3 COMMIT removes every salon row and the acq client" || { echo "FAIL C3 $r"; exit 1; }
r=$($P -d sbclean -At -c "select count(*) from bos.service_resources sr join bos.services s on s.id=sr.service_id join bos.resources r on r.id=sr.resource_id where s.business_id<>r.business_id")
[ "$r" = "0" ] && echo "PASS  C4 stray cross-business service link removed" || { echo "FAIL C4 $r"; exit 1; }
r=$($P -d sbclean -At -c "select (select count(*) from bos.businesses)||','||(select count(*) from bos.services)||','||(select count(*) from bos.service_resources)||','||(select count(*) from bos.bookings)||','||(select count(*) from bos.jobs)||','||(select count(*) from bos.idempotency)||','||(select count(*) from acq.clients)||','||(select count(*) from acq.leads)")
[ "$r" = "1,1,1,1,1,1,1,1" ] && echo "PASS  C5 SimplyBooked's own business, booking, jobs and acq rows untouched" || { echo "FAIL C5 $r"; exit 1; }
r=$($P -d sbclean -At -c "select count(*) from salon_cleanup_backup.businesses")
[ "$r" = "1" ] && echo "PASS  C6 backup still intact after the delete (create-if-not-exists did not overwrite it)" || { echo "FAIL C6 $r"; exit 1; }

# 3) a table that references the salon WITHOUT cascade makes the delete fail and roll back as a whole
$P -d sbclean -c "insert into bos.businesses values ('44444444-4444-4444-8444-444444444444','glam-studio','Glam Studio')" \
  -c "create table bos.unknown_ref (business_id uuid references bos.businesses(id))" \
  -c "insert into bos.unknown_ref values ('44444444-4444-4444-8444-444444444444')" >/dev/null
if $P -d sbclean -f /tmp/sbclean_commit.sql >/dev/null 2>&1; then echo "FAIL C7 delete should have failed"; exit 1; fi
r=$($P -d sbclean -At -c "select count(*) from bos.businesses where id='44444444-4444-4444-8444-444444444444'")
[ "$r" = "1" ] && echo "PASS  C7 unexpected non-cascading reference: delete refused, nothing half-removed" || { echo "FAIL C7 $r"; exit 1; }
$P -d postgres -c "drop database sbclean" >/dev/null
echo CLEANUP_TESTS_PASSED
