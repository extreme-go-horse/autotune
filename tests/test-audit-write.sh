#!/usr/bin/env bash
# Tests for audit-write.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
setup_tmpdir

AUDIT="$SCRIPT_DIR/../scripts/audit-write.sh"

# Create state dir
STATE_DIR="$TEST_TMPDIR/autotune"
mkdir -p "$STATE_DIR"

# Create rules.json with hot_files
cat > "$STATE_DIR/rules.json" << 'RULES'
{
  "schema_version": 1,
  "hot_files": ["CLAUDE.md", "settings.json", "MEMORY.md"],
  "block_rules": [],
  "warn_rules": []
}
RULES

# Create config.json with audit_max_entries
cat > "$STATE_DIR/config.json" << 'CONFIG'
{
  "version": 1,
  "thresholds": { "audit_max_entries": 5 }
}
CONFIG

# --- Test: hot file write is logged ---
echo '{"tool_input":{"file_path":"/home/user/.claude/CLAUDE.md","content":"line1\nline2\nline3"}}' | \
  AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$AUDIT" 2>/dev/null || true
assert_file_exists "$STATE_DIR/audit.jsonl" "audit.jsonl created"
LAST_LINE=$(tail -1 "$STATE_DIR/audit.jsonl")
assert_contains "$LAST_LINE" "CLAUDE.md" "audit entry contains filename"
assert_contains "$LAST_LINE" '"action":"edit"' "audit entry has action"

# --- Test: non-hot file is NOT logged ---
BEFORE=$(wc -l < "$STATE_DIR/audit.jsonl" | tr -d ' ')
echo '{"tool_input":{"file_path":"/tmp/random.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$AUDIT" 2>/dev/null || true
AFTER=$(wc -l < "$STATE_DIR/audit.jsonl" | tr -d ' ')
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$BEFORE" -eq "$AFTER" ]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} non-hot file not logged\n"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}FAIL${NC} non-hot file was logged\n"
fi

# --- Test: rotation at max entries ---
for i in 1 2 3 4 5 6; do
  echo "{\"tool_input\":{\"file_path\":\"/home/.claude/CLAUDE.md\",\"content\":\"line$i\"}}" | \
    AUTOTUNE_STATE_DIR="$STATE_DIR" bash "$AUDIT" 2>/dev/null || true
done
LINE_COUNT=$(wc -l < "$STATE_DIR/audit.jsonl" | tr -d ' ')
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$LINE_COUNT" -le 5 ]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} audit rotation works (lines: %d <= 5)\n" "$LINE_COUNT"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}FAIL${NC} audit rotation failed (lines: %d > 5)\n" "$LINE_COUNT"
fi

# --- Test: missing rules.json = no logging ---
CODE=0
echo '{"tool_input":{"file_path":"/home/.claude/CLAUDE.md","content":"x"}}' | \
  AUTOTUNE_STATE_DIR="$TEST_TMPDIR/nonexistent" bash "$AUDIT" 2>/dev/null || CODE=$?
assert_exit_code 0 "$CODE" "missing rules.json exits cleanly"

print_results
