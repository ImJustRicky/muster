#!/usr/bin/env bash
# muster/lib/commands/setup.sh — Guided setup wizard (scan-first)

source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/checklist.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"
source "$MUSTER_ROOT/lib/tui/order.sh"
source "$MUSTER_ROOT/lib/core/scanner.sh"

SETUP_TOTAL_STEPS=7

_setup_phrases=(
  "Let's get this show on the road"
  "Deploying happiness since 2026"
  "Your services called. They want order."
  "Chaos to calm in one setup"
  "Because 'it works on my machine' isn't a strategy"
  "Bringing the mustard to your deploy"
  "Rally your services. Deploy with confidence."
  "One script to rule them all"
  "SSH into production? Not today."
  "Making deploys boring (the good kind)"
  "Hot dogs optional. Deploy scripts required."
  "Gather your troops. It's deploy time."
  "Less YAML, more mustard"
  "Your ops team called. You ARE the ops team."
  "Spreadin' that mustard on your stack"
)

_setup_pick_phrase() {
  local count=${#_setup_phrases[@]}
  local idx=$(( RANDOM % count ))
  echo "${_setup_phrases[$idx]}"
}

# Current screen state for resize redraw
_SETUP_CUR_STEP=1
_SETUP_CUR_LABEL=""
_SETUP_CUR_PHRASE=""
_SETUP_CUR_SUMMARY=()
_SETUP_CUR_PROMPT="false"

_setup_redraw() {
  if [[ "$_SETUP_CUR_PROMPT" == "true" ]]; then
    _setup_screen_inner
  fi
}

_setup_screen_inner() {
  clear
  update_term_size

  local W=$(( TERM_COLS - 4 ))
  (( W > 56 )) && W=56
  (( W < 10 )) && W=10

  local bar_w=$(( W - 4 ))
  (( bar_w < 1 )) && bar_w=1
  local filled=$(( _SETUP_CUR_STEP * bar_w / SETUP_TOTAL_STEPS ))
  local empty_count=$(( bar_w - filled ))
  local bar_filled=""
  local bar_empty=""
  local i=0
  while (( i < filled )); do bar_filled="${bar_filled}#"; i=$((i + 1)); done
  i=0
  while (( i < empty_count )); do bar_empty="${bar_empty}-"; i=$((i + 1)); done

  local step_text="step ${_SETUP_CUR_STEP}/${SETUP_TOTAL_STEPS}"

  local max_phrase_len=$(( W - 2 ))
  local display_phrase="$_SETUP_CUR_PHRASE"
  if (( ${#display_phrase} > max_phrase_len )); then
    display_phrase="${display_phrase:0:$((max_phrase_len - 3))}..."
  fi

  local display_step="$step_text"
  if (( ${#display_step} > max_phrase_len )); then
    display_step="${display_step:0:$((max_phrase_len - 3))}..."
  fi

  local hline
  hline=$(printf '%*s' "$W" "" | sed 's/ /─/g')

  local p_empty
  p_empty=$(printf '%*s' "$W" "")
  local p_title
  local p_title_pad=$(( W - 13 ))
  (( p_title_pad < 0 )) && p_title_pad=0
  p_title=$(printf '%*s' "$p_title_pad" "")
  local p_phrase
  local p_phrase_pad=$(( W - ${#display_phrase} - 2 ))
  (( p_phrase_pad < 0 )) && p_phrase_pad=0
  p_phrase=$(printf '%*s' "$p_phrase_pad" "")
  local p_bar
  local p_bar_pad=$(( W - bar_w - 4 ))
  (( p_bar_pad < 0 )) && p_bar_pad=0
  p_bar=$(printf '%*s' "$p_bar_pad" "")
  local p_step
  local p_step_pad=$(( W - ${#display_step} - 2 ))
  (( p_step_pad < 0 )) && p_step_pad=0
  p_step=$(printf '%*s' "$p_step_pad" "")

  echo ""
  printf '  %b┌%s┐%b\n' "${ACCENT_BRIGHT}" "$hline" "${RESET}"
  printf '  %b│%b%s%b│%b\n' "${ACCENT_BRIGHT}" "${RESET}" "$p_empty" "${ACCENT_BRIGHT}" "${RESET}"
  printf '  %b│%b  %b%bm u s t e r%b%s%b│%b\n' "${ACCENT_BRIGHT}" "${RESET}" "${BOLD}" "${ACCENT_BRIGHT}" "${RESET}" "$p_title" "${ACCENT_BRIGHT}" "${RESET}"
  printf '  %b│%b  %b%s%b%s%b│%b\n' "${ACCENT_BRIGHT}" "${RESET}" "${DIM}" "$display_phrase" "${RESET}" "$p_phrase" "${ACCENT_BRIGHT}" "${RESET}"
  printf '  %b│%b%s%b│%b\n' "${ACCENT_BRIGHT}" "${RESET}" "$p_empty" "${ACCENT_BRIGHT}" "${RESET}"
  printf '  %b│%b  %b%s%b%s%b  %s%b│%b\n' "${ACCENT_BRIGHT}" "${RESET}" "${ACCENT_BRIGHT}" "$bar_filled" "${GRAY}" "$bar_empty" "${RESET}" "$p_bar" "${ACCENT_BRIGHT}" "${RESET}"
  printf '  %b│%b  %b%s%b%s%b│%b\n' "${ACCENT_BRIGHT}" "${RESET}" "${DIM}" "$display_step" "${RESET}" "$p_step" "${ACCENT_BRIGHT}" "${RESET}"
  printf '  %b└%s┘%b\n' "${ACCENT_BRIGHT}" "$hline" "${RESET}"

  if [[ -n "$_SETUP_CUR_LABEL" ]]; then
    echo ""
    echo -e "  ${BOLD}${_SETUP_CUR_LABEL}${RESET}"
  fi

  local _sum_count=${#_SETUP_CUR_SUMMARY[@]}
  local _sum_i=0
  local s
  for s in "${_SETUP_CUR_SUMMARY[@]}"; do
    _sum_i=$((_sum_i + 1))
    if (( _sum_i == _sum_count )) && [[ "$_SETUP_CUR_PROMPT" == "true" ]]; then
      printf '%b' "$s"
    else
      echo -e "$s"
    fi
  done
}

_SETUP_SESSION_PHRASE=""

_setup_screen() {
  _SETUP_CUR_STEP="${1:-1}"
  _SETUP_CUR_LABEL="${2:-}"
  if [[ -z "$_SETUP_SESSION_PHRASE" ]]; then
    _SETUP_SESSION_PHRASE=$(_setup_pick_phrase)
  fi
  _SETUP_CUR_PHRASE="$_SETUP_SESSION_PHRASE"
  MUSTER_REDRAW_FN="_setup_redraw"
  _setup_screen_inner
}

# ── Sanitize service name to a config key ──
_svc_to_key() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

# ── Copy template hooks for a service, replacing placeholders ──
_setup_copy_hooks() {
  local stack="$1" svc_key="$2" svc_name="$3" hook_dir="$4"
  local template_dir="${MUSTER_ROOT}/templates/hooks/${stack}"

  if [[ ! -d "$template_dir" ]]; then
    # No templates for this stack, write stub hooks
    _setup_write_stub_hooks "$hook_dir"
    return
  fi

  local f
  for f in "${template_dir}"/*.sh; do
    [[ ! -f "$f" ]] && continue
    local basename
    basename=$(basename "$f")
    sed \
      -e "s/{{SERVICE_NAME}}/${svc_name}/g" \
      -e "s/{{NAMESPACE}}/default/g" \
      -e "s/{{PORT}}/8080/g" \
      -e "s/{{COMPOSE_FILE}}/docker-compose.yml/g" \
      "$f" > "${hook_dir}/${basename}"
    chmod +x "${hook_dir}/${basename}"
  done
}

_setup_write_stub_hooks() {
  local hook_dir="$1"

  cat > "${hook_dir}/deploy.sh" << 'HOOK'
#!/usr/bin/env bash
# Deploy hook — add your deploy commands here
echo "TODO: Add deploy commands"
exit 0
HOOK
  chmod +x "${hook_dir}/deploy.sh"

  cat > "${hook_dir}/health.sh" << 'HOOK'
#!/usr/bin/env bash
# Health check hook — exit 0 if healthy, exit 1 if not
echo "TODO: Add health check"
exit 0
HOOK
  chmod +x "${hook_dir}/health.sh"

  cat > "${hook_dir}/rollback.sh" << 'HOOK'
#!/usr/bin/env bash
# Rollback hook — add your rollback commands here
echo "TODO: Add rollback commands"
exit 0
HOOK
  chmod +x "${hook_dir}/rollback.sh"

  cat > "${hook_dir}/logs.sh" << 'HOOK'
#!/usr/bin/env bash
# Logs hook — stream logs for this service
echo "TODO: Add log streaming"
exit 0
HOOK
  chmod +x "${hook_dir}/logs.sh"

  cat > "${hook_dir}/cleanup.sh" << 'HOOK'
#!/usr/bin/env bash
# Cleanup hook — remove stale resources
echo "TODO: Add cleanup commands"
exit 0
HOOK
  chmod +x "${hook_dir}/cleanup.sh"
}

# ══════════════════════════════════════════════════════════════
# Non-interactive setup via flags
# ══════════════════════════════════════════════════════════════
_setup_noninteractive() {
  local flag_path="$1" flag_scan="$2" flag_stack="$3" flag_services="$4"
  local flag_order="$5" flag_name="$6"
  # flag_health and flag_creds are in global arrays _FLAG_HEALTH[] and _FLAG_CREDS[]

  # ── Resolve project path ──
  local project_path
  project_path="$(cd "$flag_path" 2>/dev/null && pwd)" || {
    err "Path does not exist: $flag_path"
    return 1
  }

  local stack="$flag_stack"
  local selected_services=()

  # ── Scan if requested ──
  if [[ "$flag_scan" == "true" ]]; then
    scan_project "$project_path"

    # Use scanned stack if not explicitly provided
    if [[ -z "$stack" && -n "$_SCAN_STACK" ]]; then
      stack="$_SCAN_STACK"
    fi

    # Use scanned services if not explicitly provided
    if [[ -z "$flag_services" && ${#_SCAN_SERVICES[@]} -gt 0 ]]; then
      selected_services=("${_SCAN_SERVICES[@]}")
    fi
  fi

  # ── Parse explicit services ──
  if [[ -n "$flag_services" ]]; then
    selected_services=()
    local IFS=','
    for s in $flag_services; do
      selected_services[${#selected_services[@]}]="$s"
    done
  fi

  # Default stack
  [[ -z "$stack" ]] && stack="bare"

  # Validate
  if [[ ${#selected_services[@]} -eq 0 ]]; then
    err "No services specified. Use --services or --scan to detect them."
    return 1
  fi

  # Validate stack value
  case "$stack" in
    k8s|compose|docker|bare) ;;
    *)
      err "Invalid stack: $stack (must be k8s, compose, docker, or bare)"
      return 1
      ;;
  esac

  # ── Deploy order ──
  local ordered_services=()
  if [[ -n "$flag_order" ]]; then
    local IFS=','
    for s in $flag_order; do
      ordered_services[${#ordered_services[@]}]="$s"
    done
  else
    ordered_services=("${selected_services[@]}")
  fi

  # ── Project name ──
  local project_name="${flag_name:-$(basename "$project_path")}"

  # ── Build health map from --health flags ──
  # _FLAG_HEALTH[] contains "svc=type:arg:arg" entries
  # Build parallel arrays for lookup
  local _h_keys=()
  local _h_vals=()
  local hi=0
  while (( hi < ${#_FLAG_HEALTH[@]} )); do
    local spec="${_FLAG_HEALTH[$hi]}"
    local h_svc="${spec%%=*}"
    local h_rest="${spec#*=}"
    _h_keys[${#_h_keys[@]}]="$h_svc"
    _h_vals[${#_h_vals[@]}]="$h_rest"
    hi=$((hi + 1))
  done

  # ── Build creds map from --creds flags ──
  local _c_keys=()
  local _c_vals=()
  local ci=0
  while (( ci < ${#_FLAG_CREDS[@]} )); do
    local spec="${_FLAG_CREDS[$ci]}"
    local c_svc="${spec%%=*}"
    local c_rest="${spec#*=}"
    _c_keys[${#_c_keys[@]}]="$c_svc"
    _c_vals[${#_c_vals[@]}]="$c_rest"
    ci=$((ci + 1))
  done

  # ── Build services JSON ──
  local services_json="{"
  local deploy_order_json="["
  local first=true

  for svc in "${ordered_services[@]}"; do
    local key
    key=$(_svc_to_key "$svc")

    # Look up health for this service
    local health_json="{\"enabled\":false}"
    local li=0
    while (( li < ${#_h_keys[@]} )); do
      if [[ "${_h_keys[$li]}" == "$svc" || "${_h_keys[$li]}" == "$key" ]]; then
        local h_spec="${_h_vals[$li]}"
        local h_type="${h_spec%%:*}"
        local h_args="${h_spec#*:}"

        case "$h_type" in
          http)
            local h_endpoint="${h_args%%:*}"
            local h_port="${h_args#*:}"
            [[ -z "$h_endpoint" ]] && h_endpoint="/health"
            [[ -z "$h_port" || "$h_port" == "$h_endpoint" ]] && h_port="8080"
            health_json="{\"type\":\"http\",\"endpoint\":\"${h_endpoint}\",\"port\":${h_port},\"timeout\":10,\"enabled\":true}"
            ;;
          tcp)
            local h_port="${h_args}"
            [[ -z "$h_port" ]] && h_port="0"
            health_json="{\"type\":\"tcp\",\"port\":${h_port},\"timeout\":5,\"enabled\":true}"
            ;;
          command)
            local h_cmd="${h_args}"
            health_json="{\"type\":\"command\",\"command\":\"${h_cmd}\",\"timeout\":10,\"enabled\":true}"
            ;;
          none)
            health_json="{\"enabled\":false}"
            ;;
        esac
        break
      fi
      li=$((li + 1))
    done

    # Look up creds for this service
    local cred_mode="off"
    li=0
    while (( li < ${#_c_keys[@]} )); do
      if [[ "${_c_keys[$li]}" == "$svc" || "${_c_keys[$li]}" == "$key" ]]; then
        cred_mode="${_c_vals[$li]}"
        break
      fi
      li=$((li + 1))
    done

    # Validate cred mode
    case "$cred_mode" in
      off|save|session|always) ;;
      *) cred_mode="off" ;;
    esac

    [[ "$first" == "true" ]] && first=false || services_json+=","
    services_json+="\"${key}\":{\"name\":\"${svc}\",\"health\":${health_json},\"credentials\":{\"mode\":\"${cred_mode}\"}}"
    deploy_order_json+="\"${key}\","
  done

  services_json+="}"
  deploy_order_json="${deploy_order_json%,}]"

  # ── Generate files ──
  local config_path="${project_path}/deploy.json"
  local muster_dir="${project_path}/.muster"

  mkdir -p "${muster_dir}/hooks"
  mkdir -p "${muster_dir}/logs"

  for svc in "${ordered_services[@]}"; do
    local key
    key=$(_svc_to_key "$svc")
    local hook_dir="${muster_dir}/hooks/${key}"
    mkdir -p "$hook_dir"
    _setup_copy_hooks "$stack" "$key" "$svc" "$hook_dir"
  done

  # Write deploy.json
  if has_cmd jq; then
    echo "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" | jq '.' > "$config_path"
  elif has_cmd python3; then
    python3 -c "
import json, sys
data = json.loads(sys.argv[1])
print(json.dumps(data, indent=2))
" "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" > "$config_path"
  else
    echo "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" > "$config_path"
  fi

  # .gitignore
  local gitignore="${project_path}/.gitignore"
  if [[ -f "$gitignore" ]]; then
    grep -q '.muster/logs' "$gitignore" || echo '.muster/logs/' >> "$gitignore"
  else
    echo '.muster/logs/' > "$gitignore"
  fi

  # ── Print summary (plain text, no TUI) ──
  local stack_display=""
  case "$stack" in
    k8s)     stack_display="Kubernetes" ;;
    compose) stack_display="Docker Compose" ;;
    docker)  stack_display="Docker" ;;
    bare)    stack_display="Bare metal" ;;
  esac

  ok "Setup complete"
  echo ""
  echo "  Project:  ${project_name}"
  echo "  Root:     ${project_path}"
  echo "  Stack:    ${stack_display}"
  echo "  Config:   ${config_path}"
  echo ""
  echo "  Services:"
  for svc in "${ordered_services[@]}"; do
    local key
    key=$(_svc_to_key "$svc")
    echo "    ${svc}  →  .muster/hooks/${key}/"
  done
  echo ""
  echo "  Next: review hooks in .muster/hooks/ then run 'muster'"
}

# ══════════════════════════════════════════════════════════════
# Main setup command
# ══════════════════════════════════════════════════════════════
_FLAG_HEALTH=()
_FLAG_CREDS=()

cmd_setup() {
  # ── Parse flags ──
  local flag_path="" flag_scan="false" flag_stack="" flag_services=""
  local flag_order="" flag_name=""
  _FLAG_HEALTH=()
  _FLAG_CREDS=()
  local has_flags=false

  while [[ $# -gt 0 ]]; do
    has_flags=true
    case "$1" in
      --path|-p)
        flag_path="$2"; shift 2 ;;
      --scan)
        flag_scan="true"; shift ;;
      --stack|-s)
        flag_stack="$2"; shift 2 ;;
      --services)
        flag_services="$2"; shift 2 ;;
      --order)
        flag_order="$2"; shift 2 ;;
      --health)
        _FLAG_HEALTH[${#_FLAG_HEALTH[@]}]="$2"; shift 2 ;;
      --creds)
        _FLAG_CREDS[${#_FLAG_CREDS[@]}]="$2"; shift 2 ;;
      --name|-n)
        flag_name="$2"; shift 2 ;;
      --help|-h)
        echo "Usage: muster setup [flags]"
        echo ""
        echo "Without flags, runs the interactive setup wizard."
        echo ""
        echo "Flags:"
        echo "  --path, -p <dir>      Project directory (default: .)"
        echo "  --scan                Auto-detect stack and services from project files"
        echo "  --stack, -s <type>    Stack: k8s, compose, docker, bare"
        echo "  --services <list>     Comma-separated service names"
        echo "  --order <list>        Comma-separated deploy order (default: services order)"
        echo "  --health <spec>       Per-service health: svc=type[:arg:arg] (repeatable)"
        echo "  --creds <spec>        Per-service credentials: svc=mode (repeatable)"
        echo "  --name, -n <name>     Project name (default: directory basename)"
        echo ""
        echo "Health spec examples:"
        echo "  --health api=http:/health:8080"
        echo "  --health redis=tcp:6379"
        echo "  --health worker=command:./check.sh"
        echo "  --health api=none"
        echo ""
        echo "Credential modes: off, save, session, always"
        echo ""
        echo "Examples:"
        echo "  muster setup --path /app --scan"
        echo "  muster setup --stack k8s --services api,redis --name myapp"
        echo "  muster setup --scan --health api=http:/health:3000 --name myapp"
        return 0
        ;;
      *)
        err "Unknown flag: $1"
        echo "Run 'muster setup --help' for usage."
        return 1
        ;;
    esac
  done

  # If flags were provided, run non-interactive
  if [[ "$has_flags" == "true" ]]; then
    [[ -z "$flag_path" ]] && flag_path="."
    _setup_noninteractive "$flag_path" "$flag_scan" "$flag_stack" "$flag_services" "$flag_order" "$flag_name"
    return $?
  fi

  # ── Interactive TUI wizard ──

  # ── Step 1: Project root ──
  local _plat_tools=""
  [[ "$MUSTER_HAS_DOCKER" == "true" ]] && _plat_tools+="docker "
  [[ "$MUSTER_HAS_KUBECTL" == "true" ]] && _plat_tools+="kubectl "
  [[ "$MUSTER_HAS_JQ" == "true" ]] && _plat_tools+="jq "
  [[ "$MUSTER_HAS_PYTHON" == "true" ]] && _plat_tools+="python3 "
  local _plat_kc="not available (will use encrypted vault)"
  [[ "$MUSTER_HAS_KEYCHAIN" == "true" ]] && _plat_kc="available"

  _SETUP_CUR_SUMMARY=(
    ""
    "  ${DIM}${MUSTER_OS} ${MUSTER_ARCH}${RESET}"
    "  ${DIM}tools: ${_plat_tools}${RESET}"
    "  ${DIM}keychain: ${_plat_kc}${RESET}"
    ""
    "  ${BOLD}Where is your project?${RESET}"
    "  ${DIM}Enter path or press enter for parent directory${RESET}"
    ""
    "  ${ACCENT}>${RESET} "
  )
  _SETUP_CUR_PROMPT="true"

  _setup_screen 1 "Project location"
  read -r project_path
  _SETUP_CUR_PROMPT="false"

  project_path="${project_path:-..}"
  project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
    err "Path does not exist: $project_path"
    return 1
  }

  # ── Step 2: Scan project ──
  _SETUP_CUR_SUMMARY=("")
  _setup_screen 2 "Scanning project"
  echo ""
  start_spinner "Scanning ${project_path}..."
  scan_project "$project_path"
  stop_spinner

  if (( ${#_SCAN_FILES[@]} > 0 )); then
    # ────── Scan-first flow ──────
    scan_print_results
    echo ""
    sleep 1

    # ── Step 3: Confirm stack + select services ──
    local stack="$_SCAN_STACK"

    if [[ -n "$stack" ]]; then
      local stack_label=""
      case "$stack" in
        k8s)     stack_label="Kubernetes" ;;
        compose) stack_label="Docker Compose" ;;
        docker)  stack_label="Docker" ;;
        bare)    stack_label="Bare metal / Systemd" ;;
      esac

      _SETUP_CUR_SUMMARY=("")
      _setup_screen 3 "Confirm stack"
      menu_select "Detected ${stack_label}. Correct?" "Yes" "No, let me pick"

      if [[ "$MENU_RESULT" == "No, let me pick" ]]; then
        _SETUP_CUR_SUMMARY=("")
        _setup_screen 3 "Select stack"
        menu_select "What deploys your services?" "Kubernetes" "Docker Compose" "Docker (standalone)" "Bare metal / Systemd"
        case "$MENU_RESULT" in
          Kubernetes)              stack="k8s" ;;
          "Docker Compose")        stack="compose" ;;
          "Docker (standalone)")   stack="docker" ;;
          "Bare metal / Systemd")  stack="bare" ;;
        esac
      fi
    else
      # Stack not detected, ask
      _SETUP_CUR_SUMMARY=("")
      _setup_screen 3 "Select stack"
      menu_select "How do you deploy?" "Kubernetes" "Docker Compose" "Docker (standalone)" "Bare metal / Systemd"
      case "$MENU_RESULT" in
        Kubernetes)              stack="k8s" ;;
        "Docker Compose")        stack="compose" ;;
        "Docker (standalone)")   stack="docker" ;;
        "Bare metal / Systemd")  stack="bare" ;;
      esac
    fi

    # Select services from scan results
    if (( ${#_SCAN_SERVICES[@]} > 0 )); then
      _SETUP_CUR_SUMMARY=("")
      _setup_screen 3 "Select services"
      checklist_select "Manage these services?" "${_SCAN_SERVICES[@]}"

      local selected_services=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && selected_services[${#selected_services[@]}]="$line"
      done <<< "$CHECKLIST_RESULT"
    else
      # No services detected, ask for names
      _SETUP_CUR_SUMMARY=(
        ""
        "  ${DIM}Enter service names separated by spaces${RESET}"
        "  ${DIM}Example: api worker redis${RESET}"
        ""
        "  ${ACCENT}>${RESET} "
      )
      _SETUP_CUR_PROMPT="true"
      _setup_screen 3 "Name your services"
      read -r svc_input
      _SETUP_CUR_PROMPT="false"

      local selected_services=()
      for s in $svc_input; do
        selected_services[${#selected_services[@]}]="$s"
      done
    fi

    if [[ ${#selected_services[@]} -eq 0 ]]; then
      warn "No services selected."
      return 1
    fi

    # ── Step 4: Deploy order ──
    _SETUP_CUR_SUMMARY=("")
    _setup_screen 4 "Deploy order"

    if (( ${#selected_services[@]} > 1 )); then
      order_select "What order should services deploy?" "${selected_services[@]}"
      selected_services=("${ORDER_RESULT[@]}")
    else
      echo -e "\n  ${GREEN}1.${RESET} ${selected_services[0]}"
    fi

    # ── Step 5: Per-service config (health + credentials) ──
    local services_json="{"
    local deploy_order_json="["
    local first=true
    local svc_index=0

    for svc in "${selected_services[@]}"; do
      svc_index=$((svc_index + 1))
      local key
      key=$(_svc_to_key "$svc")

      # Health check
      _SETUP_CUR_SUMMARY=("")
      _setup_screen 5 "Configure ${svc} (${svc_index}/${#selected_services[@]})"
      menu_select "Health check for ${svc}?" "HTTP" "TCP" "Command" "None"
      local health_choice="$MENU_RESULT"

      local health_json="{}"
      case "$health_choice" in
        HTTP)
          printf "\n  ${ACCENT}>${RESET} Health endpoint [/health]: "
          read -r endpoint
          printf "  ${ACCENT}>${RESET} Port [8080]: "
          read -r port_num
          health_json="{\"type\":\"http\",\"endpoint\":\"${endpoint:-/health}\",\"port\":${port_num:-8080},\"timeout\":10,\"enabled\":true}"
          ;;
        TCP)
          printf "\n  ${ACCENT}>${RESET} Port: "
          read -r port_num
          health_json="{\"type\":\"tcp\",\"port\":${port_num:-0},\"timeout\":5,\"enabled\":true}"
          ;;
        Command)
          printf "\n  ${ACCENT}>${RESET} Health command: "
          read -r health_cmd
          health_json="{\"type\":\"command\",\"command\":\"${health_cmd}\",\"timeout\":10,\"enabled\":true}"
          ;;
        None)
          health_json="{\"enabled\":false}"
          ;;
      esac

      # Credentials
      _SETUP_CUR_SUMMARY=(
        ""
        "  ${GREEN}*${RESET} Health: ${health_choice}"
      )
      _setup_screen 5 "Configure ${svc} (${svc_index}/${#selected_services[@]})"
      menu_select "Credentials for ${svc}?" "None" "Save always (keychain)" "Once per session" "Every time"
      local cred_choice="$MENU_RESULT"

      local cred_mode="off"
      case "$cred_choice" in
        "Save always (keychain)") cred_mode="save" ;;
        "Once per session")       cred_mode="session" ;;
        "Every time")             cred_mode="always" ;;
      esac

      [[ "$first" == "true" ]] && first=false || services_json+=","
      services_json+="\"${key}\":{\"name\":\"${svc}\",\"health\":${health_json},\"credentials\":{\"mode\":\"${cred_mode}\"}}"
      deploy_order_json+="\"${key}\","
    done

    services_json+="}"
    deploy_order_json="${deploy_order_json%,}]"

    # ── Step 6: Project name ──
    local project_name
    project_name=$(basename "$project_path")
    _SETUP_CUR_SUMMARY=(
      ""
      "  ${ACCENT}>${RESET} Project name [${project_name}]: "
    )
    _SETUP_CUR_PROMPT="true"
    _setup_screen 6 "Project name"
    read -r custom_name
    _SETUP_CUR_PROMPT="false"
    project_name="${custom_name:-$project_name}"

    # ── Step 7: Generate ──
    local config_path="${project_path}/deploy.json"
    local muster_dir="${project_path}/.muster"

    mkdir -p "${muster_dir}/hooks"
    mkdir -p "${muster_dir}/logs"

    # Copy template hooks for each service
    local generated_hooks=()
    for svc in "${selected_services[@]}"; do
      local key
      key=$(_svc_to_key "$svc")
      local hook_dir="${muster_dir}/hooks/${key}"
      mkdir -p "$hook_dir"
      _setup_copy_hooks "$stack" "$key" "$svc" "$hook_dir"
      generated_hooks[${#generated_hooks[@]}]=".muster/hooks/${key}/"
    done

    # Write deploy.json
    if has_cmd jq; then
      echo "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" | jq '.' > "$config_path"
    elif has_cmd python3; then
      python3 -c "
import json, sys
data = json.loads(sys.argv[1])
print(json.dumps(data, indent=2))
" "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" > "$config_path"
    else
      echo "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" > "$config_path"
    fi

    # .gitignore
    local gitignore="${project_path}/.gitignore"
    if [[ -f "$gitignore" ]]; then
      grep -q '.muster/logs' "$gitignore" || echo '.muster/logs/' >> "$gitignore"
    else
      echo '.muster/logs/' > "$gitignore"
    fi

    # Stack label for display
    local stack_display=""
    case "$stack" in
      k8s)     stack_display="Kubernetes" ;;
      compose) stack_display="Docker Compose" ;;
      docker)  stack_display="Docker" ;;
      bare)    stack_display="Bare metal" ;;
    esac

    # ── Done screen ──
    _SETUP_CUR_SUMMARY=(
      ""
      "  ${GREEN}*${RESET} Project: ${BOLD}${project_name}${RESET}"
      "  ${GREEN}*${RESET} Root:    ${project_path}"
      "  ${GREEN}*${RESET} Stack:   ${stack_display}"
      "  ${GREEN}*${RESET} Config:  ${config_path}"
      ""
      "  ${BOLD}Generated:${RESET}"
      "    deploy.json"
    )

    for h in "${generated_hooks[@]}"; do
      local hook_path="${muster_dir}/hooks/${h##*.muster/hooks/}"
      local hook_files=""
      for hf in "${hook_path}"*.sh; do
        [[ -f "$hf" ]] && hook_files="${hook_files} $(basename "$hf")"
      done
      _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="    ${h}  ${DIM}${hook_files}${RESET}"
    done

    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]=""
    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${ACCENT}Next steps:${RESET}"
    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${DIM}1. Review hooks in .muster/hooks/ (look for TODO comments)${RESET}"
    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${DIM}2. Run ${BOLD}muster${RESET}${DIM} to open the dashboard${RESET}"
    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]=""
    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${DIM}Press enter to exit${RESET}"
    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]=""

    _SETUP_CUR_PROMPT="false"
    _setup_screen 7 "Setup complete"
    read -rs

  else
    # ────── Fallback: manual question flow ──────
    _setup_manual_flow
  fi
}

# ══════════════════════════════════════════════════════════════
# Manual fallback (no files detected)
# ══════════════════════════════════════════════════════════════
_setup_manual_flow() {
  info "No project files detected. Let's set things up manually."
  echo ""
  sleep 1

  # ── Step 3: Stack questions ──
  local has_db="no" db_type="" has_api="no" api_type=""
  local has_workers="no" has_proxy="no" stack="bare"

  _SETUP_CUR_SUMMARY=("")
  _setup_screen 3 "Your stack"
  menu_select "Do you manage a database here?" "Yes" "No"
  if [[ "$MENU_RESULT" == "Yes" ]]; then
    has_db="yes"
    _SETUP_CUR_SUMMARY=("")
    _setup_screen 3 "Your stack"
    menu_select "What kind of database?" "PostgreSQL" "MySQL" "Redis" "MongoDB" "SQLite" "Other"
    db_type="$MENU_RESULT"
  fi

  _SETUP_CUR_SUMMARY=("")
  _setup_screen 3 "Your stack"
  menu_select "Do you have a web server or API?" "Yes" "No"
  if [[ "$MENU_RESULT" == "Yes" ]]; then
    has_api="yes"
    _SETUP_CUR_SUMMARY=("")
    _setup_screen 3 "Your stack"
    menu_select "What runs it?" "Docker" "Node.js" "Go" "Python" "Rust" "Other"
    api_type="$MENU_RESULT"
  fi

  _SETUP_CUR_SUMMARY=("")
  _setup_screen 3 "Your stack"
  menu_select "Any background workers or jobs?" "Yes" "No"
  [[ "$MENU_RESULT" == "Yes" ]] && has_workers="yes"

  _SETUP_CUR_SUMMARY=("")
  _setup_screen 3 "Your stack"
  menu_select "Any reverse proxy (nginx, caddy, etc)?" "Yes" "No"
  [[ "$MENU_RESULT" == "Yes" ]] && has_proxy="yes"

  _SETUP_CUR_SUMMARY=("")
  _setup_screen 3 "Your stack"
  menu_select "Do you use containers?" "Docker Compose" "Kubernetes" "Docker (standalone)" "None"
  case "$MENU_RESULT" in
    "Docker Compose")        stack="compose" ;;
    Kubernetes)              stack="k8s" ;;
    "Docker (standalone)")   stack="docker" ;;
    None)                    stack="bare" ;;
  esac

  # ── Step 4: Build service list + select ──
  local service_list=()
  [[ "$has_api" == "yes" ]] && service_list[${#service_list[@]}]="api"
  [[ "$has_db" == "yes" ]] && service_list[${#service_list[@]}]="$(_svc_to_key "$db_type")"
  [[ "$has_workers" == "yes" ]] && service_list[${#service_list[@]}]="worker"
  [[ "$has_proxy" == "yes" ]] && service_list[${#service_list[@]}]="proxy"

  if [[ ${#service_list[@]} -eq 0 ]]; then
    warn "No services defined. Add at least one service."
    return 1
  fi

  _SETUP_CUR_SUMMARY=("")
  _setup_screen 4 "Select services"
  checklist_select "Select services to manage" "${service_list[@]}"

  local selected_services=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && selected_services[${#selected_services[@]}]="$line"
  done <<< "$CHECKLIST_RESULT"

  if [[ ${#selected_services[@]} -eq 0 ]]; then
    warn "No services selected."
    return 1
  fi

  # Deploy order
  if (( ${#selected_services[@]} > 1 )); then
    _SETUP_CUR_SUMMARY=("")
    _setup_screen 4 "Deploy order"
    order_select "What order should services deploy?" "${selected_services[@]}"
    selected_services=("${ORDER_RESULT[@]}")
  fi

  # ── Step 5: Per-service config ──
  local services_json="{"
  local deploy_order_json="["
  local first=true
  local svc_index=0

  for svc in "${selected_services[@]}"; do
    svc_index=$((svc_index + 1))
    local key
    key=$(_svc_to_key "$svc")

    _SETUP_CUR_SUMMARY=("")
    _setup_screen 5 "Configure ${svc} (${svc_index}/${#selected_services[@]})"
    menu_select "Health check type for ${svc}?" "HTTP" "TCP" "Command" "None"
    local health_choice="$MENU_RESULT"

    local health_json="{}"
    case "$health_choice" in
      HTTP)
        printf "\n  ${ACCENT}>${RESET} Health endpoint [/health]: "
        read -r endpoint
        printf "  ${ACCENT}>${RESET} Port [8080]: "
        read -r port_num
        health_json="{\"type\":\"http\",\"endpoint\":\"${endpoint:-/health}\",\"port\":${port_num:-8080},\"timeout\":10,\"enabled\":true}"
        ;;
      TCP)
        printf "\n  ${ACCENT}>${RESET} Port: "
        read -r port_num
        health_json="{\"type\":\"tcp\",\"port\":${port_num:-0},\"timeout\":5,\"enabled\":true}"
        ;;
      Command)
        printf "\n  ${ACCENT}>${RESET} Health command: "
        read -r health_cmd
        health_json="{\"type\":\"command\",\"command\":\"${health_cmd}\",\"timeout\":10,\"enabled\":true}"
        ;;
      None)
        health_json="{\"enabled\":false}"
        ;;
    esac

    # Credentials
    _SETUP_CUR_SUMMARY=(
      ""
      "  ${GREEN}*${RESET} Health: ${health_choice}"
    )
    _setup_screen 5 "Configure ${svc} (${svc_index}/${#selected_services[@]})"
    menu_select "Credentials for ${svc}?" "None" "Save always (keychain)" "Once per session" "Every time"
    local cred_choice="$MENU_RESULT"

    local cred_mode="off"
    case "$cred_choice" in
      "Save always (keychain)") cred_mode="save" ;;
      "Once per session")       cred_mode="session" ;;
      "Every time")             cred_mode="always" ;;
    esac

    [[ "$first" == "true" ]] && first=false || services_json+=","
    services_json+="\"${key}\":{\"name\":\"${svc}\",\"health\":${health_json},\"credentials\":{\"mode\":\"${cred_mode}\"}}"
    deploy_order_json+="\"${key}\","
  done

  services_json+="}"
  deploy_order_json="${deploy_order_json%,}]"

  # ── Step 6: Project name ──
  local project_name
  project_name=$(basename "$project_path")
  _SETUP_CUR_SUMMARY=(
    ""
    "  ${ACCENT}>${RESET} Project name [${project_name}]: "
  )
  _SETUP_CUR_PROMPT="true"
  _setup_screen 6 "Project name"
  read -r custom_name
  _SETUP_CUR_PROMPT="false"
  project_name="${custom_name:-$project_name}"

  # ── Step 7: Generate ──
  local config_path="${project_path}/deploy.json"
  local muster_dir="${project_path}/.muster"

  mkdir -p "${muster_dir}/hooks"
  mkdir -p "${muster_dir}/logs"

  for svc in "${selected_services[@]}"; do
    local key
    key=$(_svc_to_key "$svc")
    local hook_dir="${muster_dir}/hooks/${key}"
    mkdir -p "$hook_dir"
    _setup_copy_hooks "$stack" "$key" "$svc" "$hook_dir"
  done

  if has_cmd jq; then
    echo "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" | jq '.' > "$config_path"
  elif has_cmd python3; then
    python3 -c "
import json, sys
data = json.loads(sys.argv[1])
print(json.dumps(data, indent=2))
" "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" > "$config_path"
  else
    echo "{\"project\":\"${project_name}\",\"version\":\"1\",\"root\":\"${project_path}\",\"services\":${services_json},\"deploy_order\":${deploy_order_json},\"skills\":[]}" > "$config_path"
  fi

  local gitignore="${project_path}/.gitignore"
  if [[ -f "$gitignore" ]]; then
    grep -q '.muster/logs' "$gitignore" || echo '.muster/logs/' >> "$gitignore"
  else
    echo '.muster/logs/' > "$gitignore"
  fi

  _SETUP_CUR_SUMMARY=(
    ""
    "  ${GREEN}*${RESET} Project: ${BOLD}${project_name}${RESET}"
    "  ${GREEN}*${RESET} Root:    ${project_path}"
    "  ${GREEN}*${RESET} Config:  ${config_path}"
    "  ${GREEN}*${RESET} Hooks:   ${muster_dir}/hooks/"
    ""
    "  ${ACCENT}Next steps:${RESET}"
    "  ${DIM}1. Review hooks in .muster/hooks/ (look for TODO comments)${RESET}"
    "  ${DIM}2. Run ${BOLD}muster${RESET}${DIM} to open the dashboard${RESET}"
    ""
    "  ${DIM}Press enter to exit${RESET}"
    ""
  )

  _SETUP_CUR_PROMPT="false"
  _setup_screen 7 "Setup complete"
  read -rs
}
