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
# Also extract new_string (Edit tool uses {file_path, old_string, new_string} — content is always empty for Edit)
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null) || NEW_STRING=""

if [ -z "$FILE_PATH" ]; then
  exit 0  # No file path = not a file write, allow
fi

# Check block rules against file path (path rules only — no false positives from content mentions)
BLOCK_COUNT=$(jq -r '.block_rules | length' "$RULES_FILE" 2>/dev/null) || BLOCK_COUNT=0
i=0
while [ "$i" -lt "$BLOCK_COUNT" ]; do
  PATTERN=$(jq -r ".block_rules[$i].pattern" "$RULES_FILE")
  REASON=$(jq -r ".block_rules[$i].reason" "$RULES_FILE")

  # Check file path against pattern. Invalid regex causes grep to exit non-zero;
  # inside an if-condition set -e does not fire, and 2>/dev/null suppresses the error message.
  # Net effect: invalid regex = skip rule = allow through (fail-open, not fail-closed).
  if echo "$FILE_PATH" | grep -qE "$PATTERN" 2>/dev/null; then
    echo "autotune: BLOCKED — $REASON (matched: $FILE_PATH)" >&2
    exit 2
  fi

  i=$((i + 1))
done

# Check content/new_string against sabotage patterns only (separate list — not path patterns)
# This prevents path patterns like "credentials" from blocking docs that mention the word.
SABOTAGE_PATTERNS="DISABLE_PROMPT_CACHING|DISABLE_COST_OPTIMIZATION"

# Combine content and new_string for the check
COMBINED_CONTENT="${CONTENT}${NEW_STRING}"
if [ -n "$COMBINED_CONTENT" ]; then
  if echo "$COMBINED_CONTENT" | grep -qE "$SABOTAGE_PATTERNS" 2>/dev/null; then
    echo "autotune: BLOCKED — sabotage pattern detected in content (in $FILE_PATH)" >&2
    exit 2
  fi
fi

exit 0
