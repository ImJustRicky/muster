#!/usr/bin/env bash
# muster/lib/tui/dashboard.sh — Live status dashboard

source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"

cmd_dashboard() {
  load_config

  local project
  project=$(config_get '.project')

  clear
  echo -e "\n  ${BOLD}${ACCENT_BRIGHT}muster${RESET} ${DIM}v${MUSTER_VERSION}${RESET}  ${WHITE}${project}${RESET}"
  print_platform
  echo ""

  # Health check all services
  local services
  services=$(config_services)

  local w=$(( TERM_COLS - 6 ))
  (( w > 50 )) && w=50
  (( w < 30 )) && w=30
  local inner=$(( w - 2 ))
  local border
  border=$(printf '─%.0s' $(seq 1 "$w"))

  echo -e "  ${ACCENT}┌─${BOLD}Services${RESET}${ACCENT}─$(printf '─%.0s' $(seq 1 $((w - 11))))┐${RESET}"

  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local name status_icon status_color

    name=$(config_get ".services.${svc}.name")
    local cred_enabled
    cred_enabled=$(config_get ".services.${svc}.credentials.enabled")

    # Run health check
    local hook_dir
    hook_dir="$(dirname "$CONFIG_FILE")/.muster/hooks/${svc}"

    if [[ -x "${hook_dir}/health.sh" ]]; then
      if "${hook_dir}/health.sh" &>/dev/null; then
        status_icon="●"
        status_color="$GREEN"
      else
        status_icon="●"
        status_color="$RED"
      fi
    else
      status_icon="○"
      status_color="$GRAY"
    fi

    local cred_warn=""
    [[ "$cred_enabled" == "true" ]] && cred_warn=" ${YELLOW}! KEY${RESET}"

    printf "  ${ACCENT}│${RESET}  ${status_color}${status_icon}${RESET} %-$((inner - 10))s${cred_warn} ${ACCENT}│${RESET}\n" "$name"
  done <<< "$services"

  echo -e "  ${ACCENT}└${border}┘${RESET}"
  echo ""

  # Collect available actions
  local actions=()
  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  actions[${#actions[@]}]="Deploy"

  local has_rollback=false has_logs=false
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local hook_dir="${project_dir}/.muster/hooks/${svc}"
    [[ -x "${hook_dir}/rollback.sh" ]] && has_rollback=true
    [[ -x "${hook_dir}/logs.sh" ]] && has_logs=true
  done <<< "$services"

  actions[${#actions[@]}]="Status"
  [[ "$has_logs" == "true" ]] && actions[${#actions[@]}]="Logs"
  [[ "$has_rollback" == "true" ]] && actions[${#actions[@]}]="Rollback"
  actions[${#actions[@]}]="Cleanup"
  actions[${#actions[@]}]="Quit"

  menu_select "Actions" "${actions[@]}"

  case "$MENU_RESULT" in
    Deploy)
      source "$MUSTER_ROOT/lib/commands/deploy.sh"
      cmd_deploy
      ;;
    Status)
      source "$MUSTER_ROOT/lib/commands/status.sh"
      cmd_status
      ;;
    Logs)
      source "$MUSTER_ROOT/lib/commands/logs.sh"
      cmd_logs
      ;;
    Rollback)
      source "$MUSTER_ROOT/lib/commands/rollback.sh"
      cmd_rollback
      ;;
    Cleanup)
      source "$MUSTER_ROOT/lib/commands/cleanup.sh"
      cmd_cleanup
      ;;
    Quit) exit 0 ;;
  esac
}
