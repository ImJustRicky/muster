#!/usr/bin/env bash
# muster/lib/commands/status.sh — Service health status

source "$MUSTER_ROOT/lib/tui/spinner.sh"
source "$MUSTER_ROOT/lib/core/remote.sh"

cmd_status() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: muster status"
      echo ""
      echo "Check health of all services."
      return 0
      ;;
    --*)
      err "Unknown flag: $1"
      echo "Run 'muster status --help' for usage."
      return 1
      ;;
  esac

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

    local _remote_tag=""
    if remote_is_enabled "$svc"; then
      _remote_tag=" ${DIM}($(remote_desc "$svc"))${RESET}"
    fi

    if [[ "$health_enabled" == "false" ]]; then
      echo -e "  ${GRAY}○${RESET} ${name}${_remote_tag} ${DIM}(disabled)${RESET}"
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

      start_spinner "Checking ${name}..."
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
        stop_spinner
        echo -e "  ${GREEN}●${RESET} ${name}${_remote_tag}"
      else
        stop_spinner
        echo -e "  ${RED}●${RESET} ${name}${_remote_tag}"
      fi
    else
      echo -e "  ${GRAY}○${RESET} ${name}${_remote_tag} ${DIM}(no health check)${RESET}"
    fi
  done <<< "$services"

  echo ""
}
