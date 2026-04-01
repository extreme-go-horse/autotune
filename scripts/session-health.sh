#!/usr/bin/env bash
# session-health.sh — SessionStart quick health check
# Reports autotune status line. Always exits 0 (never blocks session start).
set -euo pipefail

AUTOTUNE_STATE_DIR="${AUTOTUNE_STATE_DIR:-$HOME/.claude/autotune}"
RULES_FILE="$AUTOTUNE_STATE_DIR/rules.json"
LASTRUN_FILE="$AUTOTUNE_STATE_DIR/last-run.json"
SCORES_FILE="$AUTOTUNE_STATE_DIR/scores.json"
CONFIG_FILE="$AUTOTUNE_STATE_DIR/config.json"

WARNINGS=0
MESSAGES=""

add_warning() {
  WARNINGS=$((WARNINGS + 1))
  if [ -n "$MESSAGES" ]; then
    MESSAGES="$MESSAGES, $1"
  else
    MESSAGES="$1"
  fi
}

# Check if state dir exists (first run?)
if [ ! -d "$AUTOTUNE_STATE_DIR" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"autotune: not configured — run `/autotune` for first setup"}}'
  exit 0
fi

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"autotune: jq not found — install jq for full diagnostics"}}'
  exit 0
fi

# Check rules.json integrity
if [ -f "$RULES_FILE" ]; then
  if ! jq empty "$RULES_FILE" 2>/dev/null; then
    add_warning "rules.json corrupted"
  fi
else
  add_warning "no rules.json"
fi

# Check stale run
STALE_DAYS=7
if [ -f "$CONFIG_FILE" ]; then
  STALE_DAYS=$(jq -r '.thresholds.stale_run_days // 7' "$CONFIG_FILE" 2>/dev/null) || STALE_DAYS=7
fi

if [ -f "$LASTRUN_FILE" ]; then
  LAST_TS=$(jq -r '.timestamp // empty' "$LASTRUN_FILE" 2>/dev/null) || LAST_TS=""
  if [ -n "$LAST_TS" ]; then
    # Calculate days since last run (portable: use date comparison)
    if command -v python3 >/dev/null 2>&1; then
      DAYS_AGO=$(LAST_TS="$LAST_TS" python3 -c "
import os, datetime
ts = os.environ['LAST_TS']
try:
    then = datetime.datetime.fromisoformat(ts.replace('Z', '+00:00'))
    now = datetime.datetime.now(datetime.timezone.utc)
    print((now - then).days)
except:
    print(999)
" 2>/dev/null) || DAYS_AGO=999
    else
      DAYS_AGO=0  # Can't check without python3
    fi
    if [ "$DAYS_AGO" -gt "$STALE_DAYS" ]; then
      add_warning "stale (last run ${DAYS_AGO}d ago)"
    fi
  fi
else
  add_warning "never run"
fi

# Get score
SCORE=""
if [ -f "$SCORES_FILE" ]; then
  SCORE=$(jq -r '.overall // empty' "$SCORES_FILE" 2>/dev/null) || SCORE=""
fi

# Build status line
if [ "$WARNINGS" -gt 0 ]; then
  if [ -n "$SCORE" ]; then
    STATUS="autotune: ${SCORE}/100 — ${WARNINGS} warning(s): ${MESSAGES}"
  else
    STATUS="autotune: ${WARNINGS} warning(s): ${MESSAGES}"
  fi
else
  if [ -n "$SCORE" ]; then
    STATUS="autotune: ${SCORE}/100 — healthy"
  else
    STATUS="autotune: healthy"
  fi
fi

jq -n -c --arg status "$STATUS" \
  '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$status}}'
exit 0
