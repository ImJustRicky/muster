#!/usr/bin/env bash
# muster/lib/commands/fleet.sh — Fleet command handler

source "$MUSTER_ROOT/lib/core/fleet.sh"
source "$MUSTER_ROOT/lib/tui/menu.sh"
source "$MUSTER_ROOT/lib/tui/spinner.sh"
source "$MUSTER_ROOT/lib/tui/progress.sh"
source "$MUSTER_ROOT/lib/tui/streambox.sh"
source "$MUSTER_ROOT/lib/core/credentials.sh"
source "$MUSTER_ROOT/lib/commands/history.sh"
source "$MUSTER_ROOT/lib/commands/fleet_deploy.sh"

cmd_fleet() {
  case "${1:-}" in
    init)
      _fleet_cmd_init
      ;;
    add)
      shift
      _fleet_cmd_add "$@"
      ;;
    remove|rm)
      shift
      _fleet_cmd_remove "$@"
      ;;
    pair)
      shift
      _fleet_cmd_pair "$@"
      ;;
    list|ls)
      shift
      _fleet_cmd_list "$@"
      ;;
    test)
      shift
      _fleet_cmd_test "$@"
      ;;
    group)
      shift
      _fleet_cmd_group "$@"
      ;;
    ungroup)
      shift
      _fleet_cmd_ungroup "$@"
      ;;
    deploy)
      shift
      _fleet_cmd_deploy "$@"
      ;;
    status)
      shift
      _fleet_cmd_status "$@"
      ;;
    rollback)
      shift
      _fleet_cmd_rollback "$@"
      ;;
    sync)
      shift
      source "$MUSTER_ROOT/lib/commands/fleet_sync.sh"
      _fleet_cmd_sync "$@"
      ;;
    keygen)
      shift
      _fleet_cmd_keygen "$@"
      ;;
    trust-key)
      shift
      _fleet_cmd_trust_key "$@"
      ;;
    list-keys)
      shift
      _fleet_cmd_list_keys "$@"
      ;;
    revoke-key)
      shift
      _fleet_cmd_revoke_key "$@"
      ;;
    setup-user)
      shift
      source "$MUSTER_ROOT/lib/commands/fleet_sync.sh"
      _fleet_cmd_setup_user "$@"
      ;;
    edit)
      shift
      _fleet_cmd_edit "$@"
      ;;
    --help|-h)
      _fleet_cmd_help
      ;;
    "")
      if [[ -t 0 ]]; then
        _fleet_cmd_manager
      else
        _fleet_cmd_help
      fi
      ;;
    *)
      err "Unknown fleet command: $1"
      echo "Run 'muster fleet --help' for usage."
      return 1
      ;;
  esac
}

_fleet_cmd_help() {
  echo "Usage: muster fleet <command>"
  echo ""
  echo "Deploy one project to multiple machines via SSH or cloud tunnel."
  echo ""
  echo "Setup:"
  echo "  init                          Create empty remotes.json"
  echo "  add <name> user@host [opts]   Add a machine to the fleet"
  echo "  remove <name>                 Remove a machine (+ stored token)"
  echo "  pair <name> --token <token>   Manually pair a muster-mode machine"
  echo "  group <name> <m1> [m2...]     Create or update a machine group"
  echo "  ungroup <name>                Remove a group"
  echo ""
  echo "Info:"
  echo "  list [--json]                 Show machines, groups, status"
  echo "  test [name|group]             Test connectivity (SSH or cloud)"
  echo ""
  echo "Operations:"
  echo "  deploy [target] [--parallel]  Deploy to fleet machines"
  echo "  deploy [target] --sync        Sync hooks before deploying"
  echo "  status [target] [--json]      Check health across fleet"
  echo "  rollback [target]             Rollback fleet machines"
  echo ""
  echo "Hook Management:"
  echo "  sync [target] [--dry-run]     Push local hooks to remote machines"
  echo "  edit <name> [--sync|--manual] Change machine settings"
  echo "  setup-user <name> [--user X]  Create dedicated deploy user on target"
  echo ""
  echo "Signing:"
  echo "  keygen                        Generate signing keypair"
  echo "  trust-key <name>              Distribute public key to target"
  echo "  list-keys [name]              Show trusted signing keys on target"
  echo "  revoke-key <name> --label X   Remove a signing key from target"
  echo ""
  echo "Transport:"
  echo "  SSH (default)     Direct SSH connection to each machine"
  echo "  Cloud             Route through cloud relay (--transport cloud)"
  echo "                    Requires muster-tunnel + muster-agent on remote"
  echo ""
  echo "Examples:"
  echo "  muster fleet init"
  echo "  muster fleet add prod-1 deploy@10.0.1.10 --mode muster --path /opt/app"
  echo "  muster fleet add prod-2 deploy@10.0.1.11 --mode push"
  echo "  muster fleet add cloud-1 deploy@agent-east --transport cloud --path /opt/app"
  echo "  muster fleet group web prod-1 prod-2"
  echo "  muster fleet deploy web"
  echo "  muster fleet deploy --parallel"
  echo ""
  echo "See also: muster group --help   (orchestrate multiple projects together)"
}

# ── Interactive fleet manager (from dashboard or bare `muster fleet`) ──

_fleet_cmd_manager() {
  if ! fleet_load_config; then
    info "No remotes.json found. Set up fleet via CLI:"
    echo ""
    printf '%b\n' "  ${DIM}muster fleet init${RESET}"
    printf '%b\n' "  ${DIM}muster fleet add <name> user@host [--mode muster|push]${RESET}"
    printf '%b\n' "  ${DIM}muster fleet --help${RESET}"
    echo ""
    return 0
  fi

  while true; do
    # Show fleet overview using list TUI
    _fleet_cmd_list

    local machines
    machines=$(fleet_machines)

    if [[ -z "$machines" ]]; then
      printf '%b\n' "  ${DIM}Add machines via CLI: muster fleet add <name> user@host${RESET}"
      echo ""
      return 0
    fi

    # Operations menu (no CRUD — that's CLI only)
    local actions=()
    actions[${#actions[@]}]="Deploy"
    actions[${#actions[@]}]="Status"
    actions[${#actions[@]}]="Test connections"
    actions[${#actions[@]}]="Rollback"
    actions[${#actions[@]}]="Back"

    menu_select "Fleet" "${actions[@]}"

    case "$MENU_RESULT" in
      "Deploy")
        _fleet_cmd_deploy
        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
        ;;
      "Status")
        _fleet_cmd_status
        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
        ;;
      "Test connections")
        _fleet_cmd_test
        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
        ;;
      "Rollback")
        _fleet_cmd_rollback
        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
        ;;
      "Back"|__back__)
        return 0
        ;;
    esac
  done
}

# ── init ──

_fleet_cmd_init() {
  fleet_init
}

# ── add ──

_fleet_cmd_add() {
  local name="" userhost="" mode="push" port="22" path="" key="" transport="ssh" hook_mode="manual"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode|-m) mode="$2"; shift 2 ;;
      --port|-p) port="$2"; shift 2 ;;
      --path) path="$2"; shift 2 ;;
      --key|-k) key="$2"; shift 2 ;;
      --transport|-t) transport="$2"; shift 2 ;;
      --sync) hook_mode="sync"; shift ;;
      --manual) hook_mode="manual"; shift ;;
      --help|-h)
        echo "Usage: muster fleet add <name> user@host [options]"
        echo ""
        echo "Options:"
        echo "  --mode, -m <muster|push>    Deploy mode (default: push)"
        echo "  --transport, -t <ssh|cloud>  Transport layer (default: ssh)"
        echo "  --port, -p <N>              SSH port (default: 22)"
        echo "  --path <dir>                Project directory on remote"
        echo "  --key, -k <file>            SSH identity file"
        echo "  --sync                      Sync hooks from dev machine before deploy"
        echo "  --manual                    Hooks already on remote (default)"
        echo ""
        echo "Modes:"
        echo "  muster   Remote has muster installed (SSH + muster deploy)"
        echo "  push     Pipe hook scripts over SSH (no muster needed)"
        echo ""
        echo "Hook Modes:"
        echo "  --sync     Dev machine pushes hooks before deploy (target needs nothing)"
        echo "  --manual   Hooks already exist on target (default)"
        echo ""
        echo "Transports:"
        echo "  ssh      Direct SSH connection (default)"
        echo "  cloud    Connect via muster-tunnel relay"
        return 0
        ;;
      --*)
        err "Unknown flag: $1"
        return 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        elif [[ -z "$userhost" ]]; then
          userhost="$1"
        else
          err "Unexpected argument: $1"
          return 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$name" || -z "$userhost" ]]; then
    err "Usage: muster fleet add <name> user@host [--mode muster|push] [--transport ssh|cloud]"
    return 1
  fi

  # Parse user@host
  local user host
  if [[ "$userhost" == *"@"* ]]; then
    user="${userhost%%@*}"
    host="${userhost#*@}"
  else
    err "Expected user@host format, got: ${userhost}"
    return 1
  fi

  # Ensure fleet config exists
  if ! fleet_load_config; then
    err "No remotes.json found. Run 'muster fleet init' first."
    return 1
  fi

  fleet_add_machine "$name" "$host" "$user" "$port" "$key" "$path" "$mode" "$transport" "$hook_mode" || return 1

  if [[ "$transport" == "cloud" ]]; then
    # Cloud transport: check for muster-tunnel, validate cloud config
    source "$MUSTER_ROOT/lib/core/cloud.sh"

    if ! _fleet_cloud_available; then
      echo ""
      warn "muster-tunnel not installed"
      printf '%b\n' "  ${DIM}Install: curl -sSL https://getmuster.dev/cloud | bash${RESET}"
    fi

    # Check if remotes.json has a cloud section
    local _relay
    _relay=$(fleet_get '.cloud.relay // ""')
    if [[ -z "$_relay" || "$_relay" == "null" ]]; then
      echo ""
      warn "No cloud config in remotes.json"
      printf '%b\n' "  ${DIM}Add a \"cloud\" section with relay URL and org_id to remotes.json${RESET}"
    fi

    echo ""
    info "Cloud machine added. Deploy via: muster fleet deploy ${name}"
    printf '%b\n' "  ${DIM}Ensure muster-agent is running on the remote and connected to the relay.${RESET}"
  else
    # SSH transport: test connectivity
    echo ""
    start_spinner "Testing SSH connectivity..."
    if fleet_check "$name"; then
      stop_spinner
      ok "SSH connection to ${user}@${host}:${port} succeeded"
    else
      stop_spinner
      warn "SSH connection to ${user}@${host}:${port} failed"
      printf '%b\n' "  ${DIM}Machine added but not reachable. Check SSH config and try: muster fleet test ${name}${RESET}"
    fi

    # Non-root check
    _fleet_check_nonroot "$name"

    # Auto-pair for muster mode
    if [[ "$mode" == "muster" ]]; then
      echo ""
      fleet_auto_pair "$name"
    fi

    # Offer initial sync for sync-mode machines
    if [[ "$hook_mode" == "sync" ]]; then
      echo ""
      printf '%b\n' "  ${DIM}Hook mode: sync (dev machine pushes hooks)${RESET}"
      printf '  Run initial sync now? [y/N] '
      local _sync_reply
      read -r _sync_reply
      case "$_sync_reply" in
        y|Y)
          source "$MUSTER_ROOT/lib/commands/fleet_sync.sh"
          _fleet_sync_one "$name" "false" ""
          ;;
      esac
    fi
  fi
}

# ── remove ──

_fleet_cmd_remove() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    err "Usage: muster fleet remove <name>"
    return 1
  fi

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  fleet_remove_machine "$name"
}

# ── pair ──

_fleet_cmd_pair() {
  local name="" token=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token|-t) token="$2"; shift 2 ;;
      --help|-h)
        echo "Usage: muster fleet pair <name> --token <token>"
        echo ""
        echo "Manually store an auth token for a muster-mode machine."
        echo ""
        echo "To get a token, run on the remote:"
        echo "  muster auth create fleet-\$(hostname) --scope deploy"
        return 0
        ;;
      --*)
        err "Unknown flag: $1"
        return 1
        ;;
      *)
        name="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$name" || -z "$token" ]]; then
    err "Usage: muster fleet pair <name> --token <token>"
    return 1
  fi

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  # Verify machine exists
  local existing
  existing=$(fleet_get ".machines.\"${name}\" // empty")
  if [[ -z "$existing" ]]; then
    err "Machine '${name}' not found in remotes.json"
    return 1
  fi

  fleet_token_set "$name" "$token"
  ok "Token stored for '${name}'"

  # Verify if possible
  start_spinner "Verifying token..."
  if fleet_verify_pair "$name"; then
    stop_spinner
    ok "Token verified — $(fleet_desc "$name") is paired"
  else
    stop_spinner
    warn "Token stored but verification failed. Check that the remote is reachable and the token is valid."
  fi
}

# ── list ──

_fleet_cmd_list() {
  local json_mode=false
  [[ "${1:-}" == "--json" ]] && json_mode=true

  if ! fleet_load_config; then
    if [[ "$json_mode" == "true" ]]; then
      printf '{"machines":[],"groups":[]}\n'
    else
      info "No remotes.json found. Run 'muster fleet init' to get started."
    fi
    return 0
  fi

  if [[ "$json_mode" == "true" ]]; then
    jq '.' "$FLEET_CONFIG_FILE"
    return 0
  fi

  local w=$(( TERM_COLS - 4 ))
  (( w > 50 )) && w=50
  (( w < 10 )) && w=10
  local inner=$(( w - 2 ))

  echo ""

  local machines
  machines=$(fleet_machines)

  # ── Machines box ──
  local label="Machines"
  local label_pad_len=$(( w - ${#label} - 3 ))
  (( label_pad_len < 1 )) && label_pad_len=1
  local label_pad
  printf -v label_pad '%*s' "$label_pad_len" ""
  label_pad="${label_pad// /─}"
  printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$label" "${RESET}${ACCENT}" "$label_pad" "${RESET}"

  if [[ -z "$machines" ]]; then
    local _empty="No machines configured"
    local _epad_len=$(( inner - ${#_empty} - 2 ))
    (( _epad_len < 0 )) && _epad_len=0
    local _epad
    printf -v _epad '%*s' "$_epad_len" ""
    printf '  %b│%b  %b%s%b%s%b│%b\n' "${ACCENT}" "${RESET}" "${DIM}" "$_empty" "${RESET}" "$_epad" "${ACCENT}" "${RESET}"
  else
    while IFS= read -r machine; do
      [[ -z "$machine" ]] && continue
      _fleet_load_machine "$machine"

      local host_str="${_FM_USER}@${_FM_HOST}"
      [[ "$_FM_PORT" != "22" ]] && host_str="${host_str}:${_FM_PORT}"

      local status_icon status_color tag=""
      if [[ "$_FM_TRANSPORT" == "cloud" ]]; then
        status_icon="●"; status_color="$BLUE"
        tag=" cloud"
      elif [[ "$_FM_MODE" == "muster" ]]; then
        local token
        token=$(fleet_token_get "$machine")
        if [[ -n "$token" ]]; then
          status_icon="●"; status_color="$GREEN"
        else
          status_icon="●"; status_color="$YELLOW"
          tag=" unpaired"
        fi
      else
        status_icon="●"; status_color="$GREEN"
      fi

      local _transport_label=""
      [[ "$_FM_TRANSPORT" == "cloud" ]] && _transport_label=", cloud"
      local display="${machine}: ${host_str} (${_FM_MODE}${_transport_label})"
      local tag_len=${#tag}
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

      if [[ -n "$tag" ]]; then
        printf '  %b│%b  %b%s%b %s%s%b%s%b%b│%b\n' \
          "${ACCENT}" "${RESET}" "$status_color" "$status_icon" "${RESET}" \
          "$display" "$pad" "${YELLOW}" "$tag" "${RESET}" "${ACCENT}" "${RESET}"
      else
        printf '  %b│%b  %b%s%b %s%s%b│%b\n' \
          "${ACCENT}" "${RESET}" "$status_color" "$status_icon" "${RESET}" \
          "$display" "$pad" "${ACCENT}" "${RESET}"
      fi
    done <<< "$machines"
  fi

  local bottom
  printf -v bottom '%*s' "$w" ""
  bottom="${bottom// /─}"
  printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"

  # ── Groups box ──
  local groups
  groups=$(fleet_groups)

  if [[ -n "$groups" ]]; then
    echo ""
    local glabel="Groups"
    local glabel_pad_len=$(( w - ${#glabel} - 3 ))
    (( glabel_pad_len < 1 )) && glabel_pad_len=1
    local glabel_pad
    printf -v glabel_pad '%*s' "$glabel_pad_len" ""
    glabel_pad="${glabel_pad// /─}"
    printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$glabel" "${RESET}${ACCENT}" "$glabel_pad" "${RESET}"

    while IFS= read -r group; do
      [[ -z "$group" ]] && continue
      local members
      members=$(fleet_group_machines "$group" | tr '\n' ', ' | sed 's/,$//')
      local gdisplay="${group}: ${members}"
      local gmax=$(( inner - 4 ))
      if (( ${#gdisplay} > gmax )); then
        gdisplay="${gdisplay:0:$((gmax - 3))}..."
      fi
      local gcontent_len=$(( 4 + ${#gdisplay} ))
      local gpad_len=$(( inner - gcontent_len ))
      (( gpad_len < 0 )) && gpad_len=0
      local gpad
      printf -v gpad '%*s' "$gpad_len" ""
      printf '  %b│%b  %b○%b %b%s%b%s%b│%b\n' \
        "${ACCENT}" "${RESET}" "${DIM}" "${RESET}" \
        "${WHITE}" "$gdisplay" "${RESET}" "$gpad" "${ACCENT}" "${RESET}"
    done <<< "$groups"

    local gbottom
    printf -v gbottom '%*s' "$w" ""
    gbottom="${gbottom// /─}"
    printf '  %b└%s┘%b\n' "${ACCENT}" "$gbottom" "${RESET}"
  fi

  # Deploy order
  local deploy_order
  deploy_order=$(fleet_deploy_order)
  if [[ -n "$deploy_order" ]]; then
    echo ""
    local order_str=""
    while IFS= read -r _grp; do
      [[ -z "$_grp" ]] && continue
      if [[ -n "$order_str" ]]; then
        order_str="${order_str} -> ${_grp}"
      else
        order_str="$_grp"
      fi
    done <<< "$deploy_order"
    printf '%b\n' "  ${DIM}Deploy order:${RESET} ${order_str}"
  fi

  echo ""
}

# ── test ──

_fleet_cmd_test() {
  local target="${1:-}"

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  local machines_to_test=()

  if [[ -z "$target" ]]; then
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      machines_to_test[${#machines_to_test[@]}]="$m"
    done < <(fleet_machines)
  else
    local group_members
    group_members=$(fleet_group_machines "$target" 2>/dev/null)
    if [[ -n "$group_members" ]]; then
      while IFS= read -r m; do
        [[ -z "$m" ]] && continue
        machines_to_test[${#machines_to_test[@]}]="$m"
      done <<< "$group_members"
    else
      machines_to_test[0]="$target"
    fi
  fi

  local w=$(( TERM_COLS - 4 ))
  (( w > 50 )) && w=50
  (( w < 10 )) && w=10
  local inner=$(( w - 2 ))

  echo ""

  local label="Connectivity"
  local label_pad_len=$(( w - ${#label} - 3 ))
  (( label_pad_len < 1 )) && label_pad_len=1
  local label_pad
  printf -v label_pad '%*s' "$label_pad_len" ""
  label_pad="${label_pad// /─}"
  printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$label" "${RESET}${ACCENT}" "$label_pad" "${RESET}"

  local pass=0 fail=0
  local i=0
  while (( i < ${#machines_to_test[@]} )); do
    local machine="${machines_to_test[$i]}"
    _fleet_load_machine "$machine"

    local status_icon status_color tag=""

    if [[ "$_FM_TRANSPORT" == "cloud" ]]; then
      # Cloud transport test
      if fleet_check "$machine"; then
        status_icon="●"; status_color="$GREEN"
        tag=" cloud ok"
        pass=$(( pass + 1 ))
      else
        source "$MUSTER_ROOT/lib/core/cloud.sh"
        if ! _fleet_cloud_available; then
          status_icon="●"; status_color="$YELLOW"
          tag=" no tunnel"
        else
          status_icon="●"; status_color="$RED"
          tag=" cloud fail"
        fi
        fail=$(( fail + 1 ))
      fi
    elif fleet_check "$machine"; then
      # SSH test passed
      status_icon="●"; status_color="$GREEN"
      tag=" SSH ok"

      # Token test (muster mode only)
      if [[ "$_FM_MODE" == "muster" ]]; then
        local token
        token=$(fleet_token_get "$machine")
        if [[ -z "$token" ]]; then
          status_icon="●"; status_color="$YELLOW"
          tag=" unpaired"
        elif fleet_verify_pair "$machine"; then
          tag=" SSH ok, token ok"
        else
          status_icon="●"; status_color="$RED"
          tag=" SSH ok, token fail"
          fail=$(( fail + 1 ))
          i=$(( i + 1 ))

          # Render line before continue
          local _display="$machine"
          local _tag_len=${#tag}
          local _max=$(( inner - 4 - _tag_len ))
          (( _max < 5 )) && _max=5
          (( ${#_display} > _max )) && _display="${_display:0:$((_max - 3))}..."
          local _clen=$(( 4 + ${#_display} + _tag_len ))
          local _plen=$(( inner - _clen ))
          (( _plen < 0 )) && _plen=0
          local _pad
          printf -v _pad '%*s' "$_plen" ""
          printf '  %b│%b  %b%s%b %s%s%b%s%b%b│%b\n' \
            "${ACCENT}" "${RESET}" "$status_color" "$status_icon" "${RESET}" \
            "$_display" "$_pad" "$RED" "$tag" "${RESET}" "${ACCENT}" "${RESET}"
          continue
        fi
      fi

      pass=$(( pass + 1 ))
    else
      status_icon="●"; status_color="$RED"
      tag=" SSH fail"
      fail=$(( fail + 1 ))
    fi

    local display="$machine"
    local tag_len=${#tag}
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

    local tag_color="$GREEN"
    (( fail > 0 )) && [[ "$status_color" == "$RED" ]] && tag_color="$RED"
    [[ "$status_color" == "$YELLOW" ]] && tag_color="$YELLOW"

    printf '  %b│%b  %b%s%b %s%s%b%s%b%b│%b\n' \
      "${ACCENT}" "${RESET}" "$status_color" "$status_icon" "${RESET}" \
      "$display" "$pad" "$tag_color" "$tag" "${RESET}" "${ACCENT}" "${RESET}"

    i=$(( i + 1 ))
  done

  local bottom
  printf -v bottom '%*s' "$w" ""
  bottom="${bottom// /─}"
  printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"

  echo ""
  if (( fail == 0 )); then
    ok "All ${pass} machine(s) passed"
  else
    warn "${pass} passed, ${fail} failed"
  fi
  echo ""
}

# ── group ──

_fleet_cmd_group() {
  local group_name="${1:-}"
  shift 2>/dev/null || true

  if [[ -z "$group_name" ]]; then
    err "Usage: muster fleet group <name> <machine1> [machine2...]"
    return 1
  fi

  if [[ $# -eq 0 ]]; then
    err "Usage: muster fleet group <name> <machine1> [machine2...]"
    return 1
  fi

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  # Validate all machines exist
  local _m
  for _m in "$@"; do
    local exists
    exists=$(fleet_get ".machines.\"${_m}\" // empty")
    if [[ -z "$exists" ]]; then
      err "Machine '${_m}' not found in remotes.json"
      return 1
    fi
  done

  fleet_set_group "$group_name" "$@"
}

# ── ungroup ──

_fleet_cmd_ungroup() {
  local group_name="${1:-}"
  if [[ -z "$group_name" ]]; then
    err "Usage: muster fleet ungroup <name>"
    return 1
  fi

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  fleet_remove_group "$group_name"
}


# Deploy orchestration loaded from lib/commands/fleet_deploy.sh

# ── status ──

_fleet_cmd_status() {
  local target="" json_mode=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      --help|-h)
        echo "Usage: muster fleet status [target] [--json]"
        return 0
        ;;
      --*)
        err "Unknown flag: $1"
        return 1
        ;;
      *)
        target="$1"
        shift
        ;;
    esac
  done

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  # Resolve machines
  local machines=()
  if [[ -n "$target" ]]; then
    local group_members
    group_members=$(fleet_group_machines "$target" 2>/dev/null)
    if [[ -n "$group_members" ]]; then
      while IFS= read -r m; do
        [[ -z "$m" ]] && continue
        machines[${#machines[@]}]="$m"
      done <<< "$group_members"
    else
      machines[0]="$target"
    fi
  else
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      machines[${#machines[@]}]="$m"
    done < <(fleet_machines)
  fi

  if [[ "$json_mode" == "true" ]]; then
    _fleet_status_json "${machines[@]}"
    return 0
  fi

  local w=$(( TERM_COLS - 4 ))
  (( w > 50 )) && w=50
  (( w < 10 )) && w=10
  local inner=$(( w - 2 ))

  echo ""

  local label="Fleet Status"
  local label_pad_len=$(( w - ${#label} - 3 ))
  (( label_pad_len < 1 )) && label_pad_len=1
  local label_pad
  printf -v label_pad '%*s' "$label_pad_len" ""
  label_pad="${label_pad// /─}"
  printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$label" "${RESET}${ACCENT}" "$label_pad" "${RESET}"

  local i=0
  while (( i < ${#machines[@]} )); do
    local machine="${machines[$i]}"
    _fleet_load_machine "$machine"

    local host_str="${_FM_USER}@${_FM_HOST}"
    [[ "$_FM_PORT" != "22" ]] && host_str="${host_str}:${_FM_PORT}"

    local status_icon status_color tag=""

    # Check connectivity
    if fleet_check "$machine"; then
      if [[ "$_FM_MODE" == "muster" ]]; then
        local token
        token=$(fleet_token_get "$machine")
        if [[ -n "$token" ]]; then
          local remote_status
          remote_status=$(fleet_exec "$machine" "MUSTER_TOKEN=${token} muster status --json" 2>/dev/null)
          if printf '%s' "$remote_status" | jq -e '.services' &>/dev/null; then
            local svc_count healthy_count
            svc_count=$(printf '%s' "$remote_status" | jq '.services | length')
            healthy_count=$(printf '%s' "$remote_status" | jq '[.services[] | select(.healthy == true)] | length')
            status_icon="●"; status_color="$GREEN"
            tag=" ${healthy_count}/${svc_count} healthy"
          else
            status_icon="●"; status_color="$GREEN"
            tag=" reachable"
          fi
        else
          status_icon="●"; status_color="$YELLOW"
          tag=" unpaired"
        fi
      else
        status_icon="●"; status_color="$GREEN"
        tag=" reachable"
      fi
    else
      status_icon="●"; status_color="$RED"
      tag=" unreachable"
    fi

    local display="${machine}: ${host_str} (${_FM_MODE})"
    local tag_len=${#tag}
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

    local tag_color="$status_color"

    printf '  %b│%b  %b%s%b %s%s%b%s%b%b│%b\n' \
      "${ACCENT}" "${RESET}" "$status_color" "$status_icon" "${RESET}" \
      "$display" "$pad" "$tag_color" "$tag" "${RESET}" "${ACCENT}" "${RESET}"

    i=$(( i + 1 ))
  done

  local bottom
  printf -v bottom '%*s' "$w" ""
  bottom="${bottom// /─}"
  printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"
  echo ""
}

_fleet_status_json() {
  printf '['
  local first=true
  for machine in "$@"; do
    [[ "$first" == "true" ]] && first=false || printf ','
    _fleet_load_machine "$machine"
    local reachable=false
    fleet_check "$machine" && reachable=true
    printf '{"machine":"%s","host":"%s","port":%s,"mode":"%s","reachable":%s}' \
      "$machine" "$_FM_HOST" "$_FM_PORT" "$_FM_MODE" "$reachable"
  done
  printf ']\n'
}

# ── rollback ──

_fleet_cmd_rollback() {
  # shellcheck disable=SC2034
  local target="" parallel=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parallel) parallel=true; shift ;;
      --help|-h)
        echo "Usage: muster fleet rollback [target] [--parallel]"
        return 0
        ;;
      --*)
        err "Unknown flag: $1"
        return 1
        ;;
      *)
        target="$1"
        shift
        ;;
    esac
  done

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  load_config

  # Resolve machines
  local machines=()
  if [[ -n "$target" ]]; then
    local group_members
    group_members=$(fleet_group_machines "$target" 2>/dev/null)
    if [[ -n "$group_members" ]]; then
      while IFS= read -r m; do
        [[ -z "$m" ]] && continue
        machines[${#machines[@]}]="$m"
      done <<< "$group_members"
    else
      machines[0]="$target"
    fi
  else
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      machines[${#machines[@]}]="$m"
    done < <(fleet_machines)
  fi

  local total=${#machines[@]}
  echo ""
  printf '%b\n' "  ${BOLD}${YELLOW}Fleet Rollback${RESET} — ${total} machine(s)"
  echo ""

  local succeeded=0 failed=0
  local current=0

  for machine in "${machines[@]}"; do
    current=$(( current + 1 ))
    _fleet_load_machine "$machine"

    progress_bar "$current" "$total" "Rollback: ${machine}..."
    echo ""

    local project_dir
    project_dir="$(dirname "$CONFIG_FILE")"
    local log_dir="${project_dir}/.muster/logs"
    local log_file
    log_file="${log_dir}/fleet-${machine}-rollback-$(date +%Y%m%d-%H%M%S).log"

    local rc=0

    if [[ "$_FM_MODE" == "muster" ]]; then
      local token
      token=$(fleet_token_get "$machine")
      if [[ -z "$token" ]]; then
        err "No token for ${machine}"
        failed=$(( failed + 1 ))
        continue
      fi

      local cmd="MUSTER_TOKEN=${token} muster rollback"
      [[ -n "$_FM_PROJECT_DIR" ]] && cmd="cd ${_FM_PROJECT_DIR} && ${cmd}"

      fleet_exec "$machine" "$cmd" >> "$log_file" 2>&1
      rc=$?
    else
      # Push mode: run rollback hooks
      while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        local hook="${project_dir}/.muster/hooks/${svc}/rollback.sh"
        [[ ! -x "$hook" ]] && continue

        fleet_push_hook "$machine" "$hook" "" >> "$log_file" 2>&1 || { rc=1; break; }
      done < <(config_get '.deploy_order[]' 2>/dev/null || config_services)
    fi

    if (( rc == 0 )); then
      ok "${machine} rolled back"
      _history_log_event "fleet:${machine}" "rollback" "ok" ""
      succeeded=$(( succeeded + 1 ))
    else
      err "${machine} rollback failed"
      _history_log_event "fleet:${machine}" "rollback" "failed" ""
      failed=$(( failed + 1 ))
    fi
  done

  echo ""
  if (( failed == 0 )); then
    ok "Fleet rollback complete — ${succeeded}/${total} succeeded"
  else
    warn "Fleet rollback — ${succeeded} succeeded, ${failed} failed (${total} total)"
  fi
  echo ""
}

# ── keygen ──

_fleet_cmd_keygen() {
  source "$MUSTER_ROOT/lib/core/payload_sign.sh"

  if [[ -f "$_PAYLOAD_PRIVKEY" && "${1:-}" != "--force" ]]; then
    local fp
    fp=$(payload_fingerprint 2>/dev/null || echo "unknown")
    echo ""
    ok "Signing keypair already exists"
    printf '%b\n' "  ${DIM}Fingerprint: ${fp}${RESET}"
    printf '%b\n' "  ${DIM}Public key:  ${_PAYLOAD_PUBKEY}${RESET}"
    printf '%b\n' "  ${DIM}Use --force to regenerate${RESET}"
    echo ""
    return 0
  fi

  if [[ "${1:-}" == "--force" && -f "$_PAYLOAD_PRIVKEY" ]]; then
    rm -f "$_PAYLOAD_PRIVKEY" "$_PAYLOAD_PUBKEY" "$_PAYLOAD_KEYTYPE_FILE"
  fi

  _payload_ensure_keypair || return 1

  local algo fp
  algo=$(cat "$_PAYLOAD_KEYTYPE_FILE" 2>/dev/null || echo "unknown")
  fp=$(payload_fingerprint 2>/dev/null || echo "unknown")

  echo ""
  ok "Signing keypair generated (${algo})"
  printf '%b\n' "  ${DIM}Fingerprint: ${fp}${RESET}"
  printf '%b\n' "  ${DIM}Public key:  ${_PAYLOAD_PUBKEY}${RESET}"
  echo ""
  printf '%b\n' "  ${DIM}Next: muster fleet trust-key <machine>${RESET}"
  printf '%b\n' "  ${DIM}Then: muster settings --global signing on${RESET}"
  echo ""
}

# ── trust-key ──

_fleet_cmd_trust_key() {
  local machine="${1:-}"
  if [[ -z "$machine" ]]; then
    err "Usage: muster fleet trust-key <machine>"
    return 1
  fi

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  source "$MUSTER_ROOT/lib/core/payload_sign.sh"

  if [[ ! -f "$_PAYLOAD_PUBKEY" ]]; then
    err "No signing keypair — run: muster fleet keygen"
    return 1
  fi

  echo ""
  info "Distributing public key to ${machine}..."

  source "$MUSTER_ROOT/lib/commands/fleet_sync.sh"
  _fleet_sync_pubkey "$machine"

  local fp
  fp=$(payload_fingerprint 2>/dev/null || echo "unknown")
  ok "Public key distributed (${fp})"
  echo ""
}

# ── list-keys ──

_fleet_cmd_list_keys() {
  local machine="${1:-}"

  source "$MUSTER_ROOT/lib/core/payload_sign.sh"

  if [[ -z "$machine" ]]; then
    # Show local keypair info
    echo ""
    if [[ -f "$_PAYLOAD_PUBKEY" ]]; then
      local fp algo
      fp=$(payload_fingerprint 2>/dev/null || echo "unknown")
      algo=$(cat "$_PAYLOAD_KEYTYPE_FILE" 2>/dev/null || echo "unknown")
      printf '%b\n' "  ${BOLD}Local signing key${RESET}"
      printf '%b\n' "  ${DIM}Algorithm:   ${algo}${RESET}"
      printf '%b\n' "  ${DIM}Fingerprint: ${fp}${RESET}"
      printf '%b\n' "  ${DIM}Public key:  ${_PAYLOAD_PUBKEY}${RESET}"
    else
      printf '%b\n' "  ${DIM}No local signing key — run: muster fleet keygen${RESET}"
    fi
    echo ""
    return 0
  fi

  # Show keys on remote machine
  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  _fleet_load_machine "$machine"
  _fleet_build_opts

  echo ""
  printf '%b\n' "  ${BOLD}Trusted keys on ${machine}${RESET}"
  echo ""

  # shellcheck disable=SC2086
  ssh $_FLEET_SSH_OPTS "${_FM_USER}@${_FM_HOST}" \
    'for f in $HOME/.muster/fleet/authorized_keys/*.json; do [ -f "$f" ] || continue; echo "$(basename "$f" .json):"; jq -r ".keys[] | \"  \\(.label)  \\(.added)\"" "$f" 2>/dev/null; done' 2>/dev/null || {
    warn "Could not read keys from ${machine}"
  }
  echo ""
}

# ── revoke-key ──

_fleet_cmd_revoke_key() {
  local machine="" label=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label) label="$2"; shift 2 ;;
      -*) err "Unknown flag: $1"; return 1 ;;
      *) machine="$1"; shift ;;
    esac
  done

  if [[ -z "$machine" || -z "$label" ]]; then
    err "Usage: muster fleet revoke-key <machine> --label <name>"
    return 1
  fi

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  _fleet_load_machine "$machine"
  _fleet_build_opts

  # shellcheck disable=SC2086
  ssh $_FLEET_SSH_OPTS "${_FM_USER}@${_FM_HOST}" "bash -s" <<REVOKE_EOF 2>/dev/null
for f in \$HOME/.muster/fleet/authorized_keys/*.json; do
  [ -f "\$f" ] || continue
  if command -v jq >/dev/null 2>&1; then
    TMP="\${f}.tmp"
    jq --arg l "${label}" '.keys = [.keys[] | select(.label != \$l)]' "\$f" > "\$TMP" && mv "\$TMP" "\$f"
  fi
done
REVOKE_EOF

  ok "Key '${label}' revoked on ${machine}"
}

# ── edit ──

_fleet_cmd_edit() {
  local machine=""
  local new_hook_mode="" new_user="" new_host="" new_port=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sync)   new_hook_mode="sync"; shift ;;
      --manual) new_hook_mode="manual"; shift ;;
      --user)   new_user="$2"; shift 2 ;;
      --host)   new_host="$2"; shift 2 ;;
      --port)   new_port="$2"; shift 2 ;;
      --help|-h)
        echo "Usage: muster fleet edit <machine> [options]"
        echo ""
        echo "Options:"
        echo "  --sync              Switch to sync hook mode"
        echo "  --manual            Switch to manual hook mode"
        echo "  --user <user>       Change SSH user"
        echo "  --host <host>       Change host"
        echo "  --port <port>       Change SSH port"
        return 0
        ;;
      -*) err "Unknown flag: $1"; return 1 ;;
      *) machine="$1"; shift ;;
    esac
  done

  if [[ -z "$machine" ]]; then
    err "Usage: muster fleet edit <machine> [--sync|--manual] [--user X] [--host X] [--port X]"
    return 1
  fi

  if ! fleet_load_config; then
    err "No remotes.json found"
    return 1
  fi

  local existing
  existing=$(fleet_get ".machines.\"${machine}\" // empty")
  if [[ -z "$existing" ]]; then
    err "Machine '${machine}' not found"
    return 1
  fi

  local changed=false

  if [[ -n "$new_hook_mode" ]]; then
    fleet_set ".machines.\"${machine}\".hook_mode" "\"${new_hook_mode}\""
    ok "Hook mode set to '${new_hook_mode}' for ${machine}"
    changed=true
  fi

  if [[ -n "$new_user" ]]; then
    fleet_set ".machines.\"${machine}\".user" "\"${new_user}\""
    ok "User set to '${new_user}' for ${machine}"
    changed=true
  fi

  if [[ -n "$new_host" ]]; then
    fleet_set ".machines.\"${machine}\".host" "\"${new_host}\""
    ok "Host set to '${new_host}' for ${machine}"
    changed=true
  fi

  if [[ -n "$new_port" ]]; then
    fleet_set ".machines.\"${machine}\".port" "${new_port}"
    ok "Port set to '${new_port}' for ${machine}"
    changed=true
  fi

  if [[ "$changed" == "false" ]]; then
    info "No changes specified. Use --help to see options."
  fi
}
