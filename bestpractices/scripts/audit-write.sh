#!/usr/bin/env bash
# audit-write.sh — PostToolUse Write/Edit logger
# Appends to audit.jsonl when hot files are modified
# Always exits 0 (never blocks — this is post-action)
set -euo pipefail

AUTOTUNE_STATE_DIR="${AUTOTUNE_STATE_DIR:-$HOME/.claude/autotune}"
RULES_FILE="$AUTOTUNE_STATE_DIR/rules.json"
AUDIT_FILE="$AUTOTUNE_STATE_DIR/audit.jsonl"
CONFIG_FILE="$AUTOTUNE_STATE_DIR/config.json"

# No rules = no hot file list = nothing to log
if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Read input
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Extract just the filename for matching
FILENAME=$(basename "$FILE_PATH")

# Check if this is a hot file
IS_HOT=$(jq -r --arg name "$FILENAME" '.hot_files[]? | select(. == $name)' "$RULES_FILE" 2>/dev/null) || IS_HOT=""

if [ -z "$IS_HOT" ]; then
  exit 0  # Not a hot file, skip
fi

# Calculate content metrics
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null) || CONTENT=""
if [ -n "$CONTENT" ]; then
  LINE_COUNT=$(echo "$CONTENT" | wc -l | tr -d ' ')
  CHAR_COUNT=${#CONTENT}
  TOKEN_ESTIMATE=$((CHAR_COUNT / 3))
else
  LINE_COUNT=0
  CHAR_COUNT=0
  TOKEN_ESTIMATE=0
fi

# Get timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create state dir if needed
mkdir -p "$AUTOTUNE_STATE_DIR"

# _do_audit_write: append entry and rotate — called inside a lock when possible.
_do_audit_write() {
  # Append audit entry (use jq to safely build JSON — prevents injection via FILE_PATH)
  jq -n -c \
    --arg ts "$TS" \
    --arg file "$FILE_PATH" \
    --arg action "edit" \
    --argjson lines "$LINE_COUNT" \
    --argjson chars "$CHAR_COUNT" \
    --argjson tokens "$TOKEN_ESTIMATE" \
    '{"ts":$ts,"file":$file,"action":$action,"lines":$lines,"chars":$chars,"token_estimate":$tokens}' >> "$AUDIT_FILE"

  # Rotation check
  MAX_ENTRIES=10000
  if [ -f "$CONFIG_FILE" ]; then
    MAX_ENTRIES=$(jq -r '.thresholds.audit_max_entries // 10000' "$CONFIG_FILE" 2>/dev/null) || MAX_ENTRIES=10000
  fi

  CURRENT_LINES=$(wc -l < "$AUDIT_FILE" | tr -d ' ')
  if [ "$CURRENT_LINES" -gt "$MAX_ENTRIES" ]; then
    # Keep newest 50%
    KEEP=$((MAX_ENTRIES / 2))
    TAIL_TMP=$(mktemp)
    tail -n "$KEEP" "$AUDIT_FILE" > "$TAIL_TMP"
    mv "$TAIL_TMP" "$AUDIT_FILE"
  fi
}

# Wrap append + rotation in a lock to prevent corruption from concurrent hook invocations.
# Use flock (Linux) or lockf (macOS/BSD) when available; fall back to no-lock (best-effort).
LOCK_FILE="${AUDIT_FILE}.lock"
if command -v flock >/dev/null 2>&1; then
  # Linux: fd-based flock — Bash 3.2 compatible
  (
    flock 9
    _do_audit_write
  ) 9>"$LOCK_FILE"
elif command -v lockf >/dev/null 2>&1; then
  # macOS/BSD: lockf -k keeps the lock file after release
  lockf -k "$LOCK_FILE" bash -s <<EOF
$(declare -f _do_audit_write)
AUDIT_FILE=$(printf '%q' "$AUDIT_FILE")
CONFIG_FILE=$(printf '%q' "$CONFIG_FILE")
TS=$(printf '%q' "$TS")
FILE_PATH=$(printf '%q' "$FILE_PATH")
LINE_COUNT=$LINE_COUNT
CHAR_COUNT=$CHAR_COUNT
TOKEN_ESTIMATE=$TOKEN_ESTIMATE
_do_audit_write
EOF
else
  # No locking utility available — proceed without lock (best-effort)
  _do_audit_write
fi

exit 0
