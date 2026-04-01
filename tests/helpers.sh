#!/usr/bin/env bash
# Shared test utilities for autotune shell script tests
# Usage: source tests/helpers.sh

set -euo pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors (disabled if not tty)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  NC=''
fi

setup_tmpdir() {
  TEST_TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TEST_TMPDIR"' EXIT
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$actual" -eq "$expected" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (expected exit %d, got %d)\n" "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -q "$needle"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (output missing: %s)\n" "$label" "$needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -q "$needle"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (output contains: %s)\n" "$label" "$needle"
  else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  fi
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} %s\n" "$label"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${RED}FAIL${NC} %s (file not found: %s)\n" "$label" "$path"
  fi
}

print_results() {
  echo ""
  echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
  fi
}
