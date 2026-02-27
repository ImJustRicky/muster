#!/usr/bin/env bash
# muster/lib/commands/deploy.sh — Deploy orchestration

source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"
source "$MUSTER_ROOT/lib/tui/progress.sh"
source "$MUSTER_ROOT/lib/tui/streambox.sh"
source "$MUSTER_ROOT/lib/core/credentials.sh"

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
  echo -e "  ${BOLD}${ACCENT_BRIGHT}Deploying${RESET} ${WHITE}${project}${RESET}"
  echo ""

  # Get deploy order
  local services=()
  if [[ "$target" == "all" ]]; then
    while IFS= read -r svc; do
      [[ -z "$svc" ]] && continue
      local skip
      skip=$(config_get ".services.${svc}.skip_deploy")
      [[ "$skip" == "true" ]] && continue
      services[${#services[@]}]="$svc"
    done < <(config_get '.deploy_order[]' 2>/dev/null || config_services)
  else
    services[0]="$target"
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

    # Gather credentials if configured
    local _cred_env_lines=""
    _cred_env_lines=$(cred_env_for_service "$svc")
    if [[ -n "$_cred_env_lines" ]]; then
      while IFS='=' read -r _ck _cv; do
        [[ -z "$_ck" ]] && continue
        export "$_ck=$_cv"
      done <<< "$_cred_env_lines"
    fi

    progress_bar "$current" "$total" "Deploying ${name}..."
    echo ""

    local log_file="${log_dir}/${svc}-deploy-$(date +%Y%m%d-%H%M%S).log"
    stream_in_box "$name" "$log_file" "$hook"
    local rc=$?

    # Clean up exported cred vars
    if [[ -n "$_cred_env_lines" ]]; then
      while IFS='=' read -r _ck _cv; do
        [[ -z "$_ck" ]] && continue
        unset "$_ck"
      done <<< "$_cred_env_lines"
    fi

    if (( rc == 0 )); then
      ok "${name} deployed"

      # Run health check
      local health_hook="${project_dir}/.muster/hooks/${svc}/health.sh"
      local health_enabled
      health_enabled=$(config_get ".services.${svc}.health.enabled")
      if [[ "$health_enabled" != "false" && -x "$health_hook" ]]; then
        start_spinner "Health check: ${name}"
        if "$health_hook" &>/dev/null; then
          stop_spinner
          ok "${name} healthy"
        else
          stop_spinner
          err "${name} health check failed"
          echo ""
          menu_select "Health check failed. What do you want to do?" "Continue anyway" "Rollback ${name}" "Abort"
          case "$MENU_RESULT" in
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
              return 1
              ;;
          esac
        fi
      fi
    else
      err "${name} deploy failed (exit code ${rc})"
      err "Log: ${log_file}"
      return 1
    fi

    echo ""
  done

  progress_bar "$total" "$total" "Complete"
  echo ""
  echo ""
  ok "Deploy complete"
  echo ""
}
