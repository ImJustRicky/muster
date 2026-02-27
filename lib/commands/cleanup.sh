#!/usr/bin/env bash
# muster/lib/commands/cleanup.sh — Cleanup stuck processes

source "$MUSTER_ROOT/lib/tui/spinner.sh"

cmd_cleanup() {
  load_config

  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"
  local services
  services=$(config_services)

  echo ""
  echo -e "  ${BOLD}Cleanup${RESET}"
  echo ""

  # Run cleanup hooks if they exist
  local ran_any=false
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local hook="${project_dir}/.muster/hooks/${svc}/cleanup.sh"
    if [[ -x "$hook" ]]; then
      local name
      name=$(config_get ".services.${svc}.name")
      start_spinner "Cleaning up ${name}..."
      "$hook" &>/dev/null
      stop_spinner
      ok "${name} cleaned up"
      ran_any=true
    fi
  done <<< "$services"

  # Clean old logs (use global log_retention_days, default 7)
  local retention_days
  retention_days=$(global_config_get "log_retention_days" 2>/dev/null)
  case "$retention_days" in
    ''|*[!0-9]*) retention_days=7 ;;
  esac

  local log_dir="${project_dir}/.muster/logs"
  if [[ -d "$log_dir" ]]; then
    local old_logs
    old_logs=$(find "$log_dir" -name "*.log" -mtime +"$retention_days" 2>/dev/null | wc -l | tr -d ' ')
    if (( old_logs > 0 )); then
      find "$log_dir" -name "*.log" -mtime +"$retention_days" -delete 2>/dev/null
      ok "Removed ${old_logs} old log files (>${retention_days} days)"
      ran_any=true
    fi
  fi

  if [[ "$ran_any" == "false" ]]; then
    info "Nothing to clean up"
  fi

  echo ""
}
