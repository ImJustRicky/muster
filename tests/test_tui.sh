#!/usr/bin/env bash
# tests/test_tui.sh — Tests for TUI components (matrix, dashboard helpers, color mode)
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

# ────────────────────────────────────────
echo "  TUI — Matrix animation"
# ────────────────────────────────────────

source "$MUSTER_ROOT/lib/tui/matrix.sh"

# _matrix_splash function should exist
_test "_matrix_splash function exists" type -t _matrix_splash

# MUSTER_MINIMAL=true should skip animation entirely (fast, no output)
MUSTER_MINIMAL="true"
_output=$(_matrix_splash 2>&1)
_test_eq "matrix skipped in minimal mode (no output)" "" "$_output"
MUSTER_MINIMAL="false"

# ────────────────────────────────────────
echo ""
echo "  TUI — Dashboard bar helper"
# ────────────────────────────────────────

source "$MUSTER_ROOT/lib/tui/menu.sh" 2>/dev/null || true
source "$MUSTER_ROOT/lib/tui/spinner.sh" 2>/dev/null || true
source "$MUSTER_ROOT/lib/core/build_context.sh" 2>/dev/null || true
source "$MUSTER_ROOT/lib/core/updater.sh" 2>/dev/null || true
source "$MUSTER_ROOT/lib/core/just_runner.sh" 2>/dev/null || true
source "$MUSTER_ROOT/lib/tui/dashboard.sh" 2>/dev/null || true

# _dashboard_bar should render left and right text
_output=$(_dashboard_bar "muster" "v1.0.0  " 2>&1)
_test_contains "dashboard bar contains left text" "muster" "$_output"
_test_contains "dashboard bar contains right text" "v1.0.0" "$_output"

# ────────────────────────────────────────
echo ""
echo "  TUI — Dashboard separator"
# ────────────────────────────────────────

_output=$(_dashboard_rule 2>&1)
_test_contains "dashboard rule contains separator chars" "─" "$_output"

# ────────────────────────────────────────
echo ""
echo "  TUI — Dashboard service line"
# ────────────────────────────────────────

_output=$(_dashboard_print_svc_line "●" "" "api" "healthy" "" 50 2>&1)
_test_contains "service line shows service name" "api" "$_output"
_test_contains "service line shows status label" "healthy" "$_output"

# With credential warning
_output=$(_dashboard_print_svc_line "●" "" "api" "healthy" "KEY" 50 2>&1)
_test_contains "service line shows cred warning" "KEY" "$_output"

# ────────────────────────────────────────
echo ""
echo "  TUI — Color mode never produces no ANSI"
# ────────────────────────────────────────

# When all color vars are empty (simulating color_mode=never),
# dashboard_bar should produce no ANSI escape sequences
GREEN="" YELLOW="" RED="" RESET="" BOLD="" DIM="" ACCENT="" ACCENT_BRIGHT="" WHITE="" GRAY=""
_output=$(_dashboard_print_svc_line "o" "" "redis" "disabled" "" 50 2>&1)
# Check no ESC byte in output (ANSI escapes start with \033)
_has_ansi="false"
case "$_output" in
  *$'\033'*) _has_ansi="true" ;;
esac
_test_eq "no ANSI escapes with empty color vars" "false" "$_has_ansi"

_test_summary
