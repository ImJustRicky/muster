#!/usr/bin/env bash
# muster/lib/commands/doctor.sh — Project diagnostics

cmd_doctor() {
  local fix=false
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --fix) fix=true; shift ;;
      *) shift ;;
    esac
  done

  load_config

  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  local pass=0
  local warnings=0
  local failures=0

  echo ""
  echo -e "  ${BOLD}Doctor${RESET}"
  echo ""

  # Helper: print pass/warn/fail lines and bump counters
  _doc_pass() { echo -e "  ${GREEN}✓${RESET} $1"; pass=$(( pass + 1 )); }
  _doc_warn() { echo -e "  ${YELLOW}!${RESET} $1"; warnings=$(( warnings + 1 )); }
  _doc_fail() { echo -e "  ${RED}✗${RESET} $1"; failures=$(( failures + 1 )); }

  # ── (a) deploy.json exists and is valid JSON ──
  if [[ -f "$CONFIG_FILE" ]]; then
    local json_valid=false
    if has_cmd jq; then
      jq '.' "$CONFIG_FILE" &>/dev/null && json_valid=true
    elif has_cmd python3; then
      python3 -c "import json; json.load(open('$CONFIG_FILE'))" &>/dev/null && json_valid=true
    else
      json_valid=true  # can't validate, assume ok
    fi
    if [[ "$json_valid" == "true" ]]; then
      _doc_pass "deploy.json valid"
    else
      _doc_fail "deploy.json has invalid JSON"
    fi
  else
    _doc_fail "deploy.json not found"
  fi

  # ── (b) .muster/hooks/ directory exists ──
  local hooks_dir="${project_dir}/.muster/hooks"
  if [[ -d "$hooks_dir" ]]; then
    _doc_pass ".muster/hooks/ directory exists"
  else
    _doc_fail ".muster/hooks/ directory missing"
  fi

  # ── (c, d) Service hooks: existence and executable ──
  local services
  services=$(config_services)
  local svc_count=0
  local missing_hooks=0
  local not_exec=0
  local fixed_exec=0
  local expected_hooks="deploy.sh health.sh rollback.sh logs.sh cleanup.sh"

  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    svc_count=$(( svc_count + 1 ))
    local svc_hooks_dir="${hooks_dir}/${svc}"
    if [[ ! -d "$svc_hooks_dir" ]]; then
      missing_hooks=$(( missing_hooks + 1 ))
      continue
    fi
    for h in $expected_hooks; do
      local hpath="${svc_hooks_dir}/${h}"
      if [[ -f "$hpath" && ! -x "$hpath" ]]; then
        if [[ "$fix" == "true" ]]; then
          chmod +x "$hpath"
          fixed_exec=$(( fixed_exec + 1 ))
        else
          not_exec=$(( not_exec + 1 ))
        fi
      fi
    done
  done <<< "$services"

  _doc_pass "${svc_count} services configured"

  if (( missing_hooks > 0 )); then
    _doc_fail "${missing_hooks} services missing hooks directory"
  fi

  if (( not_exec > 0 )); then
    _doc_fail "${not_exec} hook scripts not executable (run with --fix)"
  elif (( fixed_exec > 0 )); then
    _doc_pass "Fixed ${fixed_exec} hook scripts (chmod +x)"
  else
    if [[ -d "$hooks_dir" ]]; then
      _doc_pass "All hook scripts executable"
    fi
  fi

  # ── (e) Health checks: enabled vs disabled ──
  local health_enabled=0
  local health_disabled=0
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local he
    he=$(config_get ".services.${svc}.health.enabled")
    if [[ "$he" == "false" ]]; then
      health_disabled=$(( health_disabled + 1 ))
    else
      health_enabled=$(( health_enabled + 1 ))
    fi
  done <<< "$services"

  if (( health_disabled > 0 && health_enabled == 0 )); then
    _doc_warn "Health checks disabled for all ${health_disabled} services"
  elif (( health_disabled > 0 )); then
    _doc_warn "Health checks disabled for ${health_disabled} services"
  else
    _doc_pass "Health checks enabled for all services"
  fi

  # ── (f) Stale PID files ──
  local pids_dir="${project_dir}/.muster/pids"
  if [[ -d "$pids_dir" ]]; then
    local stale_pids=0
    local removed_pids=0
    for pid_file in "$pids_dir"/*.pid; do
      [[ -f "$pid_file" ]] || continue
      local stored_pid
      stored_pid=$(cat "$pid_file" 2>/dev/null)
      if [[ -n "$stored_pid" ]] && ! kill -0 "$stored_pid" 2>/dev/null; then
        if [[ "$fix" == "true" ]]; then
          rm -f "$pid_file"
          removed_pids=$(( removed_pids + 1 ))
        else
          stale_pids=$(( stale_pids + 1 ))
        fi
      fi
    done
    if (( removed_pids > 0 )); then
      _doc_pass "Removed ${removed_pids} stale PID files"
    elif (( stale_pids > 0 )); then
      _doc_warn "${stale_pids} stale PID files found (run with --fix)"
    else
      _doc_pass "No stale PID files"
    fi
  else
    _doc_pass "No stale PID files"
  fi

  # ── (g) .env file presence ──
  local env_file="${project_dir}/.env"
  if [[ -f "$env_file" ]]; then
    local env_count=0
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; then
        env_count=$(( env_count + 1 ))
      fi
    done < "$env_file"
    _doc_pass ".env file found (${env_count} vars)"
  else
    _doc_warn ".env file not found"
  fi

  # ── (h) Required tools based on hook content ──
  local needs_docker=false
  local needs_kubectl=false
  local needs_jq=false
  if [[ -d "$hooks_dir" ]]; then
    local hook_content=""
    for hf in "$hooks_dir"/*/*.sh; do
      [[ -f "$hf" ]] || continue
      hook_content="${hook_content}
$(cat "$hf" 2>/dev/null)"
    done
    case "$hook_content" in
      *docker*) needs_docker=true ;;
    esac
    case "$hook_content" in
      *kubectl*) needs_kubectl=true ;;
    esac
    case "$hook_content" in
      *jq*) needs_jq=true ;;
    esac
  fi

  local required_tools=""
  local missing_tools=""
  if [[ "$needs_docker" == "true" ]]; then
    required_tools="${required_tools}docker "
    if [[ "$MUSTER_HAS_DOCKER" != "true" ]]; then
      missing_tools="${missing_tools}docker "
    fi
  fi
  if [[ "$needs_kubectl" == "true" ]]; then
    required_tools="${required_tools}kubectl "
    if [[ "$MUSTER_HAS_KUBECTL" != "true" ]]; then
      missing_tools="${missing_tools}kubectl "
    fi
  fi
  if [[ "$needs_jq" == "true" ]]; then
    required_tools="${required_tools}jq "
    if [[ "$MUSTER_HAS_JQ" != "true" ]]; then
      missing_tools="${missing_tools}jq "
    fi
  fi

  if [[ -n "$missing_tools" ]]; then
    _doc_fail "Missing required tools: ${missing_tools}"
  elif [[ -n "$required_tools" ]]; then
    _doc_pass "Required tools: ${required_tools}"
  fi

  # ── (i) .muster/logs/ exists and writable ──
  local log_dir="${project_dir}/.muster/logs"
  if [[ -d "$log_dir" ]]; then
    if [[ -w "$log_dir" ]]; then
      _doc_pass ".muster/logs/ exists and writable"
    else
      _doc_fail ".muster/logs/ exists but not writable"
    fi
  else
    _doc_warn ".muster/logs/ directory missing"
  fi

  # ── (j) Old log files based on log_retention_days ──
  local retention_days
  retention_days=$(global_config_get "log_retention_days" 2>/dev/null)
  case "$retention_days" in
    ''|*[!0-9]*) retention_days=7 ;;
  esac

  if [[ -d "$log_dir" ]]; then
    local old_logs
    old_logs=$(find "$log_dir" -name "*.log" -mtime +"$retention_days" 2>/dev/null | wc -l | tr -d ' ')
    if (( old_logs > 0 )); then
      if [[ "$fix" == "true" ]]; then
        find "$log_dir" -name "*.log" -mtime +"$retention_days" -delete 2>/dev/null
        _doc_pass "Removed ${old_logs} old log files (>${retention_days} days)"
      else
        _doc_warn "${old_logs} log files older than ${retention_days} days (run with --fix)"
      fi
    fi
  fi

  # ── (k) K8s cluster reachable (if hooks reference kubectl) ──
  if [[ "$needs_kubectl" == "true" && "$MUSTER_HAS_KUBECTL" == "true" ]]; then
    if kubectl cluster-info &>/dev/null; then
      _doc_pass "Kubernetes cluster reachable"
    else
      _doc_warn "Kubernetes cluster not reachable"
    fi
  fi

  # ── Summary ──
  echo ""
  local summary="  ${pass} checks passed"
  if (( warnings > 0 )); then
    summary="${summary}, ${YELLOW}${warnings} warnings${RESET}"
  fi
  if (( failures > 0 )); then
    summary="${summary}, ${RED}${failures} failures${RESET}"
  fi
  echo -e "  ${summary}"
  echo ""
}
