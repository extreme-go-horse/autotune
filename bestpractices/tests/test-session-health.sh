#!/usr/bin/env bash
# Tests for session-health.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
setup_tmpdir

HEALTH="$SCRIPT_DIR/../scripts/session-health.sh"

# --- Test: healthy state ---
STATE_DIR="$TEST_TMPDIR/healthy"
mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/rules.json" << 'RULES'
{"schema_version": 1, "hot_files": [], "block_rules": [], "warn_rules": []}
RULES
cat > "$STATE_DIR/last-run.json" << LASTRUN
{"timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")", "status": "ok"}
LASTRUN
cat > "$STATE_DIR/scores.json" << 'SCORES'
{"overall": 85, "areas": {}}
SCORES

CODE=0
OUTPUT=$(AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$HEALTH" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "healthy state exits 0"
assert_contains "$OUTPUT" "autotune" "output mentions autotune"

# --- Test: stale run warning ---
STATE_DIR="$TEST_TMPDIR/stale"
mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/rules.json" << 'RULES'
{"schema_version": 1, "hot_files": [], "block_rules": [], "warn_rules": []}
RULES
cat > "$STATE_DIR/last-run.json" << 'LASTRUN'
{"timestamp": "2025-01-01T00:00:00Z", "status": "ok"}
LASTRUN
cat > "$STATE_DIR/config.json" << 'CONFIG'
{"version": 1, "thresholds": {"stale_run_days": 7}}
CONFIG

CODE=0
OUTPUT=$(AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$HEALTH" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "stale run still exits 0"
assert_contains "$OUTPUT" "stale" "stale warning shown"

# --- Test: missing state dir = first run ---
CODE=0
OUTPUT=$(AUTOTUNE_STATE_DIR="$TEST_TMPDIR/nonexistent" bash "$HEALTH" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "missing state dir exits 0"
assert_contains "$OUTPUT" "autotune" "first run message shown"

# --- Test: broken rules.json ---
STATE_DIR="$TEST_TMPDIR/broken"
mkdir -p "$STATE_DIR"
echo "not json" > "$STATE_DIR/rules.json"

CODE=0
OUTPUT=$(AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$HEALTH" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "broken rules.json exits 0"
assert_contains "$OUTPUT" "warning" "broken rules warning shown"

print_results
