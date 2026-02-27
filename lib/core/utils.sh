#!/usr/bin/env bash
# muster/lib/core/utils.sh — Shared utility functions

# Terminal size (updated on SIGWINCH)
TERM_COLS=80
TERM_ROWS=24

update_term_size() {
  TERM_COLS=$(tput cols 2>/dev/null || echo 80)
  TERM_ROWS=$(tput lines 2>/dev/null || echo 24)
}
update_term_size

# Global redraw callback — set this to a function name to auto-redraw on resize
MUSTER_REDRAW_FN=""

# Flag: set to "true" by WINCH redraw to tell menu/checklist to do a full redraw
_MUSTER_INPUT_DIRTY="false"

_on_resize() {
  update_term_size
  if [[ -n "$MUSTER_REDRAW_FN" ]]; then
    $MUSTER_REDRAW_FN
  fi
}
trap '_on_resize' WINCH

# Cleanup terminal state on exit
cleanup_term() {
  printf '\033[;r' 2>/dev/null
  tput cnorm 2>/dev/null || true
  printf '\033[0m' 2>/dev/null
  stty echo 2>/dev/null || true
  echo ""
}
trap cleanup_term EXIT

# Double Ctrl+C to quit — first press warns, second within 5s exits
_SIGINT_LAST=0

_on_sigint() {
  local now
  now=$(date +%s)
  local diff=$(( now - _SIGINT_LAST ))
  if (( diff <= 5 )); then
    echo ""
    cleanup_term
    exit 0
  fi
  _SIGINT_LAST=$now
  # Move to a new line, show warning
  echo ""
  printf '  \033[38;5;221m!\033[0m Press Ctrl+C again to quit\n'
}
trap '_on_sigint' INT

# Check if a command exists
has_cmd() {
  command -v "$1" &>/dev/null
}

# Find the project deploy.json by walking up from cwd
find_config() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/deploy.json" ]]; then
      echo "$dir/deploy.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}
