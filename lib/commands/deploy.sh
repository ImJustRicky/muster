#!/usr/bin/env bash
# muster/lib/commands/deploy.sh — Deploy orchestration

source "$MUSTER_ROOT/lib/tui/spinner.sh"
source "$MUSTER_ROOT/lib/tui/progress.sh"
source "$MUSTER_ROOT/lib/tui/streambox.sh"

cmd_deploy() {
  load_config

  local target="${1:-all}"
  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"
  local log_dir="${project_dir}/.muster/logs"
  mkdir -p "$log_dir"

  local project
  project=$(config_get '.project')

  echo ""
  echo -e "  ${BOLD}${AMBER}Deploying${RESET} ${WHITE}${project}${RESET}"
  echo ""

  # Get deploy order
  local -a services=()
  if [[ "$target" == "all" ]]; then
    while IFS= read -r svc; do
      [[ -z "$svc" ]] && continue
      local skip
      skip=$(config_get ".services.${svc}.skip_deploy")
      [[ "$skip" == "true" ]] && continue
      services+=("$svc")
    done < <(config_get '.deploy_order[]' 2>/dev/null || config_services)
  else
    services+=("$target")
  fi

  local total=${#services[@]}
  local current=0

  for svc in "${services[@]}"; do
    (( current++ ))
    local name
    name=$(config_get ".services.${svc}.name")
    local hook="${project_dir}/.muster/hooks/${svc}/deploy.sh"

    if [[ ! -x "$hook" ]]; then
      warn "No deploy hook for ${name}, skipping"
      continue
    fi

    progress_bar "$current" "$total" "Deploying ${name}..."
    echo ""

    local log_file="${log_dir}/${svc}-deploy-$(date +%Y%m%d-%H%M%S).log"
    stream_in_box "$name" "$log_file" "$hook"
    local rc=$?

    if (( rc == 0 )); then
      ok "${name} deployed"

      # Run health check
      local health_hook="${project_dir}/.muster/hooks/${svc}/health.sh"
      if [[ -x "$health_hook" ]]; then
        start_spinner "Health check: ${name}"
        if "$health_hook" &>/dev/null; then
          stop_spinner
          ok "${name} healthy"
        else
          stop_spinner
          err "${name} health check failed"
          echo ""
          menu_select choice "Health check failed. What do you want to do?" "Continue anyway" "Rollback ${name}" "Abort"
          case "$choice" in
            "Rollback ${name}")
              local rb_hook="${project_dir}/.muster/hooks/${svc}/rollback.sh"
              if [[ -x "$rb_hook" ]]; then
                "$rb_hook" 2>&1 | tee "${log_dir}/${svc}-rollback-$(date +%Y%m%d-%H%M%S).log"
                ok "${name} rolled back"
              else
                err "No rollback hook for ${name}"
              fi
              ;;
            "Abort")
              err "Deploy aborted"
              exit 1
              ;;
          esac
        fi
      fi
    else
      err "${name} deploy failed (exit code ${rc})"
      err "Log: ${log_file}"
      exit 1
    fi

    echo ""
  done

  progress_bar "$total" "$total" "Complete"
  echo ""
  echo ""
  ok "Deploy complete"
  echo ""
}
