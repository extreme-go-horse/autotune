#!/usr/bin/env bash
# gate-mechanical.sh — PreToolUse Write/Edit guard
# Reads rules.json, blocks writes to sensitive/bloated files
# Exit 0 = allow, Exit 2 = block (message on stderr)
set -euo pipefail

AUTOTUNE_STATE_DIR="${AUTOTUNE_STATE_DIR:-$HOME/.claude/autotune}"
RULES_FILE="$AUTOTUNE_STATE_DIR/rules.json"

# No rules file = no enforcement (first run before /autotune)
if [ ! -f "$RULES_FILE" ]; then
  exit 0
fi

# Read input from stdin
INPUT=$(cat)

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  exit 0  # No jq = can't enforce, allow through
fi

# Validate schema version
SCHEMA_VERSION=$(jq -r '.schema_version // 0' "$RULES_FILE" 2>/dev/null) || SCHEMA_VERSION=0
if [ "$SCHEMA_VERSION" != "1" ]; then
  echo "autotune: rules.json schema mismatch (got v${SCHEMA_VERSION}, expected v1) — run \`/autotune\` to recompile" >&2
  exit 2
fi

# Extract file path and content from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null) || CONTENT=""

if [ -z "$FILE_PATH" ]; then
  exit 0  # No file path = not a file write, allow
fi

# Check block rules against file path
BLOCK_COUNT=$(jq -r '.block_rules | length' "$RULES_FILE" 2>/dev/null) || BLOCK_COUNT=0
i=0
while [ "$i" -lt "$BLOCK_COUNT" ]; do
  PATTERN=$(jq -r ".block_rules[$i].pattern" "$RULES_FILE")
  REASON=$(jq -r ".block_rules[$i].reason" "$RULES_FILE")

  # Check file path against pattern
  if echo "$FILE_PATH" | grep -qE "$PATTERN"; then
    echo "autotune: BLOCKED — $REASON (matched: $FILE_PATH)" >&2
    exit 2
  fi

  # Check content against pattern (for sabotage detection)
  if [ -n "$CONTENT" ] && echo "$CONTENT" | grep -qE "$PATTERN"; then
    echo "autotune: BLOCKED — $REASON (content match in $FILE_PATH)" >&2
    exit 2
  fi

  i=$((i + 1))
done

exit 0
