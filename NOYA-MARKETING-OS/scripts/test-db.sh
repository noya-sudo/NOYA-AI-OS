#!/usr/bin/env bash
# NOYA Marketing OS — database test runner.
# Builds a throwaway database, applies the Supabase stub + every migration, runs the behavioural suite,
# then a real concurrency race (parallel executor claims on one execution). Never point this at a Supabase project.
#
# Usage: PGHOST=... PGPORT=... PGUSER=postgres scripts/test-db.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB="mos_test_$$"
P="psql -v ON_ERROR_STOP=1 -q -X"

cleanup() { $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

$P -d postgres -c "create database $DB" >/dev/null
$P -d "$DB" -f supabase/tests/00_supabase_stub.sql >/dev/null
for f in supabase/migrations/*.sql; do $P -d "$DB" -f "$f" 2>&1 | grep -v -e NOTICE -e '^$' || true; done

echo "== Behavioural suite"
$P -d "$DB" -f supabase/tests/10_phase1_test.sql 2>&1 | grep -E 'PASS|FAIL|ERROR|ALL PASSED' | sed -E 's/^(psql:[^ ]* )?(NOTICE: +)?//'

echo "== Concurrency race: 10 executors claim the same queued execution at once"
EXEC_ID=$($P -d "$DB" -At <<'SQL'
update gov.integration_registry set status = 'read_write', verified_at = now(), verification_evidence = '{"test":"race"}' where code = 'linkedin_ads';
update gov.service_identities set active = true where code in ('executor.ads','monitor.safety');
set role mos_monitor;
select (public.mos_monitor_safety_pause('monitor.safety', 'linkedin_ads.pause', 'race_campaign', 'race test') ->> 'execution_id');
SQL
)
EXEC_ID=$(echo "$EXEC_ID" | tail -1)
pids=()
for i in $(seq 1 10); do
  ( $P -d "$DB" -At -c "set role mos_executor; select public.mos_executor_claim('executor.ads', '$EXEC_ID') ->> 'ok';" > "/tmp/mos_race_$$_$i" 2>&1 ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
OKS=$(cat /tmp/mos_race_$$_* | grep -c '^true$' || true)
rm -f /tmp/mos_race_$$_*
CLAIMS=$($P -d "$DB" -At -c "select count(*) from gov.audit_log where action = 'execution.claim' and result = 'ok' and target_id = '$EXEC_ID'")
REFUSALS=$($P -d "$DB" -At -c "select count(*) from gov.audit_log where action = 'execution.claim' and result = 'refused' and target_id = '$EXEC_ID'")
if [ "$OKS" = "1" ] && [ "$CLAIMS" = "1" ]; then
  echo "PASS  26 race: exactly 1 of 10 parallel claims won ($REFUSALS refusals audited against this execution; others were skipped while locked)"
else
  echo "FAIL  26 race: $OKS successful claims, $CLAIMS audited ok claims"; exit 1
fi

echo "== Audit chain after the race"
BAD=$($P -d "$DB" -At -c "select count(*) from gov.verify_audit_chain()")
[ "$BAD" = "0" ] && echo "PASS  27 audit chain intact after concurrent writers" || { echo "FAIL  27 audit chain broken"; exit 1; }

echo "== Local equivalents of Supabase security advisors"
LINT=$($P -d "$DB" -At <<'SQL'
select 'function without pinned search_path: ' || p.oid::regprocedure
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname in ('gov','ops') or (n.nspname = 'public' and p.proname like 'mos\_%'))
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
union all
select 'table without RLS: ' || schemaname || '.' || tablename from pg_tables where schemaname in ('gov','ops') and not rowsecurity
union all
select 'table in exposed schema: public.' || tablename from pg_tables where schemaname = 'public' and tablename not like 't\_%'
union all
select 'view in exposed schema: public.' || viewname from pg_views where schemaname = 'public'
union all
select 'anon/authenticated privilege on ' || table_schema || '.' || table_name from information_schema.role_table_grants
 where grantee in ('anon','authenticated','service_role','mos_agent','mos_executor','mos_monitor','mos_dispatcher') and table_schema in ('gov','ops')
union all
select 'anon can execute ' || p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname like 'mos\_%' and has_function_privilege('anon', p.oid, 'execute');
SQL
)
if [ -z "$LINT" ]; then echo "PASS  28 advisor-equivalent lint: pinned search_path, RLS everywhere, nothing exposed, no anon execute"
else echo "FAIL  28 lint:"; echo "$LINT" | sed 's/^/  /'; exit 1; fi
