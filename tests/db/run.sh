#!/usr/bin/env bash
# Rebuilds a THROWAWAY local database, applies every migration twice (re-run safety)
# and runs the test suite. Never point this at Supabase.
set -euo pipefail
cd "$(dirname "$0")"
H=${PGHOST:-/var/tmp/bospg}; P=${PGPORT:-55432}
PSQL="psql -h $H -p $P -U postgres -v ON_ERROR_STOP=1 -q -X"
DB=salontest
$PSQL -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$PSQL -d $DB -f 00_supabase_shim.sql >/dev/null
for pass in 1 2; do
  for f in ../../supabase/migrations/*.sql; do
    $PSQL -d $DB -f "$f" >/dev/null 2>&1 || { echo "MIGRATION FAILED (pass $pass): $f"; $PSQL -d $DB -f "$f"; exit 1; }
  done
done
echo "migrations applied twice: OK"
$PSQL -d $DB -f 10_tests.sql 2>&1 | grep -E "PASS|FAIL|ERROR|ALL_TESTS" | sed 's/^psql:[^ ]* //;s/NOTICE:  //'
bash ./20_concurrency.sh "$DB"
