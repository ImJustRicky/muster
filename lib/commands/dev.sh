#!/usr/bin/env bash
# muster/lib/commands/dev.sh — Dev mode: deploy + watch + auto-cleanup

source "$MUSTER_ROOT/lib/commands/deploy.sh"
source "$MUSTER_ROOT/lib/commands/cleanup.sh"

_dev_cleanup() {
  echo ""
  echo ""
  echo -e "  ${BOLD}Shutting down dev environment...${RESET}"
  echo ""

  load_config

  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  # Run cleanup hooks for all services
  local services
  services=$(config_services)
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local hook="${project_dir}/.muster/hooks/${svc}/cleanup.sh"
    if [[ -x "$hook" ]]; then
      local name
      name=$(config_get ".services.${svc}.name")
      start_spinner "Cleaning up ${name}..."
      "$hook" &>/dev/null
      stop_spinner
      ok "${name} stopped"
    fi
  done <<< "$services"

  # Kill any remaining PIDs in .muster/pids/
  local pid_dir="${project_dir}/.muster/pids"
  if [[ -d "$pid_dir" ]]; then
    local killed_any=false
    for pid_file in "$pid_dir"/*.pid; do
      [[ -f "$pid_file" ]] || continue
      local pid
      pid=$(cat "$pid_file" 2>/dev/null)
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        killed_any=true
      fi
      rm -f "$pid_file"
    done
    if [[ "$killed_any" == "true" ]]; then
      ok "Killed remaining background processes"
    fi
  fi

  echo ""
  ok "Dev environment stopped"
  echo ""
  exit 0
}

_dev_show_status() {
  local project_dir="$1"

  # Move cursor up past previous status display (if any)
  if [[ "${_dev_first_status:-true}" == "false" ]]; then
    # Clear the previous status block
    local line_count="${_dev_status_lines:-0}"
    local i=0
    while (( i < line_count )); do
      tput cuu1
      tput el
      i=$(( i + 1 ))
    done
  fi
  _dev_first_status=false

  local lines=0

  echo -e "  ${BOLD}Service Health${RESET}"
  lines=$(( lines + 1 ))

  local services
  services=$(config_services)
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local name
    name=$(config_get ".services.${svc}.name")

    local health_enabled
    health_enabled=$(config_get ".services.${svc}.health.enabled")

    local hook="${project_dir}/.muster/hooks/${svc}/health.sh"

    if [[ "$health_enabled" == "false" ]]; then
      echo -e "  ${GRAY}○${RESET} ${name} ${DIM}(disabled)${RESET}"
    elif [[ -x "$hook" ]]; then
      # Export k8s env vars for health hook
      local _k8s_env=""
      _k8s_env=$(k8s_env_for_service "$svc")
      if [[ -n "$_k8s_env" ]]; then
        while IFS='=' read -r _ek _ev; do
          [[ -z "$_ek" ]] && continue
          export "$_ek=$_ev"
        done <<< "$_k8s_env"
      fi

      local _health_ok=false
      if remote_is_enabled "$svc"; then
        if remote_exec_stdout "$svc" "$hook" "$_k8s_env" &>/dev/null; then
          _health_ok=true
        fi
      else
        if "$hook" &>/dev/null; then
          _health_ok=true
        fi
      fi

      # Clean up k8s env
      if [[ -n "$_k8s_env" ]]; then
        while IFS='=' read -r _ek _ev; do
          [[ -z "$_ek" ]] && continue
          unset "$_ek"
        done <<< "$_k8s_env"
      fi

      if [[ "$_health_ok" == "true" ]]; then
        echo -e "  ${GREEN}●${RESET} ${name}"
      else
        echo -e "  ${RED}●${RESET} ${name}"
      fi
    else
      echo -e "  ${GRAY}○${RESET} ${name} ${DIM}(no health check)${RESET}"
    fi
    lines=$(( lines + 1 ))
  done <<< "$services"

  echo ""
  lines=$(( lines + 1 ))
  echo -e "  ${DIM}Last checked: $(date +%H:%M:%S)${RESET}  ${DIM}|${RESET}  ${DIM}Ctrl+C to stop${RESET}"
  lines=$(( lines + 1 ))

  _dev_status_lines="$lines"
}

cmd_dev() {
  load_config

  local project
  project=$(config_get '.project')
  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  # Trap SIGINT/SIGTERM for clean shutdown
  trap '_dev_cleanup' INT TERM

  echo ""
  echo -e "  ${BOLD}${ACCENT_BRIGHT}Dev Mode${RESET} ${WHITE}${project}${RESET}"
  echo ""

  # Deploy all services
  cmd_deploy "$@"
  local rc=$?
  if (( rc != 0 )); then
    err "Deploy failed — aborting dev mode"
    return 1
  fi

  echo ""
  echo -e "  ${GREEN}*${RESET} ${BOLD}Dev environment running${RESET}"
  echo ""

  _dev_first_status=true

  # Watch loop — refresh health every 5 seconds
  while true; do
    _dev_show_status "$project_dir"
    sleep 5
  done
}
