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

  # Box width: total line = 2 (margin) + 1 (border) + w (inner) + 1 (border) = w + 4
  local w=$(( TERM_COLS - 4 ))
  (( w > 50 )) && w=50
  (( w < 10 )) && w=10
  local inner=$(( w - 2 ))

  # Top border with "Services" label
  local label="Services"
  local label_pad_len=$(( w - ${#label} - 3 ))
  (( label_pad_len < 1 )) && label_pad_len=1
  local label_pad
  label_pad=$(printf '%*s' "$label_pad_len" "" | sed 's/ /─/g')
  printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$label" "${RESET}${ACCENT}" "$label_pad" "${RESET}"

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
    local cred_extra=0
    if [[ "$cred_enabled" == "true" ]]; then
      cred_warn="! KEY"
      cred_extra=${#cred_warn}
      cred_extra=$((cred_extra + 1))  # space before
    fi

    # Truncate name to fit: "  " + icon + " " + name + cred_warn + pad = inner
    local max_name=$(( inner - 4 - cred_extra ))
    (( max_name < 5 )) && max_name=5
    local display_name="$name"
    if (( ${#display_name} > max_name )); then
      display_name="${display_name:0:$((max_name - 3))}..."
    fi

    local content_len=$(( 4 + ${#display_name} + cred_extra ))
    local pad_len=$(( inner - content_len ))
    (( pad_len < 0 )) && pad_len=0
    local pad
    pad=$(printf '%*s' "$pad_len" "")

    if [[ -n "$cred_warn" ]]; then
      printf '  %b│%b  %b%s%b %s%s %b%s%b%b│%b\n' \
        "${ACCENT}" "${RESET}" "$status_color" "$status_icon" "${RESET}" "$display_name" "$pad" "${YELLOW}" "$cred_warn" "${RESET}" "${ACCENT}" "${RESET}"
    else
      printf '  %b│%b  %b%s%b %s%s%b│%b\n' \
        "${ACCENT}" "${RESET}" "$status_color" "$status_icon" "${RESET}" "$display_name" "$pad" "${ACCENT}" "${RESET}"
    fi
  done <<< "$services"

  local bottom
  bottom=$(printf '%*s' "$w" "" | sed 's/ /─/g')
  printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"
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
