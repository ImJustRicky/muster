#!/usr/bin/env bash
# muster/lib/commands/status.sh — Service health status

source "$MUSTER_ROOT/lib/tui/spinner.sh"

cmd_status() {
  load_config

  local project
  project=$(config_get '.project')
  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  echo ""
  echo -e "  ${BOLD}${project}${RESET} — Service Status"
  echo ""

  local services
  services=$(config_services)

  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local name
    name=$(config_get ".services.${svc}.name")

    local hook="${project_dir}/.muster/hooks/${svc}/health.sh"

    local health_enabled
    health_enabled=$(config_get ".services.${svc}.health.enabled")

    if [[ "$health_enabled" == "false" ]]; then
      echo -e "  ${GRAY}○${RESET} ${name} ${DIM}(disabled)${RESET}"
    elif [[ -x "$hook" ]]; then
      start_spinner "Checking ${name}..."
      if "$hook" &>/dev/null; then
        stop_spinner
        echo -e "  ${GREEN}●${RESET} ${name}"
      else
        stop_spinner
        echo -e "  ${RED}●${RESET} ${name}"
      fi
    else
      echo -e "  ${GRAY}○${RESET} ${name} ${DIM}(no health check)${RESET}"
    fi
  done <<< "$services"

  echo ""
}
