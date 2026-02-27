#!/usr/bin/env bash
# muster/lib/commands/setup.sh — Guided setup wizard

source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/checklist.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"

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
_SETUP_CUR_PROMPT="false"    # if true, last summary line is a prompt (no trailing newline)

# Called by WINCH trap to redraw on resize
# Only redraws when at a read prompt (safe). During menus/checklists,
# the next step transition will adapt to the new size.
_setup_redraw() {
  if [[ "$_SETUP_CUR_PROMPT" == "true" ]]; then
    _setup_screen_inner
  fi
}

# Draw the banner + label + summary (full screen, used on step transitions)
_setup_screen_inner() {
  clear
  update_term_size

  # W = inner width between │ borders. Total line = 2 (margin) + 1 (│) + W + 1 (│) = W + 4
  # Must fit within TERM_COLS to avoid wrapping
  local W=$(( TERM_COLS - 4 ))
  (( W > 56 )) && W=56
  (( W < 10 )) && W=10

  # Progress bar
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

  # Truncate phrase to fit box
  local max_phrase_len=$(( W - 2 ))
  local display_phrase="$_SETUP_CUR_PHRASE"
  if (( ${#display_phrase} > max_phrase_len )); then
    display_phrase="${display_phrase:0:$((max_phrase_len - 3))}..."
  fi

  # Truncate step text if needed
  local display_step="$step_text"
  if (( ${#display_step} > max_phrase_len )); then
    display_step="${display_step:0:$((max_phrase_len - 3))}..."
  fi

  # Build horizontal border using printf repeat
  local hline
  hline=$(printf '%*s' "$W" "" | sed 's/ /─/g')

  # Build padding strings (plain spaces, no ANSI)
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

  # Draw box using printf (no echo -e on mixed content)
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

  # Redraw summary lines (last line uses printf to keep cursor on same line for prompts)
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

# Public: set state and draw
# Pick phrase once per session (on first call)
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

# Helper: build summary lines for step 2
_build_stack_summary() {
  _SETUP_CUR_PROMPT="false"
  _SETUP_CUR_SUMMARY=("")
  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${DIM}Project: ${project_path}${RESET}"
  [[ "$has_db" == "yes" && -n "$db_type" ]] && _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${GREEN}*${RESET} Database: ${db_type}"
  [[ "$has_db" == "yes" && -z "$db_type" ]] && _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${GREEN}*${RESET} Database: yes"
  [[ "$has_api" == "yes" && -n "$api_type" ]] && _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${GREEN}*${RESET} API/Web: ${api_type}"
  [[ "$has_api" == "yes" && -z "$api_type" ]] && _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${GREEN}*${RESET} API/Web: yes"
  [[ "$has_workers" == "yes" ]] && _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${GREEN}*${RESET} Workers: yes"
  [[ "$has_proxy" == "yes" ]] && _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${GREEN}*${RESET} Proxy: yes"
}

cmd_setup() {
  # ── Step 1: Project root ──
  # Build platform info lines for summary (so resize redraw can reproduce them)
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
    exit 1
  }

  # ── Step 2: Conversational questions ──
  local has_db="no" db_type="" has_api="no" api_type=""
  local has_workers="no" has_proxy="no" container_type="none"

  _build_stack_summary
  _setup_screen 2 "Your stack"
  menu_select "Do you manage a database here?" "Yes" "No"
  if [[ "$MENU_RESULT" == "Yes" ]]; then
    has_db="yes"
    _build_stack_summary
    _setup_screen 2 "Your stack"
    menu_select "What kind of database?" "PostgreSQL" "MySQL" "Redis" "MongoDB" "SQLite" "Other"
    db_type="$MENU_RESULT"
  fi

  _build_stack_summary
  _setup_screen 2 "Your stack"
  menu_select "Do you have a web server or API?" "Yes" "No"
  if [[ "$MENU_RESULT" == "Yes" ]]; then
    has_api="yes"
    _build_stack_summary
    _setup_screen 2 "Your stack"
    menu_select "What runs it?" "Docker" "Node.js" "Go" "Python" "Rust" "Other"
    api_type="$MENU_RESULT"
  fi

  _build_stack_summary
  _setup_screen 2 "Your stack"
  menu_select "Any background workers or jobs?" "Yes" "No"
  [[ "$MENU_RESULT" == "Yes" ]] && has_workers="yes"

  _build_stack_summary
  _setup_screen 2 "Your stack"
  menu_select "Any reverse proxy (nginx, caddy, etc)?" "Yes" "No"
  [[ "$MENU_RESULT" == "Yes" ]] && has_proxy="yes"

  _build_stack_summary
  _setup_screen 2 "Your stack"
  menu_select "Do you use containers?" "Docker Compose" "Kubernetes" "Docker (standalone)" "None"
  container_type="$MENU_RESULT"

  # ── Step 3: Scan project directory ──
  _SETUP_CUR_SUMMARY=("")
  _setup_screen 3 "Scanning project"
  echo ""
  start_spinner "Scanning ${project_path}..."
  sleep 1

  local detected_files=()
  local detected_labels=()

  [[ -f "${project_path}/Dockerfile" ]] && detected_files[${#detected_files[@]}]="Dockerfile" && detected_labels[${#detected_labels[@]}]="Dockerfile found"
  [[ -f "${project_path}/docker-compose.yml" || -f "${project_path}/docker-compose.yaml" || -f "${project_path}/compose.yml" ]] && detected_files[${#detected_files[@]}]="docker-compose" && detected_labels[${#detected_labels[@]}]="Docker Compose config"
  [[ -f "${project_path}/package.json" ]] && detected_files[${#detected_files[@]}]="package.json" && detected_labels[${#detected_labels[@]}]="Node.js project"
  [[ -f "${project_path}/go.mod" ]] && detected_files[${#detected_files[@]}]="go.mod" && detected_labels[${#detected_labels[@]}]="Go module"
  [[ -f "${project_path}/Cargo.toml" ]] && detected_files[${#detected_files[@]}]="Cargo.toml" && detected_labels[${#detected_labels[@]}]="Rust project"
  [[ -f "${project_path}/requirements.txt" || -f "${project_path}/pyproject.toml" ]] && detected_files[${#detected_files[@]}]="python" && detected_labels[${#detected_labels[@]}]="Python project"
  [[ -d "${project_path}/k8s" || -d "${project_path}/kubernetes" ]] && detected_files[${#detected_files[@]}]="k8s" && detected_labels[${#detected_labels[@]}]="Kubernetes manifests"
  [[ -f "${project_path}/nginx.conf" ]] && detected_files[${#detected_files[@]}]="nginx" && detected_labels[${#detected_labels[@]}]="Nginx config"
  [[ -f "${project_path}/redis.conf" ]] && detected_files[${#detected_files[@]}]="redis" && detected_labels[${#detected_labels[@]}]="Redis config"

  stop_spinner

  if [[ ${#detected_files[@]} -gt 0 ]]; then
    info "Found in ${project_path}:"
    for label in "${detected_labels[@]}"; do
      echo -e "    ${GREEN}*${RESET} ${label}"
    done
  else
    info "No known project files detected. That's fine."
  fi

  sleep 1

  # ── Step 4: Service checklist ──
  local service_list=()

  [[ "$has_api" == "yes" ]] && service_list[${#service_list[@]}]="API Server (${api_type})"
  [[ "$has_db" == "yes" ]] && service_list[${#service_list[@]}]="${db_type}"
  [[ "$has_workers" == "yes" ]] && service_list[${#service_list[@]}]="Background Worker"
  [[ "$has_proxy" == "yes" ]] && service_list[${#service_list[@]}]="Reverse Proxy"

  if [[ ${#service_list[@]} -eq 0 ]]; then
    warn "No services defined. Add at least one service."
    exit 1
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
    exit 1
  fi

  # ── Step 5: Per-service config ──
  local services_json="{"
  local deploy_order_json="["
  local first=true
  local svc_index=0

  for svc in "${selected_services[@]}"; do
    svc_index=$((svc_index + 1))
    local key
    key=$(echo "$svc" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')

    _SETUP_CUR_SUMMARY=("")
    _setup_screen 5 "Configure ${svc} (${svc_index}/${#selected_services[@]})"

    menu_select "Health check type for ${svc}?" "HTTP" "TCP" "Command" "None"
    local health_choice="$MENU_RESULT"

    local health_json="{}"
    case "$health_choice" in
      HTTP)
        printf "\n  ${ACCENT}>${RESET} Health endpoint: "
        read -r endpoint
        printf "  ${ACCENT}>${RESET} Port: "
        read -r port_num
        health_json="{\"type\":\"http\",\"endpoint\":\"${endpoint:-/health}\",\"port\":${port_num:-8080},\"timeout\":10}"
        ;;
      TCP)
        printf "\n  ${ACCENT}>${RESET} Port: "
        read -r port_num
        health_json="{\"type\":\"tcp\",\"port\":${port_num:-0},\"timeout\":5}"
        ;;
      Command)
        printf "\n  ${ACCENT}>${RESET} Health command: "
        read -r health_cmd
        health_json="{\"type\":\"command\",\"command\":\"${health_cmd}\",\"timeout\":10}"
        ;;
      None)
        health_json="null"
        ;;
    esac

    # Credentials
    _SETUP_CUR_SUMMARY=(
      ""
      "  ${GREEN}*${RESET} Health: ${health_choice}"
      ""
      "  ${YELLOW}! HIGH RISK${RESET}: Store superuser credentials for ${svc}?"
      "  ${DIM}Credentials stored in system keychain or encrypted vault.${RESET}"
      "  ${DIM}NEVER in deploy.json or committed to git.${RESET}"
    )
    _setup_screen 5 "Configure ${svc} (${svc_index}/${#selected_services[@]})"
    menu_select "Store credentials?" "No, prompt each time (recommended)" "Yes, store securely"
    local cred_choice="$MENU_RESULT"

    local cred_json='{"enabled":false}'
    if [[ "$cred_choice" == "Yes, store securely" ]]; then
      cred_json='{"enabled":true,"risk_level":"high"}'
    fi

    [[ "$first" == "true" ]] && first=false || services_json+=","
    services_json+="\"${key}\":{\"name\":\"${svc}\",\"health\":${health_json},\"credentials\":${cred_json}}"
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

  # ── Step 7: Write config ──
  local config_path="${project_path}/deploy.json"
  local muster_dir="${project_path}/.muster"

  mkdir -p "${muster_dir}/hooks"
  mkdir -p "${muster_dir}/logs"

  for svc in "${selected_services[@]}"; do
    local key
    key=$(echo "$svc" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
    local hook_dir="${muster_dir}/hooks/${key}"
    mkdir -p "$hook_dir"

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

  # ── Done screen ──
  _SETUP_CUR_SUMMARY=(
    ""
    "  ${GREEN}*${RESET} Project: ${BOLD}${project_name}${RESET}"
    "  ${GREEN}*${RESET} Root:    ${project_path}"
    "  ${GREEN}*${RESET} Config:  ${config_path}"
    "  ${GREEN}*${RESET} Hooks:   ${muster_dir}/hooks/"
    ""
    "  ${BOLD}Services:${RESET}"
  )

  for svc in "${selected_services[@]}"; do
    _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="    ${GREEN}*${RESET} ${svc}"
  done

  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]=""
  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${ACCENT}Next steps:${RESET}"
  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${DIM}1. Edit hook scripts in .muster/hooks/${RESET}"
  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${DIM}2. Run ${BOLD}muster${RESET}${DIM} to open the dashboard${RESET}"
  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]=""
  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]="  ${DIM}Press enter to exit${RESET}"
  _SETUP_CUR_SUMMARY[${#_SETUP_CUR_SUMMARY[@]}]=""

  _SETUP_CUR_PROMPT="false"
  _setup_screen 7 "Setup complete"

  # Wait for Enter — read -rs (no -n) consumes buffered chars until newline,
  # which avoids the bash 3.2 fractional-timeout issue with -t 0.1
  read -rs
}
