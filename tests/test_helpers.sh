#!/usr/bin/env bash
# tests/test_helpers.sh — Shared test assertions
# Source this at the top of each test file.

PASS=0
FAIL=0
TOTAL=0

_test() {
  TOTAL=$(( TOTAL + 1 ))
  local desc="$1"
  shift
  if "$@" 2>/dev/null; then
    PASS=$(( PASS + 1 ))
    printf '  \033[38;5;114m✓\033[0m %s\n' "$desc"
  else
    FAIL=$(( FAIL + 1 ))
    printf '  \033[38;5;203m✗\033[0m %s\n' "$desc"
  fi
}

_test_eq() {
  TOTAL=$(( TOTAL + 1 ))
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$(( PASS + 1 ))
    printf '  \033[38;5;114m✓\033[0m %s\n' "$desc"
  else
    FAIL=$(( FAIL + 1 ))
    printf '  \033[38;5;203m✗\033[0m %s (expected: "%s", got: "%s")\n' "$desc" "$expected" "$actual"
  fi
}

_test_contains() {
  TOTAL=$(( TOTAL + 1 ))
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$(( PASS + 1 ))
    printf '  \033[38;5;114m✓\033[0m %s\n' "$desc"
  else
    FAIL=$(( FAIL + 1 ))
    printf '  \033[38;5;203m✗\033[0m %s (expected to contain: "%s")\n' "$desc" "$needle"
  fi
}

_test_not_contains() {
  TOTAL=$(( TOTAL + 1 ))
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$(( PASS + 1 ))
    printf '  \033[38;5;114m✓\033[0m %s\n' "$desc"
  else
    FAIL=$(( FAIL + 1 ))
    printf '  \033[38;5;203m✗\033[0m %s (should NOT contain: "%s")\n' "$desc" "$needle"
  fi
}

_test_file_exists() {
  TOTAL=$(( TOTAL + 1 ))
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    PASS=$(( PASS + 1 ))
    printf '  \033[38;5;114m✓\033[0m %s\n' "$desc"
  else
    FAIL=$(( FAIL + 1 ))
    printf '  \033[38;5;203m✗\033[0m %s (file not found: %s)\n' "$desc" "$path"
  fi
}

_test_summary() {
  echo ""
  if (( FAIL == 0 )); then
    printf '  \033[38;5;114m%d/%d tests passed\033[0m\n' "$PASS" "$TOTAL"
  else
    printf '  \033[38;5;203m%d/%d tests passed (%d failed)\033[0m\n' "$PASS" "$TOTAL" "$FAIL"
  fi
  echo ""
  return $FAIL
}
