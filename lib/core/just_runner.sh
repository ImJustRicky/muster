#!/usr/bin/env bash
# muster/lib/core/just_runner.sh — Optional Just (https://just.systems) runner
# When just is installed and a justfile exists in a service's hook directory,
# muster can use it instead of the .sh scripts.

# Check if Just runner is available for a service hook directory.
# Returns 0 if justfile exists and just is installed.
# Usage: _just_available <hook_dir>
_just_available() {
  local hook_dir="$1"
  has_cmd just && [[ -f "${hook_dir}/justfile" ]]
}

# Check if a specific recipe exists in a justfile.
# Returns 0 if recipe is defined.
# Usage: _just_has_recipe <hook_dir> <recipe>
_just_has_recipe() {
  local hook_dir="$1" recipe="$2"
  just --justfile "${hook_dir}/justfile" --summary 2>/dev/null | tr ' ' '\n' | grep -qx "$recipe"
}

# Run a hook via Just instead of bash.
# Exports env vars, then runs: just --justfile <justfile> <recipe>
# Usage: _just_run <hook_dir> <recipe> [env_lines]
# env_lines: newline-separated KEY=VALUE pairs to export before running
_just_run() {
  local hook_dir="$1" recipe="$2" env_lines="${3:-}"

  # Export env vars if provided
  if [[ -n "$env_lines" ]]; then
    while IFS='=' read -r _jk _jv; do
      [[ -z "$_jk" ]] && continue
      export "$_jk=$_jv"
    done <<< "$env_lines"
  fi

  just --justfile "${hook_dir}/justfile" "$recipe"
  local rc=$?

  # Clean up exported env vars
  if [[ -n "$env_lines" ]]; then
    while IFS='=' read -r _jk _jv; do
      [[ -z "$_jk" ]] && continue
      unset "$_jk"
    done <<< "$env_lines"
  fi

  return "$rc"
}

# Resolve the hook command for a service.
# If just is available and the recipe exists, prints "just" and returns 0.
# Otherwise returns 1 (caller should fall back to .sh hook).
# Usage: _just_resolve <hook_dir> <recipe>
_just_resolve() {
  local hook_dir="$1" recipe="$2"
  if _just_available "$hook_dir" && _just_has_recipe "$hook_dir" "$recipe"; then
    return 0
  fi
  return 1
}

# Check if a remote machine has just installed.
# Requires _remote_load_config + _remote_build_opts to have been called first
# (sets _SSH_OPTS, _REMOTE_USER, _REMOTE_HOST).
# Usage: _just_remote_available
# Returns 0 if just is on the remote PATH.
_just_remote_available() {
  # shellcheck disable=SC2086 — $_SSH_OPTS intentionally unquoted for word-splitting
  ssh $_SSH_OPTS "${_REMOTE_USER}@${_REMOTE_HOST}" "command -v just" &>/dev/null
}

# Run a just recipe on a remote machine via SSH.
# Requires _remote_load_config + _remote_build_opts to have been called first.
# Usage: _just_remote_run <svc> <recipe> [env_lines]
# env_lines: newline-separated KEY=VALUE pairs to export before running
_just_remote_run() {
  local svc="$1" recipe="$2" env_lines="${3:-}"

  {
    # Export env vars on the remote side
    if [[ -n "$env_lines" ]]; then
      while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        local _ek="${_line%%=*}"
        local _ev="${_line#*=}"
        printf 'export %s=%q\n' "$_ek" "$_ev"
      done <<< "$env_lines"
    fi

    # cd to project directory if set
    if [[ -n "${_REMOTE_PROJECT_DIR:-}" ]]; then
      printf 'cd %q || exit 1\n' "$_REMOTE_PROJECT_DIR"
    fi

    # Run the just recipe from the service's justfile
    printf 'just --justfile .muster/hooks/%s/justfile %s\n' "$svc" "$recipe"
  # shellcheck disable=SC2086 — $_SSH_OPTS intentionally unquoted for word-splitting
  } | ssh $_SSH_OPTS "${_REMOTE_USER}@${_REMOTE_HOST}" "bash -s"
}

# Run a hook, preferring Just if available, falling back to .sh script.
# Usage: _hook_run <hook_dir> <hook_name> [env_lines]
# hook_name: deploy, health, rollback, logs, cleanup
# Returns the exit code of the hook.
_hook_run() {
  local hook_dir="$1" hook_name="$2" env_lines="${3:-}"

  if _just_available "$hook_dir" && _just_has_recipe "$hook_dir" "$hook_name"; then
    _just_run "$hook_dir" "$hook_name" "$env_lines"
    return $?
  fi

  local hook_script="${hook_dir}/${hook_name}.sh"
  if [[ -x "$hook_script" ]]; then
    "$hook_script"
    return $?
  fi

  return 127
}
