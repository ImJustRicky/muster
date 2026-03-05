#!/usr/bin/env bash
# tests/test_onboarding.sh — Tests for first-run onboarding flow
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MUSTER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helpers.sh"

# Disable colors for test isolation
GREEN="" YELLOW="" RED="" RESET="" BOLD="" DIM="" ACCENT="" ACCENT_BRIGHT="" WHITE="" GRAY=""
MUSTER_QUIET="true"
MUSTER_VERBOSE="false"
TERM_COLS=80
TERM_ROWS=24

source "$MUSTER_ROOT/lib/core/logger.sh"
source "$MUSTER_ROOT/lib/core/utils.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Use a fake HOME so we don't touch the real ~/.muster
FAKE_HOME="${TMPDIR}/fakehome"
mkdir -p "$FAKE_HOME"

# Source matrix.sh so _first_run_check can call _matrix_splash
source "$MUSTER_ROOT/lib/tui/matrix.sh"

# Extract _first_run_check into an isolated function we can test.
# It checks: MUSTER_MINIMAL, TTY, and sentinel file.
# We redefine it here to use FAKE_HOME and skip interactive read.
_first_run_check_testable() {
  [[ "$MUSTER_MINIMAL" == "true" ]] && return 1
  [[ "${_TEST_IS_TTY:-false}" == "false" ]] && return 1
  [[ -f "$FAKE_HOME/.muster/.first_run_done" ]] && return 1

  # Create sentinel (mirrors real logic)
  mkdir -p "$FAKE_HOME/.muster"
  printf '' > "$FAKE_HOME/.muster/.first_run_done"
  return 0
}

# ────────────────────────────────────────
echo "  Onboarding — sentinel file detection"
# ────────────────────────────────────────

# First run: no sentinel, TTY, not minimal → should trigger
_TEST_IS_TTY="true"
MUSTER_MINIMAL="false"
rm -f "$FAKE_HOME/.muster/.first_run_done"

_rc=0
_first_run_check_testable || _rc=$?
_test_eq "first run triggers when no sentinel" "0" "$_rc"
_test_file_exists "sentinel created after first run" "$FAKE_HOME/.muster/.first_run_done"

# Returning user: sentinel exists → should NOT trigger
_rc=0
_first_run_check_testable || _rc=$?
_test "returning user skips onboarding" test "$_rc" -ne 0

# ────────────────────────────────────────
echo ""
echo "  Onboarding — minimal mode skip"
# ────────────────────────────────────────

# Remove sentinel, set minimal mode
rm -f "$FAKE_HOME/.muster/.first_run_done"
MUSTER_MINIMAL="true"
_TEST_IS_TTY="true"

_rc=0
_first_run_check_testable || _rc=$?
_test "first-run skipped in minimal mode" test "$_rc" -ne 0
_test "sentinel NOT created in minimal mode" test ! -f "$FAKE_HOME/.muster/.first_run_done"

# ────────────────────────────────────────
echo ""
echo "  Onboarding — non-TTY skip"
# ────────────────────────────────────────

rm -f "$FAKE_HOME/.muster/.first_run_done"
MUSTER_MINIMAL="false"
_TEST_IS_TTY="false"

_rc=0
_first_run_check_testable || _rc=$?
_test "first-run skipped when not a TTY" test "$_rc" -ne 0
_test "sentinel NOT created when not a TTY" test ! -f "$FAKE_HOME/.muster/.first_run_done"

_test_summary
