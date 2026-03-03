#!/usr/bin/env bash
# muster/lib/core/relay_guard.sh — Relay command validation layer
#
# Validates and sanitizes commands received over the WSS relay before
# the remote agent executes them. Prevents malformed or malicious
# commands from reaching hook scripts.
#
# This is a library file (sourced, not executed directly).

# ── Allowed relay operations ──

_RELAY_ALLOWED_COMMANDS="deploy rollback health logs cleanup status"

# ── Audit log path ──

_RELAY_AUDIT_LOG="$HOME/.muster/relay_audit.log"

# ── Validation functions ──

# Validate a relay command before execution.
# Usage: _relay_guard_validate_command "deploy" "api"
# Returns 0 if valid, 1 if rejected (with error message to stderr).
_relay_guard_validate_command() {
  local command="$1"
  local service="$2"

  # Command must not be empty
  if [[ -z "$command" ]]; then
    _relay_guard_log_rejection "empty command" "" "$service"
    printf '%b  %bx%b relay guard: empty command rejected\n' "" "$RED" "$RESET" >&2
    return 1
  fi

  # Check against allowlist
  local _allowed=false
  local _cmd
  for _cmd in $_RELAY_ALLOWED_COMMANDS; do
    if [[ "$command" == "$_cmd" ]]; then
      _allowed=true
      break
    fi
  done

  if [[ "$_allowed" == "false" ]]; then
    _relay_guard_log_rejection "unknown command" "$command" "$service"
    printf '%b  %bx%b relay guard: command %s not in allowlist\n' "" "$RED" "$RESET" "$command" >&2
    return 1
  fi

  # Validate the service name if provided
  if [[ -n "$service" ]]; then
    if ! _relay_guard_validate_service "$service"; then
      return 1
    fi
  fi

  return 0
}

# Validate and sanitize a service name.
# Only allows lowercase alphanumeric, underscores, and hyphens.
# Rejects empty names, path traversal, and shell metacharacters.
# Usage: _relay_guard_validate_service "api_v1"
# Returns 0 if valid, 1 if rejected.
_relay_guard_validate_service() {
  local service="$1"

  # Must not be empty
  if [[ -z "$service" ]]; then
    _relay_guard_log_rejection "empty service name" "" ""
    printf '%b  %bx%b relay guard: empty service name\n' "" "$RED" "$RESET" >&2
    return 1
  fi

  # Length limit (64 chars is generous for a service name)
  if (( ${#service} > 64 )); then
    _relay_guard_log_rejection "service name too long (${#service} chars)" "" "$service"
    printf '%b  %bx%b relay guard: service name exceeds 64 characters\n' "" "$RED" "$RESET" >&2
    return 1
  fi

  # Must match [a-z0-9_-] only
  # Using grep -q with ERE; fall back to bash pattern if grep unavailable
  if printf '%s' "$service" | grep -qE '[^a-z0-9_-]'; then
    _relay_guard_log_rejection "invalid service name chars" "" "$service"
    printf '%b  %bx%b relay guard: service name contains invalid characters (allowed: a-z 0-9 _ -)\n' "" "$RED" "$RESET" >&2
    return 1
  fi

  # Reject path traversal patterns
  case "$service" in
    *..*)
      _relay_guard_log_rejection "path traversal in service name" "" "$service"
      printf '%b  %bx%b relay guard: service name contains path traversal\n' "" "$RED" "$RESET" >&2
      return 1
      ;;
  esac

  return 0
}

# Sanitize a single argument string.
# Rejects arguments containing shell metacharacters, null bytes, newlines,
# or path traversal sequences.
# Usage: _relay_guard_sanitize_arg "some-value"
# Returns 0 if safe, 1 if rejected.
_relay_guard_sanitize_arg() {
  local arg="$1"

  # Reject null bytes (check via printf + od since bash can't hold \0 in vars,
  # but if one sneaks through encoding it would appear as literal text)
  case "$arg" in
    *$'\x00'*)
      _relay_guard_log_rejection "null byte in argument" "" ""
      printf '%b  %bx%b relay guard: argument contains null byte\n' "" "$RED" "$RESET" >&2
      return 1
      ;;
  esac

  # Reject newlines (CR or LF)
  case "$arg" in
    *$'\n'*|*$'\r'*)
      _relay_guard_log_rejection "newline in argument" "" ""
      printf '%b  %bx%b relay guard: argument contains newline\n' "" "$RED" "$RESET" >&2
      return 1
      ;;
  esac

  # Reject path traversal
  case "$arg" in
    *../*|*/../*)
      _relay_guard_log_rejection "path traversal in argument" "" ""
      printf '%b  %bx%b relay guard: argument contains path traversal\n' "" "$RED" "$RESET" >&2
      return 1
      ;;
  esac

  # Reject shell metacharacters: ; | & ` $ ( ) { } < >
  if printf '%s' "$arg" | grep -qE '[;|&`$(){}<>]'; then
    _relay_guard_log_rejection "shell metacharacter in argument" "" ""
    printf '%b  %bx%b relay guard: argument contains shell metacharacters\n' "" "$RED" "$RESET" >&2
    return 1
  fi

  return 0
}

# Validate a hook file before execution.
# Checks: exists, within project hooks dir, not a symlink escape, owned by
# current user, not world-writable, has expected shebang.
# Usage: _relay_guard_validate_hook "/path/to/hook.sh" "/path/to/project"
# Returns 0 if valid, 1 if rejected.
_relay_guard_validate_hook() {
  local hook_path="$1"
  local project_dir="$2"

  # Must not be empty
  if [[ -z "$hook_path" || -z "$project_dir" ]]; then
    _relay_guard_log_rejection "empty hook path or project dir" "" ""
    printf '%b  %bx%b relay guard: hook path or project dir is empty\n' "" "$RED" "$RESET" >&2
    return 1
  fi

  # Hook file must exist
  if [[ ! -f "$hook_path" ]]; then
    _relay_guard_log_rejection "hook file not found" "$hook_path" ""
    printf '%b  %bx%b relay guard: hook file not found: %s\n' "" "$RED" "$RESET" "$hook_path" >&2
    return 1
  fi

  # ── Resolve real paths to prevent symlink escape ──
  # macOS bash 3.2 has no readlink -f; resolve manually
  local _real_hook _real_hooks_dir
  _real_hook=$(_relay_guard_resolve_path "$hook_path")
  _real_hooks_dir=$(_relay_guard_resolve_path "${project_dir}/.muster/hooks")

  # Hook must be inside the project's .muster/hooks/ directory
  case "$_real_hook" in
    "${_real_hooks_dir}"/*)
      # Good — hook is within the expected directory
      ;;
    *)
      _relay_guard_log_rejection "hook path escapes hooks directory" "$hook_path" ""
      printf '%b  %bx%b relay guard: hook path is outside .muster/hooks/\n' "" "$RED" "$RESET" >&2
      return 1
      ;;
  esac

  # ── Ownership check: must be owned by the current user ──
  local _current_uid _file_uid
  _current_uid=$(id -u)

  # stat syntax differs between macOS and Linux
  if stat -f '%u' "$hook_path" &>/dev/null; then
    # macOS (BSD stat)
    _file_uid=$(stat -f '%u' "$hook_path")
  else
    # Linux (GNU stat)
    _file_uid=$(stat -c '%u' "$hook_path")
  fi

  if [[ "$_file_uid" != "$_current_uid" ]]; then
    _relay_guard_log_rejection "hook not owned by current user (uid ${_file_uid} != ${_current_uid})" "$hook_path" ""
    printf '%b  %bx%b relay guard: hook file is not owned by current user\n' "" "$RED" "$RESET" >&2
    return 1
  fi

  # ── World-writable check ──
  local _file_perms
  if stat -f '%Lp' "$hook_path" &>/dev/null; then
    # macOS (BSD stat) — returns octal like 755
    _file_perms=$(stat -f '%Lp' "$hook_path")
  else
    # Linux (GNU stat)
    _file_perms=$(stat -c '%a' "$hook_path")
  fi

  # Check if "others" write bit is set (octal: xx2, xx3, xx6, xx7)
  local _others_perm="${_file_perms: -1}"
  case "$_others_perm" in
    2|3|6|7)
      _relay_guard_log_rejection "hook is world-writable (perms: ${_file_perms})" "$hook_path" ""
      printf '%b  %bx%b relay guard: hook file is world-writable\n' "" "$RED" "$RESET" >&2
      return 1
      ;;
  esac

  # ── Shebang check ──
  local _first_line
  IFS= read -r _first_line < "$hook_path"

  case "$_first_line" in
    "#!/usr/bin/env bash"*|"#!/bin/bash"*|"#!/usr/bin/bash"*)
      # Valid shebang
      ;;
    *)
      _relay_guard_log_rejection "invalid or missing shebang" "$hook_path" ""
      printf '%b  %bx%b relay guard: hook has unexpected shebang: %s\n' "" "$RED" "$RESET" "$_first_line" >&2
      return 1
      ;;
  esac

  return 0
}

# Sanitize environment variables for hook execution.
# Reads lines from stdin (KEY=VALUE format), outputs only safe MUSTER_* vars.
# Rejects values containing shell injection patterns.
# Usage: echo "MUSTER_K8S_NS=default" | _relay_guard_sanitize_env
_relay_guard_sanitize_env() {
  local _line _key _val
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    # Skip empty lines
    [[ -z "$_line" ]] && continue

    # Split on first =
    _key="${_line%%=*}"
    _val="${_line#*=}"

    # Key must not be empty
    [[ -z "$_key" ]] && continue

    # Only allow MUSTER_* prefixed variable names
    case "$_key" in
      MUSTER_*)
        ;;
      *)
        _relay_guard_log_rejection "non-MUSTER env var rejected" "$_key" ""
        continue
        ;;
    esac

    # Key must be a valid env var name: uppercase letters, digits, underscores
    if printf '%s' "$_key" | grep -qE '[^A-Z0-9_]'; then
      _relay_guard_log_rejection "invalid env var name" "$_key" ""
      continue
    fi

    # Reject values with shell injection patterns
    # Check for: ; | & ` $( ) { } < > ${ and newlines
    if printf '%s' "$_val" | grep -qE '[;|&`<>]'; then
      _relay_guard_log_rejection "shell metacharacter in env value" "$_key" ""
      continue
    fi

    # Reject $( and ${ patterns (command/variable substitution)
    case "$_val" in
      *'$('*|*'${'*)
        _relay_guard_log_rejection "shell substitution in env value" "$_key" ""
        continue
        ;;
    esac

    # Reject newlines in values
    case "$_val" in
      *$'\n'*|*$'\r'*)
        _relay_guard_log_rejection "newline in env value" "$_key" ""
        continue
        ;;
    esac

    # Value is safe — output it
    printf '%s=%s\n' "$_key" "$_val"
  done
}

# Log rejected commands for audit.
# Appends to ~/.muster/relay_audit.log with timestamp.
# Usage: _relay_guard_log_rejection "reason" "command" "service"
_relay_guard_log_rejection() {
  local reason="$1"
  local command="${2:-}"
  local service="${3:-}"

  # Ensure directory exists
  mkdir -p "$(dirname "$_RELAY_AUDIT_LOG")" 2>/dev/null || true

  local _ts
  _ts=$(date '+%Y-%m-%d %H:%M:%S')

  # Truncate command/service for logging (prevent log flooding)
  if (( ${#command} > 200 )); then
    command="${command:0:200}...(truncated)"
  fi
  if (( ${#service} > 100 )); then
    service="${service:0:100}...(truncated)"
  fi

  printf '[%s] REJECTED reason="%s" command="%s" service="%s"\n' \
    "$_ts" "$reason" "$command" "$service" >> "$_RELAY_AUDIT_LOG" 2>/dev/null || true
}

# ── Just integration ──

# Determine guard mode for a service.
# Returns "just" if service has a justfile and just is installed, "bash" otherwise.
# Usage: _relay_guard_mode <project_dir> <service>
_relay_guard_mode() {
  local project_dir="$1" svc="$2"
  local hook_dir="${project_dir}/.muster/hooks/${svc}"
  if has_cmd just && [[ -f "${hook_dir}/justfile" ]]; then
    echo "just"
  else
    echo "bash"
  fi
}

# Validate a command using Just-based guard.
# Only allows known recipe names that exist in the service's justfile.
# Usage: _relay_guard_validate_just <project_dir> <service> <recipe>
# Returns 0 if valid, 1 if rejected (with error message to stderr).
_relay_guard_validate_just() {
  local project_dir="$1" svc="$2" recipe="$3"
  local hook_dir="${project_dir}/.muster/hooks/${svc}"
  local justfile="${hook_dir}/justfile"

  # Justfile must exist
  if [[ ! -f "$justfile" ]]; then
    _relay_guard_log_rejection "no justfile" "$recipe" "$svc"
    printf '%b\n' "${RED}Rejected: no justfile for ${svc}${RESET}" >&2
    return 1
  fi

  # Recipe must exist in the justfile
  if ! just --justfile "$justfile" --summary 2>/dev/null | tr ' ' '\n' | grep -qx "$recipe"; then
    _relay_guard_log_rejection "unknown recipe" "$recipe" "$svc"
    printf '%b\n' "${RED}Rejected: recipe '${recipe}' not in justfile${RESET}" >&2
    return 1
  fi

  return 0
}

# ── Internal helpers ──

# Resolve a path to its real absolute path (no symlinks).
# macOS bash 3.2 compatible (no readlink -f).
# Usage: _relay_guard_resolve_path "/some/path"
_relay_guard_resolve_path() {
  local _path="$1"

  # If it's a directory, cd into it and use pwd -P
  if [[ -d "$_path" ]]; then
    (cd "$_path" 2>/dev/null && pwd -P)
    return
  fi

  # For files: resolve the directory, then append the filename
  local _dir _base
  _dir=$(dirname "$_path")
  _base=$(basename "$_path")

  # Resolve symlinks on the file itself
  local _resolved="$_path"
  while [[ -L "$_resolved" ]]; do
    local _link_target
    _link_target=$(ls -l "$_resolved" 2>/dev/null | sed 's/.*-> //')
    case "$_link_target" in
      /*)
        _resolved="$_link_target"
        ;;
      *)
        _resolved="$(dirname "$_resolved")/${_link_target}"
        ;;
    esac
    _dir=$(dirname "$_resolved")
    _base=$(basename "$_resolved")
  done

  # Resolve the directory
  if [[ -d "$_dir" ]]; then
    printf '%s/%s' "$(cd "$_dir" 2>/dev/null && pwd -P)" "$_base"
  else
    # Can't resolve — return as-is
    printf '%s' "$_path"
  fi
}
