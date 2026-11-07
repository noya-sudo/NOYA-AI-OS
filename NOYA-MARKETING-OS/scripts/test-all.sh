#!/usr/bin/env bash
# NOYA Marketing OS — every automated check in one command.
#   secrets scan · HQ untouched · database suite + race · console build + headless browser checks
# Needs: node 18+, psql + a disposable Postgres 13+ (PGHOST/PGPORT/PGUSER), Playwright with Chromium.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "### Secrets";          node scripts/check-secrets.mjs
echo "### NOYA HQ";          scripts/check-hq-untouched.sh
echo "### Database";         scripts/test-db.sh
echo "### Console";          node console/build.mjs && node console/tests/ui.mjs
echo "ALL MARKETING OS CHECKS PASSED"
