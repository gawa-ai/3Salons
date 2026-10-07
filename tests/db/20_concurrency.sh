#!/usr/bin/env bash
# Two customers submit the SAME slot at the same moment from separate connections.
# Exactly one may win; the other must get slot_taken.
set -euo pipefail
DB=${1:-salontest}
H=${PGHOST:-/var/tmp/bospg}; P=${PGPORT:-55432}
PSQL="psql -h $H -p $P -U postgres -X -q -At -d $DB"
D=$($PSQL -c "select to_char((now() at time zone 'Europe/London')::date + 8, 'YYYY-MM-DD')")
SVC=$($PSQL -c "select v.id from app.services v join app.professionals p on p.id = v.professional_id where p.slug='shirin-jal' and v.name='Party Makeup'")
race() {
  $PSQL <<SQL
set role anon;
begin;
select public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','shirin-jal','service','$SVC',
  'date','$D','time','13:00','name','Racer $1','phone','0770090$1','idempotency_key','race-key-000000000$1'))->>'error';
select pg_sleep(1.5);
commit;
SQL
}
race 1111 > /tmp/race1.out & race 2222 > /tmp/race2.out & wait
R1=$(head -1 /tmp/race1.out); R2=$(head -1 /tmp/race2.out)
N=$($PSQL -c "select count(*) from app.bookings k join app.professionals p on p.id = k.professional_id where p.slug='shirin-jal' and k.status in ('pending','confirmed') and (k.starts_at at time zone 'Europe/London')::date = '$D'")
OUTCOME="${R1:-ok}/${R2:-ok}"
if [ "$N" = "1" ] && { [ "$OUTCOME" = "ok/slot_taken" ] || [ "$OUTCOME" = "slot_taken/ok" ]; }; then
  echo "PASS  112 concurrent requests for one slot: exactly one booking (results: '${R1:-ok}' / '${R2:-ok}')"
else
  echo "FAIL  112 concurrency: rows=$N r1='$R1' r2='$R2'"; exit 1
fi
