#!/usr/bin/env bash
# muster/lib/commands/fleet_setup.sh — Fleet setup wizard
# Creates fleet directory structure at ~/.muster/fleets/<name>/

# ── Visual helpers ──

_FLEET_SETUP_STEP=1
_FLEET_SETUP_TOTAL=5

_fleet_setup_bar() {
  local left="$1" right="${2:-}"
  local bar_w=$(( TERM_COLS - 2 ))
  (( bar_w < 20 )) && bar_w=20
  local text="  ${left}"
  local text_len=${#text}
  local right_len=${#right}
  local pad_len=$(( bar_w - text_len - right_len ))
  (( pad_len < 1 )) && pad_len=1
  local pad
  printf -v pad '%*s' "$pad_len" ""
  printf ' \033[48;5;178m\033[38;5;0m\033[1m%s%s%s\033[0m\n' "$text" "$pad" "$right"
}

_fleet_setup_screen() {
  local step="$1" label="$2"
  _FLEET_SETUP_STEP="$step"
  clear
  echo ""
  _fleet_setup_bar "muster  fleet setup" "step ${step}/${_FLEET_SETUP_TOTAL}  "

  local bar_w=$(( TERM_COLS - 6 ))
  (( bar_w < 10 )) && bar_w=10
  (( bar_w > 50 )) && bar_w=50
  local filled=$(( step * bar_w / _FLEET_SETUP_TOTAL ))
  local empty=$(( bar_w - filled ))
  local bar_filled="" bar_empty=""
  local _bi=0
  while (( _bi < filled )); do bar_filled="${bar_filled}#"; _bi=$((_bi + 1)); done
  _bi=0
  while (( _bi < empty )); do bar_empty="${bar_empty}-"; _bi=$((_bi + 1)); done
  printf '  \033[38;5;178m%s\033[2m%s\033[0m\n' "$bar_filled" "$bar_empty"

  echo ""
  printf '%b\n' "  ${BOLD}${label}${RESET}"
  echo ""
}

# Draw a boxed info line
_fleet_setup_info() {
  printf '%b\n' "  ${DIM}$1${RESET}"
}

# Draw a success bullet
_fleet_setup_ok() {
  printf '%b\n' "  ${GREEN}*${RESET} $1"
}

# Draw a fail bullet
_fleet_setup_fail() {
  printf '%b\n' "  ${RED}x${RESET} $1"
}

# Pretty machine summary line
_fleet_setup_machine_line() {
  local name="$1" user="$2" host="$3" key="$4" hook_mode="$5"
  local _hm_label=""
  case "$hook_mode" in
    sync)   _hm_label="${ACCENT}sync${RESET}" ;;
    manual) _hm_label="${DIM}manual${RESET}" ;;
    *)      _hm_label="${DIM}${hook_mode}${RESET}" ;;
  esac

  printf '  %b  %b%-16s%b %s@%s  %b[%b]%b\n' \
    "${GREEN}*${RESET}" "${BOLD}" "$name" "${RESET}" "$user" "$host" "${DIM}" "" "${RESET}"
}

# ── Main entry ──

cmd_fleet_setup() {
  if [[ ! -t 0 ]]; then
    err "Fleet setup requires a terminal (TTY)."
    echo "  Use 'muster fleet add' for non-interactive machine setup."
    return 1
  fi

  source "$MUSTER_ROOT/lib/core/fleet_config.sh"
  fleets_ensure_dir

  local _fleet_name=""
  local _machines=()
  local _machine_hosts=()
  local _machine_users=()
  local _machine_keys=()
  local _machine_hook_modes=()
  local _strategy="sequential"

  # ── Step 1: Fleet Name ──
  _FLEET_SETUP_TOTAL=5
  _fleet_setup_screen 1 "Name your fleet"

  _fleet_setup_info "A fleet deploys your project across multiple machines."
  _fleet_setup_info "Name it after your environment — production, staging, dev."
  echo ""
  printf '  %b>%b Fleet name %b(production)%b: ' "${ACCENT}" "${RESET}" "${DIM}" "${RESET}"
  IFS= read -r _fleet_name
  [[ -z "$_fleet_name" ]] && _fleet_name="production"

  # Sanitize
  _fleet_name=$(printf '%s' "$_fleet_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

  # Create fleet + default group
  if [[ -f "$(fleet_dir "$_fleet_name")/fleet.json" ]]; then
    echo ""
    _fleet_setup_info "Fleet '${_fleet_name}' already exists — adding to it."
  else
    fleet_cfg_create "$_fleet_name" "$_fleet_name" "sequential"
    fleet_cfg_group_create "$_fleet_name" "default" "default"
  fi

  # ── Step 2: Add Machines ──
  while true; do
    local _machine_count=$(( ${#_machines[@]} + 1 ))
    _fleet_setup_screen 2 "Add machines"

    # Show machines added so far
    if (( ${#_machines[@]} > 0 )); then
      local _mi=0
      while (( _mi < ${#_machines[@]} )); do
        printf '%b\n' "    ${GREEN}*${RESET} ${_machines[$_mi]}  ${DIM}${_machine_users[$_mi]}@${_machine_hosts[$_mi]}${RESET}"
        _mi=$((_mi + 1))
      done
      echo ""
    fi

    printf '%b\n' "  ${DIM}Machine ${_machine_count}:${RESET}"
    echo ""

    # Name
    printf '  %b>%b Name: ' "${ACCENT}" "${RESET}"
    local _m_name=""
    IFS= read -r _m_name
    if [[ -z "$_m_name" ]]; then
      if (( ${#_machines[@]} == 0 )); then
        warn "At least one machine is required."
        sleep 1
        continue
      fi
      break
    fi

    # Host
    printf '  %b>%b Host %b(user@ip)%b: ' "${ACCENT}" "${RESET}" "${DIM}" "${RESET}"
    local _m_host=""
    IFS= read -r _m_host

    if [[ -z "$_m_host" || "$_m_host" != *"@"* ]]; then
      warn "Expected user@hostname format"
      sleep 1
      continue
    fi

    local _m_user="${_m_host%%@*}"
    local _m_hostname="${_m_host#*@}"

    # SSH key — auto-detect, pick best
    local _ssh_keys=()
    local _kf
    for _kf in "$HOME"/.ssh/id_ed25519 "$HOME"/.ssh/id_rsa "$HOME"/.ssh/deploy-key "$HOME"/.ssh/deploy; do
      [[ -f "$_kf" ]] && _ssh_keys[${#_ssh_keys[@]}]="$_kf"
    done

    local _m_key=""
    if (( ${#_ssh_keys[@]} > 0 )); then
      echo ""
      local _key_opts=()
      local _ki=0
      while (( _ki < ${#_ssh_keys[@]} )); do
        local _kname
        _kname=$(basename "${_ssh_keys[$_ki]}")
        _key_opts[${#_key_opts[@]}]="${_ssh_keys[$_ki]}"
        _ki=$((_ki + 1))
      done
      _key_opts[${#_key_opts[@]}]="Other"
      _key_opts[${#_key_opts[@]}]="None (SSH agent)"

      menu_select "SSH key" "${_key_opts[@]}"
      case "$MENU_RESULT" in
        "None (SSH agent)") _m_key="" ;;
        "Other")
          printf '  %b>%b Key path: ' "${ACCENT}" "${RESET}"
          IFS= read -r _m_key
          ;;
        *) _m_key="$MENU_RESULT" ;;
      esac
    fi

    # Test SSH connectivity immediately
    echo ""
    start_spinner "Connecting to ${_m_host}..."
    local _ssh_ok=false
    local _ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
    [[ -n "$_m_key" ]] && _ssh_opts="${_ssh_opts} -i ${_m_key}"
    # shellcheck disable=SC2086
    if ssh $_ssh_opts "${_m_host}" "echo ok" &>/dev/null; then
      _ssh_ok=true
    fi
    stop_spinner

    if [[ "$_ssh_ok" == "true" ]]; then
      _fleet_setup_ok "Connected to ${_m_host}"
    else
      _fleet_setup_fail "Cannot reach ${_m_host}"
      _fleet_setup_info "Machine will be added anyway — fix connectivity later."
    fi

    # Create project.json
    local _proj_json
    _proj_json=$(jq -n \
      --arg n "$_m_name" \
      --arg host "$_m_hostname" \
      --arg user "$_m_user" \
      --arg key "$_m_key" \
      '{name: $n, machine: ({host: $host, user: $user, port: 22, transport: "ssh"} +
        (if $key != "" then {identity_file: $key} else {} end)),
        hook_mode: "manual"}')

    fleet_cfg_project_create "$_fleet_name" "default" "$_m_name" "$_proj_json" 2>/dev/null || true

    _machines[${#_machines[@]}]="$_m_name"
    _machine_hosts[${#_machine_hosts[@]}]="$_m_hostname"
    _machine_users[${#_machine_users[@]}]="$_m_user"
    _machine_keys[${#_machine_keys[@]}]="$_m_key"
    _machine_hook_modes[${#_machine_hook_modes[@]}]="manual"

    echo ""
    if (( ${#_machines[@]} >= 1 )); then
      menu_select "Add another?" "Add another machine" "Continue"
      [[ "$MENU_RESULT" == "Continue" || "$MENU_RESULT" == "__back__" ]] && break
    fi
  done

  if (( ${#_machines[@]} == 0 )); then
    warn "No machines added."
    return 1
  fi

  # ── Step 3: Hook Mode (per machine) ──
  local _mi=0
  while (( _mi < ${#_machines[@]} )); do
    local _mname="${_machines[$_mi]}"
    _fleet_setup_screen 3 "Configure ${_mname}"

    _fleet_setup_info "How should deploys work on ${BOLD}${_mname}${RESET}${DIM}?${RESET}"
    echo ""

    menu_select_desc "Hook management" \
      "Sync (recommended)" \
      "Create deploy scripts here. Muster pushes them to the remote before each deploy. Edit hooks locally, muster syncs automatically." \
      "Manual" \
      "The remote already has muster set up with its own hooks. Deploys trigger 'muster deploy' on the remote."

    case "$MENU_RESULT" in
      *"Sync"*)
        _machine_hook_modes[$_mi]="sync"

        echo ""
        _fleet_setup_info "What services does ${_mname} run?"
        echo ""
        checklist_select --none "Services" \
          "Web app / API" \
          "Background workers" \
          "Database" \
          "Cache (Redis)" \
          "Reverse proxy"

        local _remote_components=()
        while IFS= read -r _rc; do
          [[ -n "$_rc" ]] && _remote_components[${#_remote_components[@]}]="$_rc"
        done <<< "$CHECKLIST_RESULT"

        echo ""
        menu_select "Stack?" "Docker Compose" "Docker" "Kubernetes" "Bare metal"
        local _remote_stack="compose"
        case "$MENU_RESULT" in
          "Docker Compose") _remote_stack="compose" ;;
          "Docker")         _remote_stack="docker" ;;
          "Kubernetes")     _remote_stack="k8s" ;;
          "Bare metal")     _remote_stack="bare" ;;
        esac

        # Generate hooks
        local _hooks_base
        _hooks_base="$(fleet_cfg_project_hooks_dir "$_fleet_name" "default" "$_mname")"
        mkdir -p "$_hooks_base"

        local _svc_names=()
        local _ci=0
        while (( _ci < ${#_remote_components[@]} )); do
          local _comp="${_remote_components[$_ci]}"
          local _svc_name=""
          case "$_comp" in
            *"Web app"*|*"API"*)      _svc_name="api" ;;
            *"workers"*)              _svc_name="worker" ;;
            *"Database"*)             _svc_name="database" ;;
            *"Cache"*|*"Redis"*)      _svc_name="redis" ;;
            *"Reverse proxy"*)        _svc_name="proxy" ;;
          esac
          if [[ -n "$_svc_name" ]]; then
            local _svc_hook_dir="${_hooks_base}/${_svc_name}"
            mkdir -p "$_svc_hook_dir"
            _setup_copy_hooks "$_remote_stack" "$_svc_name" "$_svc_name" "$_svc_hook_dir" \
              "docker-compose.yml" "Dockerfile" "k8s/${_svc_name}/" "default" "8080" "$_svc_name" ""
            _svc_names[${#_svc_names[@]}]="$_svc_name"
          fi
          _ci=$((_ci + 1))
        done

        echo ""
        if (( ${#_svc_names[@]} > 0 )); then
          _fleet_setup_ok "Generated hooks:"
          local _gi=0
          while (( _gi < ${#_svc_names[@]} )); do
            printf '%b\n' "    ${DIM}${_svc_names[$_gi]}/${RESET}"
            _gi=$((_gi + 1))
          done
          echo ""
          _fleet_setup_info "Edit these anytime at:"
          _fleet_setup_info "~/.muster/fleets/${_fleet_name}/default/${_mname}/hooks/"
        fi

        # Update project.json
        fleet_cfg_project_update "$_fleet_name" "default" "$_mname" \
          '.hook_mode = "sync" | .stack = "'"$_remote_stack"'"' 2>/dev/null || true

        if (( ${#_svc_names[@]} > 0 )); then
          local _svcs_json="[]"
          local _si=0
          while (( _si < ${#_svc_names[@]} )); do
            _svcs_json=$(printf '%s' "$_svcs_json" | jq --arg s "${_svc_names[$_si]}" '. + [$s]')
            _si=$((_si + 1))
          done
          fleet_cfg_project_update "$_fleet_name" "default" "$_mname" \
            ".services = ${_svcs_json} | .deploy_order = ${_svcs_json}" 2>/dev/null || true
        fi

        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
        ;;
      *)
        # Manual mode
        _machine_hook_modes[$_mi]="manual"
        echo ""
        printf '  %b>%b Remote project path %b(~/myapp)%b: ' "${ACCENT}" "${RESET}" "${DIM}" "${RESET}"
        local _remote_path=""
        IFS= read -r _remote_path
        [[ -z "$_remote_path" ]] && _remote_path="~/myapp"

        fleet_cfg_project_update "$_fleet_name" "default" "$_mname" \
          ".hook_mode = \"manual\" | .remote_path = \"${_remote_path}\"" 2>/dev/null || true
        ;;
    esac

    _mi=$((_mi + 1))
  done

  # ── Step 4: Deploy Strategy ──
  _fleet_setup_screen 4 "Deploy strategy"

  if (( ${#_machines[@]} == 1 )); then
    _fleet_setup_info "Single machine — sequential deploy."
    _strategy="sequential"
    fleet_cfg_update "$_fleet_name" ".deploy_strategy = \"sequential\"" 2>/dev/null || true
    sleep 1
  else
    _fleet_setup_info "How should deploys run across ${#_machines[@]} machines?"
    echo ""

    menu_select_desc "Strategy" \
      "Sequential (recommended)" \
      "Deploy one machine at a time. If something fails, you can fix it before it reaches the next machine. Best for production." \
      "Parallel" \
      "Deploy all machines at once. Fastest, but failures affect everything simultaneously. Good for staging." \
      "Rolling" \
      "Deploy one, verify it's healthy, then continue. Catches bad deploys before they spread."

    case "$MENU_RESULT" in
      *"Parallel"*) _strategy="parallel" ;;
      *"Rolling"*)  _strategy="rolling" ;;
      *)            _strategy="sequential" ;;
    esac

    fleet_cfg_update "$_fleet_name" ".deploy_strategy = \"${_strategy}\"" 2>/dev/null || true
  fi

  # ── Step 5: Summary ──
  _fleet_setup_screen 5 "Fleet ready"

  # Fleet name
  local w=$(( TERM_COLS - 4 ))
  (( w > 50 )) && w=50
  (( w < 10 )) && w=10
  local inner=$(( w - 2 ))

  local label="${_fleet_name}"
  local label_pad_len=$(( w - ${#label} - 3 ))
  (( label_pad_len < 1 )) && label_pad_len=1
  local label_pad
  printf -v label_pad '%*s' "$label_pad_len" ""
  label_pad="${label_pad// /─}"
  printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$label" "${RESET}${ACCENT}" "$label_pad" "${RESET}"

  _mi=0
  while (( _mi < ${#_machines[@]} )); do
    local _mname="${_machines[$_mi]}"
    local _muser="${_machine_users[$_mi]}"
    local _mhost="${_machine_hosts[$_mi]}"
    local _mhm="${_machine_hook_modes[$_mi]}"

    local _hm_tag=""
    case "$_mhm" in
      sync)   _hm_tag=" sync" ;;
      manual) _hm_tag=" manual" ;;
    esac

    local display="${_mname}: ${_muser}@${_mhost}"
    local tag_len=${#_hm_tag}
    local max_display=$(( inner - 4 - tag_len ))
    (( max_display < 5 )) && max_display=5
    if (( ${#display} > max_display )); then
      display="${display:0:$((max_display - 3))}..."
    fi

    local content_len=$(( 4 + ${#display} + tag_len ))
    local pad_len=$(( inner - content_len ))
    (( pad_len < 0 )) && pad_len=0
    local pad
    printf -v pad '%*s' "$pad_len" ""

    printf '  %b│%b  %b*%b %s%s%b%s%b%b│%b\n' \
      "${ACCENT}" "${RESET}" "${GREEN}" "${RESET}" \
      "$display" "$pad" "${DIM}" "$_hm_tag" "${RESET}" "${ACCENT}" "${RESET}"

    _mi=$((_mi + 1))
  done

  local bottom
  printf -v bottom '%*s' "$w" ""
  bottom="${bottom// /─}"
  printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"

  echo ""
  printf '%b\n' "  ${DIM}Strategy:${RESET} ${_strategy}"
  printf '%b\n' "  ${DIM}Config:${RESET}   ~/.muster/fleets/${_fleet_name}/"
  echo ""

  # Quick commands reference
  printf '%b\n' "  ${ACCENT}Next steps:${RESET}"
  printf '%b\n' "    ${BOLD}muster fleet deploy${RESET}    Deploy to all machines"
  printf '%b\n' "    ${BOLD}muster fleet status${RESET}    Check health across fleet"
  printf '%b\n' "    ${BOLD}muster fleet sync${RESET}      Push hooks to remotes"
  printf '%b\n' "    ${BOLD}muster fleet${RESET}           Interactive fleet manager"
  echo ""

  menu_select "Run a test deploy?" "Dry run" "Done"

  if [[ "$MENU_RESULT" == "Dry run" ]]; then
    echo ""
    source "$MUSTER_ROOT/lib/commands/fleet_deploy.sh"
    FLEET_CONFIG_FILE="__fleet_dirs__"
    _fleet_cmd_deploy --dry-run
  fi

  return 0
}
