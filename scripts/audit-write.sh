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

# Append audit entry
printf '{"ts":"%s","file":"%s","action":"edit","lines":%d,"chars":%d,"token_estimate":%d}\n' \
  "$TS" "$FILE_PATH" "$LINE_COUNT" "$CHAR_COUNT" "$TOKEN_ESTIMATE" >> "$AUDIT_FILE"

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

exit 0
