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

# Track whether TUI modified terminal state
_MUSTER_TUI_ACTIVE="false"

# Call this when entering TUI mode (dashboard, menus with cursor hidden, etc.)
muster_tui_enter() {
  _MUSTER_TUI_ACTIVE="true"
}

# Cleanup terminal state on exit — only resets if TUI was active
cleanup_term() {
  if [[ "$_MUSTER_TUI_ACTIVE" = "true" ]]; then
    printf '\033[;r' 2>/dev/null
    tput cnorm 2>/dev/null || true
    printf '\033[0m' 2>/dev/null
    stty echo 2>/dev/null || true
    echo ""
  fi
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

# ── .env file loading ──

# Tracks variable names loaded from .env for cleanup
_MUSTER_ENV_VARS=()

# Load a .env file, exporting KEY=VALUE pairs without overriding existing env vars.
# Usage: _load_env_file [path]   (defaults to $(dirname "$CONFIG_FILE")/.env)
_load_env_file() {
  local env_file="${1:-}"
  if [[ -z "$env_file" ]]; then
    [[ -z "${CONFIG_FILE:-}" ]] && return 0
    env_file="$(dirname "$CONFIG_FILE")/.env"
  fi
  [[ -f "$env_file" ]] || return 0

  _MUSTER_ENV_VARS=()
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Strip inline comments only outside quotes, but keep it simple:
    # Match KEY=VALUE (value may be quoted)
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"

      # Strip surrounding quotes
      if [[ "$val" =~ ^\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
      elif [[ "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi

      # Do NOT override existing env vars
      if [[ -z "${!key+set}" ]]; then
        export "$key=$val"
        _MUSTER_ENV_VARS[${#_MUSTER_ENV_VARS[@]}]="$key"
      fi
    fi
  done < "$env_file"
}

# Unset all variables loaded by _load_env_file
_unload_env_file() {
  local k
  for k in "${_MUSTER_ENV_VARS[@]}"; do
    unset "$k"
  done
  _MUSTER_ENV_VARS=()
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
