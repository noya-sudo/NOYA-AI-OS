#!/usr/bin/env bash
# Proves Marketing OS work has not modified NOYA HQ while both live in the NOYA-AI-OS repository.
# Compares everything outside NOYA-MARKETING-OS/ against the last commit before Marketing OS existed.
# Usage: scripts/check-hq-untouched.sh [base-commit]   (default: 123cd73, the HQ head when Phase 0 started)
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
if [ ! -d NOYA-MARKETING-OS ]; then echo "Standalone repository: no HQ files present. PASS"; exit 0; fi
BASE="${1:-123cd73}"
CHANGED=$( { git diff --name-only "$BASE" HEAD -- . ':(exclude)NOYA-MARKETING-OS'; \
             git diff --name-only -- . ':(exclude)NOYA-MARKETING-OS'; \
             git ls-files --others --exclude-standard -- . ':(exclude)NOYA-MARKETING-OS'; } | sort -u )
if [ -n "$CHANGED" ]; then
  echo "FAIL  HQ files changed since $BASE:"; echo "$CHANGED" | sed 's/^/  /'; exit 1
fi
echo "PASS  HQ untouched: no file outside NOYA-MARKETING-OS/ differs from $BASE (committed, staged, unstaged or untracked)"
