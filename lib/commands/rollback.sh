#!/usr/bin/env bash
# muster/lib/commands/rollback.sh — Rollback last deploy

source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"
source "$MUSTER_ROOT/lib/core/credentials.sh"

cmd_rollback() {
  load_config

  local target="${1:-}"
  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  # If no target, let user pick from services that have rollback hooks
  if [[ -z "$target" ]]; then
    local -a rollback_services=()
    local services
    services=$(config_services)

    while IFS= read -r svc; do
      [[ -z "$svc" ]] && continue
      [[ -x "${project_dir}/.muster/hooks/${svc}/rollback.sh" ]] && rollback_services+=("$svc")
    done <<< "$services"

    if [[ ${#rollback_services[@]} -eq 0 ]]; then
      err "No services have rollback hooks configured"
      return 1
    fi

    menu_select target "Rollback which service?" "${rollback_services[@]}"
  fi

  local hook="${project_dir}/.muster/hooks/${target}/rollback.sh"

  if [[ ! -x "$hook" ]]; then
    err "No rollback hook for ${target}"
    return 1
  fi

  local name
  name=$(config_get ".services.${target}.name")

  echo ""
  warn "Rolling back ${name}..."

  local log_dir="${project_dir}/.muster/logs"
  mkdir -p "$log_dir"
  local log_file="${log_dir}/${target}-rollback-$(date +%Y%m%d-%H%M%S).log"

  # Gather credentials if configured
  local _cred_env_lines=""
  _cred_env_lines=$(cred_env_for_service "$target")
  if [[ -n "$_cred_env_lines" ]]; then
    while IFS='=' read -r _ck _cv; do
      [[ -z "$_ck" ]] && continue
      export "$_ck=$_cv"
    done <<< "$_cred_env_lines"
  fi

  start_spinner "Rolling back ${name}..."
  "$hook" >> "$log_file" 2>&1
  local rc=$?
  stop_spinner

  # Clean up exported cred vars
  if [[ -n "$_cred_env_lines" ]]; then
    while IFS='=' read -r _ck _cv; do
      [[ -z "$_ck" ]] && continue
      unset "$_ck"
    done <<< "$_cred_env_lines"
  fi

  if (( rc == 0 )); then
    ok "${name} rolled back successfully"
  else
    err "${name} rollback failed (exit code ${rc})"
    err "Log: ${log_file}"
  fi
  echo ""
}
