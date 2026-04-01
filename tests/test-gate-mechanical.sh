#!/usr/bin/env bash
# Tests for gate-mechanical.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
setup_tmpdir

GATE="$SCRIPT_DIR/../scripts/gate-mechanical.sh"

# Create a minimal rules.json for tests
RULES_DIR="$TEST_TMPDIR/autotune"
mkdir -p "$RULES_DIR"
cat > "$RULES_DIR/rules.json" << 'RULES'
{
  "schema_version": 1,
  "compiled_at": "2026-04-01T00:00:00Z",
  "hot_files": ["CLAUDE.md", "settings.json"],
  "block_rules": [
    {"pattern": "\\.env(\\..+)?$", "reason": "Sensitive file"},
    {"pattern": "credentials", "reason": "Credentials file"},
    {"pattern": "secrets/", "reason": "Secrets directory"},
    {"pattern": "DISABLE_PROMPT_CACHING", "reason": "Caching sabotage"}
  ],
  "warn_rules": [
    {"file": "CLAUDE.md", "max_lines": 10}
  ]
}
RULES

# --- Test: normal file passes ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/foo.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "normal file passes"

# --- Test: .env file blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/.env","content":"SECRET=123"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" ".env file blocked"
assert_contains "$OUTPUT" "Sensitive file" ".env block message"

# --- Test: .env.local file blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/.env.local","content":"SECRET=123"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" ".env.local file blocked"

# --- Test: .env.production blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/project/.env.production","content":"x"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" ".env.production blocked"

# --- Test: credentials file blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/user/credentials.json","content":"{}"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "credentials file blocked"

# --- Test: secrets/ directory blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/project/secrets/key.pem","content":"-----"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "secrets/ directory blocked"

# --- Test: caching sabotage blocked ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/home/.claude/settings.json","content":"DISABLE_PROMPT_CACHING=1"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "caching sabotage blocked"
assert_contains "$OUTPUT" "Caching sabotage" "caching sabotage message"

# --- Test: missing rules.json passes (no rules = no blocks) ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/foo.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$TEST_TMPDIR/nonexistent" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "missing rules.json passes gracefully"

# --- Test: wrong schema version blocks ---
mkdir -p "$TEST_TMPDIR/bad_rules"
cat > "$TEST_TMPDIR/bad_rules/rules.json" << 'RULES'
{"schema_version": 99}
RULES
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/foo.py","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$TEST_TMPDIR/bad_rules" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 2 "$CODE" "wrong schema version blocks"
assert_contains "$OUTPUT" "schema mismatch" "schema mismatch message"

# --- Test: envfile.txt not blocked (false positive check) ---
CODE=0
OUTPUT=$(echo '{"tool_input":{"file_path":"/tmp/envfile.txt","content":"hello"}}' | \
  AUTOTUNE_STATE_DIR="$RULES_DIR" bash "$GATE" 2>&1) || CODE=$?
assert_exit_code 0 "$CODE" "envfile.txt not blocked (false positive check)"

print_results
