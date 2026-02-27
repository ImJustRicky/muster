#!/usr/bin/env bash
# muster/lib/commands/deploy.sh — Deploy orchestration

source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"
source "$MUSTER_ROOT/lib/tui/progress.sh"
source "$MUSTER_ROOT/lib/tui/streambox.sh"
source "$MUSTER_ROOT/lib/core/credentials.sh"
source "$MUSTER_ROOT/lib/core/remote.sh"
source "$MUSTER_ROOT/lib/skills/manager.sh"
source "$MUSTER_ROOT/lib/commands/history.sh"

cmd_deploy() {
  local dry_run=false
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      *) shift ;;
    esac
  done

  load_config
  _load_env_file

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

    if [[ "$dry_run" == "true" ]]; then
      # ── Dry-run: show plan without executing anything ──
      progress_bar "$current" "$total" "Deploying ${name}..."
      echo ""
      echo ""
      echo -e "  ${ACCENT}[DRY-RUN]${RESET} ${BOLD}Deploying ${name}${RESET} (${current}/${total})"
      echo -e "  ${DIM}Hook:${RESET} ${hook}"

      # Show first 10 lines of the hook script
      local _line_num=0
      local _separator=""
      printf -v _separator '%*s' 34 ''
      _separator="${_separator// /-}"
      echo -e "  ${DIM}${_separator}${RESET}"
      while IFS= read -r _line; do
        _line_num=$(( _line_num + 1 ))
        (( _line_num > 10 )) && break
        echo -e "  ${DIM}${_line}${RESET}"
      done < "$hook"
      if (( _line_num > 10 )); then
        echo -e "  ${DIM}...${RESET}"
      fi
      echo -e "  ${DIM}${_separator}${RESET}"

      # Show credential key names (without fetching values)
      local _cred_enabled
      _cred_enabled=$(config_get ".services.${svc}.credentials.enabled")
      if [[ "$_cred_enabled" == "true" ]]; then
        local _cred_keys=""
        _cred_keys=$(config_get ".services.${svc}.credentials.required[]" 2>/dev/null)
        if [[ -n "$_cred_keys" && "$_cred_keys" != "null" ]]; then
          local _cred_display=""
          while IFS= read -r _ck; do
            [[ -z "$_ck" ]] && continue
            local _upper_ck
            _upper_ck=$(printf '%s' "$_ck" | tr '[:lower:]' '[:upper:]')
            if [[ -n "$_cred_display" ]]; then
              _cred_display="${_cred_display}, MUSTER_CRED_${_upper_ck}"
            else
              _cred_display="MUSTER_CRED_${_upper_ck}"
            fi
          done <<< "$_cred_keys"
          echo -e "  ${DIM}Credentials:${RESET} ${_cred_display}"
        fi
      fi

      # Show health check status
      local health_hook="${project_dir}/.muster/hooks/${svc}/health.sh"
      local health_enabled
      health_enabled=$(config_get ".services.${svc}.health.enabled")
      if [[ "$health_enabled" != "false" && -x "$health_hook" ]]; then
        echo -e "  ${DIM}Health check:${RESET} ${health_hook} ${GREEN}(enabled)${RESET}"
      else
        echo -e "  ${DIM}Health check:${RESET} ${RED}(disabled)${RESET}"
      fi

      # Show remote status
      if remote_is_enabled "$svc"; then
        local _remote_pdir
        _remote_pdir=$(config_get ".services.${svc}.remote.project_dir")
        [[ "$_remote_pdir" == "null" ]] && _remote_pdir=""
        echo -e "  ${DIM}Remote:${RESET} $(remote_desc "$svc") ${GREEN}(enabled)${RESET}"
        if [[ -n "$_remote_pdir" ]]; then
          echo -e "  ${DIM}Project dir:${RESET} ${_remote_pdir}"
        fi
      fi

      echo ""
    else
      # ── Normal deploy ──

      # Gather credentials if configured
      local _cred_env_lines=""
      _cred_env_lines=$(cred_env_for_service "$svc")

      # Export k8s config as env vars (hooks read these at runtime)
      local _k8s_env_lines=""
      _k8s_env_lines=$(k8s_env_for_service "$svc")
      if [[ -n "$_k8s_env_lines" ]]; then
        while IFS='=' read -r _ek _ev; do
          [[ -z "$_ek" ]] && continue
          export "$_ek=$_ev"
        done <<< "$_k8s_env_lines"
      fi

      run_skill_hooks "pre-deploy" "$svc"

      progress_bar "$current" "$total" "Deploying ${name}..."
      echo ""

      while true; do
        local log_file="${log_dir}/${svc}-deploy-$(date +%Y%m%d-%H%M%S).log"

        if remote_is_enabled "$svc"; then
          # ── Remote deploy via SSH ──
          info "Deploying ${name} remotely ($(remote_desc "$svc"))"
          local _all_env="${_cred_env_lines}"
          [[ -n "$_k8s_env_lines" ]] && _all_env="${_all_env}
${_k8s_env_lines}"
          stream_in_box "$name" "$log_file" remote_exec_stdout "$svc" "$hook" "$_all_env"
        else
          # ── Local deploy ──
          if [[ -n "$_cred_env_lines" ]]; then
            while IFS='=' read -r _ck _cv; do
              [[ -z "$_ck" ]] && continue
              export "$_ck=$_cv"
            done <<< "$_cred_env_lines"
          fi

          stream_in_box "$name" "$log_file" "$hook"
        fi
        local rc=$?

        if (( rc == 0 )); then
          ok "${name} deployed"
          _history_log_event "$svc" "deploy" "ok"
          run_skill_hooks "post-deploy" "$svc"

          # Run health check
          local health_hook="${project_dir}/.muster/hooks/${svc}/health.sh"
          local health_enabled
          health_enabled=$(config_get ".services.${svc}.health.enabled")
          if [[ "$health_enabled" != "false" && -x "$health_hook" ]]; then
            start_spinner "Health check: ${name}"
            local _health_ok=false
            if remote_is_enabled "$svc"; then
              if remote_exec_stdout "$svc" "$health_hook" "" &>/dev/null; then
                _health_ok=true
              fi
            else
              if "$health_hook" &>/dev/null; then
                _health_ok=true
              fi
            fi
            if [[ "$_health_ok" == "true" ]]; then
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
                    if remote_is_enabled "$svc"; then
                      remote_exec_stdout "$svc" "$rb_hook" "$_cred_env_lines" 2>&1 | tee "${log_dir}/${svc}-rollback-$(date +%Y%m%d-%H%M%S).log"
                    else
                      "$rb_hook" 2>&1 | tee "${log_dir}/${svc}-rollback-$(date +%Y%m%d-%H%M%S).log"
                    fi
                    ok "${name} rolled back"
                    _history_log_event "$svc" "rollback" "ok"
                  else
                    err "No rollback hook for ${name}"
                  fi
                  ;;
                "Abort")
                  err "Deploy aborted"
                  _unload_env_file
                  return 1
                  ;;
              esac
            fi
          fi
          break
        else
          err "${name} deploy failed (exit code ${rc})"
          _history_log_event "$svc" "deploy" "failed"

          # Show last few lines of log for context
          echo ""
          if [[ -f "$log_file" ]]; then
            tail -5 "$log_file" | while IFS= read -r _line; do
              echo -e "  ${DIM}${_line}${RESET}"
            done
          fi
          echo ""

          menu_select "Deploy failed. What do you want to do?" "Retry" "Rollback ${name}" "Skip and continue" "Abort"

          case "$MENU_RESULT" in
            "Retry")
              ;; # loop continues
            "Rollback ${name}")
              local rb_hook="${project_dir}/.muster/hooks/${svc}/rollback.sh"
              if [[ -x "$rb_hook" ]]; then
                start_spinner "Rolling back ${name}..."
                if remote_is_enabled "$svc"; then
                  remote_exec_stdout "$svc" "$rb_hook" "$_cred_env_lines" >> "${log_dir}/${svc}-rollback-$(date +%Y%m%d-%H%M%S).log" 2>&1
                else
                  "$rb_hook" >> "${log_dir}/${svc}-rollback-$(date +%Y%m%d-%H%M%S).log" 2>&1
                fi
                stop_spinner
                ok "${name} rolled back"
                _history_log_event "$svc" "rollback" "ok"
              else
                err "No rollback hook for ${name}"
              fi
              break
              ;;
            "Skip and continue")
              warn "Skipping ${name}, continuing with next service"
              break
              ;;
            "Abort")
              _unload_env_file
              return 1
              ;;
          esac
        fi
      done

      # Clean up exported env vars (local deploy only)
      if ! remote_is_enabled "$svc"; then
        if [[ -n "$_cred_env_lines" ]]; then
          while IFS='=' read -r _ck _cv; do
            [[ -z "$_ck" ]] && continue
            unset "$_ck"
          done <<< "$_cred_env_lines"
        fi
      fi
      if [[ -n "$_k8s_env_lines" ]]; then
        while IFS='=' read -r _ek _ev; do
          [[ -z "$_ek" ]] && continue
          unset "$_ek"
        done <<< "$_k8s_env_lines"
      fi

      echo ""
    fi
  done

  progress_bar "$total" "$total" "Complete"
  echo ""
  echo ""
  if [[ "$dry_run" == "true" ]]; then
    info "[DRY-RUN] Deploy plan complete — no changes made"
  else
    ok "Deploy complete"
  fi
  echo ""

  _unload_env_file
}
