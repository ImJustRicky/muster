#!/usr/bin/env bash
# muster/lib/commands/setup.sh — Guided setup wizard

source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/checklist.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"

cmd_setup() {
  clear
  local w=$(( TERM_COLS - 4 ))
  (( w > 60 )) && w=60
  local border
  border=$(printf '─%.0s' $(seq 1 "$w"))

  echo ""
  echo -e "  ${AMBER}┌${border}┐${RESET}"
  printf "  ${AMBER}│${RESET} %-$((w - 2))s ${AMBER}│${RESET}\n" "muster setup"
  echo -e "  ${AMBER}└${border}┘${RESET}"
  echo ""

  # ── Step 1: Project root ──
  echo -e "  ${BOLD}Where is your project?${RESET}"
  echo -e "  ${DIM}Enter path or press enter for parent directory${RESET}\n"
  printf "  ${CYAN}>${RESET} "
  read -r project_path
  project_path="${project_path:-..}"

  # Expand to absolute path
  project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
    err "Path does not exist: $project_path"
    exit 1
  }
  ok "Project root: ${project_path}"
  echo ""

  # ── Step 2: Conversational questions ──
  local has_db="no" db_type="" has_api="no" api_type=""
  local has_workers="no" has_proxy="no" container_type="none"

  local choice

  menu_select choice "Do you manage a database here?" "Yes" "No"
  if [[ "$choice" == "Yes" ]]; then
    has_db="yes"
    menu_select db_type "What kind of database?" "PostgreSQL" "MySQL" "Redis" "MongoDB" "SQLite" "Other"
  fi

  menu_select choice "Do you have a web server or API?" "Yes" "No"
  if [[ "$choice" == "Yes" ]]; then
    has_api="yes"
    menu_select api_type "What runs it?" "Docker" "Node.js" "Go" "Python" "Rust" "Other"
  fi

  menu_select choice "Any background workers or jobs?" "Yes" "No"
  [[ "$choice" == "Yes" ]] && has_workers="yes"

  menu_select choice "Any reverse proxy (nginx, caddy, etc)?" "Yes" "No"
  [[ "$choice" == "Yes" ]] && has_proxy="yes"

  menu_select container_type "Do you use containers?" "Docker Compose" "Kubernetes" "Docker (standalone)" "None"

  # ── Step 3: Scan project directory ──
  echo ""
  start_spinner "Scanning project..."
  sleep 1

  local -a detected_files=()
  local -a detected_labels=()

  [[ -f "${project_path}/Dockerfile" ]] && detected_files+=("Dockerfile") && detected_labels+=("Dockerfile found")
  [[ -f "${project_path}/docker-compose.yml" || -f "${project_path}/docker-compose.yaml" || -f "${project_path}/compose.yml" ]] && detected_files+=("docker-compose") && detected_labels+=("Docker Compose config")
  [[ -f "${project_path}/package.json" ]] && detected_files+=("package.json") && detected_labels+=("Node.js project")
  [[ -f "${project_path}/go.mod" ]] && detected_files+=("go.mod") && detected_labels+=("Go module")
  [[ -f "${project_path}/Cargo.toml" ]] && detected_files+=("Cargo.toml") && detected_labels+=("Rust project")
  [[ -f "${project_path}/requirements.txt" || -f "${project_path}/pyproject.toml" ]] && detected_files+=("python") && detected_labels+=("Python project")
  [[ -d "${project_path}/k8s" || -d "${project_path}/kubernetes" ]] && detected_files+=("k8s") && detected_labels+=("Kubernetes manifests")
  [[ -f "${project_path}/nginx.conf" ]] && detected_files+=("nginx") && detected_labels+=("Nginx config")
  [[ -f "${project_path}/redis.conf" ]] && detected_files+=("redis") && detected_labels+=("Redis config")

  stop_spinner

  if [[ ${#detected_files[@]} -gt 0 ]]; then
    info "Found in ${project_path}:"
    for label in "${detected_labels[@]}"; do
      echo -e "    ${GREEN}*${RESET} ${label}"
    done
    echo ""
  else
    info "No known project files detected. That's fine — we'll configure manually."
    echo ""
  fi

  # ── Step 4: Build service list ──
  local -a service_list=()

  [[ "$has_api" == "yes" ]] && service_list+=("API Server (${api_type})")
  [[ "$has_db" == "yes" ]] && service_list+=("${db_type}")
  [[ "$has_workers" == "yes" ]] && service_list+=("Background Worker")
  [[ "$has_proxy" == "yes" ]] && service_list+=("Reverse Proxy")

  if [[ ${#service_list[@]} -eq 0 ]]; then
    warn "No services defined. Add at least one service."
    exit 1
  fi

  local -a selected_services
  checklist_select selected_services "Select services to manage" "${service_list[@]}"
  echo ""

  # ── Step 5: Per-service config ──
  local services_json="{"
  local deploy_order_json="["
  local first=true

  for svc in "${selected_services[@]}"; do
    # Generate a key from the service name
    local key
    key=$(echo "$svc" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')

    local w2=$(( TERM_COLS - 4 ))
    (( w2 > 60 )) && w2=60
    local line
    line=$(printf '─%.0s' $(seq 1 "$w2"))
    echo -e "  ${GRAY}${line}${RESET}"
    echo -e "  ${BOLD}Configure: ${svc}${RESET}\n"

    local health_choice port_num
    menu_select health_choice "Health check type for ${svc}?" "HTTP" "TCP" "Command" "None"

    local health_json="{}"
    case "$health_choice" in
      HTTP)
        printf "  ${CYAN}>${RESET} Health endpoint: "
        read -r endpoint
        printf "  ${CYAN}>${RESET} Port: "
        read -r port_num
        health_json="{\"type\":\"http\",\"endpoint\":\"${endpoint:-/health}\",\"port\":${port_num:-8080},\"timeout\":10}"
        ;;
      TCP)
        printf "  ${CYAN}>${RESET} Port: "
        read -r port_num
        health_json="{\"type\":\"tcp\",\"port\":${port_num:-0},\"timeout\":5}"
        ;;
      Command)
        printf "  ${CYAN}>${RESET} Health command: "
        read -r health_cmd
        health_json="{\"type\":\"command\",\"command\":\"${health_cmd}\",\"timeout\":10}"
        ;;
      None)
        health_json="null"
        ;;
    esac

    # Credentials
    local cred_choice
    echo ""
    echo -e "  ${YELLOW}! HIGH RISK${RESET}: Store superuser credentials for ${svc}?"
    echo -e "  ${DIM}Credentials stored in system keychain or encrypted vault.${RESET}"
    echo -e "  ${DIM}NEVER in deploy.json or committed to git.${RESET}"
    menu_select cred_choice "Store credentials?" "No, prompt each time (recommended)" "Yes, store securely"

    local cred_json='{"enabled":false}'
    if [[ "$cred_choice" == "Yes, store securely" ]]; then
      cred_json='{"enabled":true,"risk_level":"high"}'
    fi

    # Build service JSON
    [[ "$first" == "true" ]] && first=false || services_json+=","
    services_json+="\"${key}\":{\"name\":\"${svc}\",\"health\":${health_json},\"credentials\":${cred_json}}"
    deploy_order_json+="\"${key}\","
    echo ""
  done

  services_json+="}"
  deploy_order_json="${deploy_order_json%,}]"

  # ── Step 6: Ask about project name ──
  local project_name
  project_name=$(basename "$project_path")
  printf "  ${CYAN}>${RESET} Project name [${project_name}]: "
  read -r custom_name
  project_name="${custom_name:-$project_name}"

  # ── Step 7: Write config ──
  echo ""
  start_spinner "Writing configuration..."

  local config_path="${project_path}/deploy.json"
  local muster_dir="${project_path}/.muster"

  mkdir -p "${muster_dir}/hooks"
  mkdir -p "${muster_dir}/logs"

  # Create hook directories and scaffold scripts
  for svc in "${selected_services[@]}"; do
    local key
    key=$(echo "$svc" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
    local hook_dir="${muster_dir}/hooks/${key}"
    mkdir -p "$hook_dir"

    # Scaffold deploy hook
    cat > "${hook_dir}/deploy.sh" << 'HOOK'
#!/usr/bin/env bash
# Deploy hook — add your deploy commands here
echo "TODO: Add deploy commands"
exit 0
HOOK
    chmod +x "${hook_dir}/deploy.sh"

    # Scaffold health hook
    cat > "${hook_dir}/health.sh" << 'HOOK'
#!/usr/bin/env bash
# Health check hook — exit 0 if healthy, exit 1 if not
echo "TODO: Add health check"
exit 0
HOOK
    chmod +x "${hook_dir}/health.sh"
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

  # Add .muster/logs to .gitignore
  local gitignore="${project_path}/.gitignore"
  if [[ -f "$gitignore" ]]; then
    grep -q '.muster/logs' "$gitignore" || echo '.muster/logs/' >> "$gitignore"
  else
    echo '.muster/logs/' > "$gitignore"
  fi

  stop_spinner

  echo ""
  ok "Created deploy.json"
  ok "Created .muster/hooks/ with scaffold scripts"
  ok "Added .muster/logs to .gitignore"
  echo ""
  info "Edit the hook scripts in .muster/hooks/ to add your deploy logic."
  info "Run ${BOLD}muster${RESET} to open the dashboard."
  echo ""
}
