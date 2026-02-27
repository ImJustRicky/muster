#!/usr/bin/env bash
# muster/lib/commands/settings.sh — Interactive project settings

source "$MUSTER_ROOT/lib/tui/menu.sh"

# Cycle menu: items cycle through options on Enter, "Back" exits
# Globals before calling:
#   _TOG_LABELS[]   — display label per item
#   _TOG_OPTIONS[]   — pipe-separated options per item (e.g. "OFF|ON" or "Off|Save|Session|Always")
#   _TOG_STATES[]    — current option index per item
# Updates _TOG_STATES[] in place
_toggle_select() {
  local title="$1"
  local count=${#_TOG_LABELS[@]}
  local selected=0

  tput civis

  local w=$(( TERM_COLS - 4 ))
  (( w > 50 )) && w=50
  (( w < 10 )) && w=10
  local inner=$(( w - 2 ))

  # Parse option counts per item
  local _tog_opt_counts=()
  local idx=0
  while (( idx < count )); do
    local opts="${_TOG_OPTIONS[$idx]}"
    local ocount=1
    local tmp="$opts"
    while [[ "$tmp" == *"|"* ]]; do
      ocount=$((ocount + 1))
      tmp="${tmp#*|}"
    done
    _tog_opt_counts[$idx]=$ocount
    idx=$((idx + 1))
  done

  # Get the Nth option from a pipe-separated string
  _tog_get_opt() {
    local opts="$1" n="$2"
    local i=0
    while (( i < n )); do
      opts="${opts#*|}"
      i=$((i + 1))
    done
    printf '%s' "${opts%%|*}"
  }

  _tog_draw_header() {
    echo ""
    echo -e "  ${BOLD}${title}${RESET}"
    echo -e "  ${DIM}↑/↓ navigate  ⏎ cycle  q back${RESET}"
    echo ""
  }

  _tog_draw() {
    local border
    border=$(printf '%*s' "$w" "" | sed 's/ /─/g')
    printf '%b' "  ${ACCENT}┌${border}┐${RESET}\n"

    local i=0
    while (( i < count )); do
      local label="${_TOG_LABELS[$i]}"
      local cur_opt
      cur_opt=$(_tog_get_opt "${_TOG_OPTIONS[$i]}" "${_TOG_STATES[$i]}")

      # Color: first option (index 0) = red/off, anything else = green/on
      local state_color="$GREEN"
      (( _TOG_STATES[i] == 0 )) && state_color="$RED"

      local prefix="  "
      (( i == selected )) && prefix="${ACCENT}>${RESET} "

      local content_len=$(( 5 + ${#label} + ${#cur_opt} ))
      local pad_len=$(( inner - content_len ))
      (( pad_len < 0 )) && pad_len=0
      local pad
      pad=$(printf '%*s' "$pad_len" "")

      printf '%b' "  ${ACCENT}│${RESET} ${prefix}${label}${pad} ${state_color}${cur_opt}${RESET}${ACCENT}│${RESET}\n"
      i=$((i + 1))
    done

    # Back row
    local back_prefix="  "
    (( selected == count )) && back_prefix="${ACCENT}>${RESET} "
    local back_pad_len=$(( inner - 3 - 4 ))
    (( back_pad_len < 0 )) && back_pad_len=0
    local back_pad
    back_pad=$(printf '%*s' "$back_pad_len" "")
    printf '%b' "  ${ACCENT}│${RESET} ${back_prefix}${DIM}Back${RESET}${back_pad}${ACCENT}│${RESET}\n"

    border=$(printf '%*s' "$w" "" | sed 's/ /─/g')
    printf '%b' "  ${ACCENT}└${border}┘${RESET}\n"
  }

  local total_lines=$(( count + 3 ))

  _tog_clear() {
    local i=0
    while (( i < total_lines )); do
      tput cuu1
      i=$((i + 1))
    done
    tput ed
  }

  _tog_read_key() {
    local key
    IFS= read -rsn1 key || true
    if [[ "$key" == $'\x1b' ]]; then
      local seq1 seq2
      IFS= read -rsn1 -t 1 seq1 || true
      IFS= read -rsn1 -t 1 seq2 || true
      key="${key}${seq1}${seq2}"
    fi
    REPLY="$key"
  }

  _tog_draw_header
  _tog_draw

  while true; do
    _tog_read_key

    if [[ "$_MUSTER_INPUT_DIRTY" == "true" ]]; then
      _MUSTER_INPUT_DIRTY="false"
      _tog_draw_header
      _tog_draw
      continue
    fi

    case "$REPLY" in
      $'\x1b[A')
        (( selected > 0 )) && selected=$((selected - 1))
        ;;
      $'\x1b[B')
        (( selected < count )) && selected=$((selected + 1))
        ;;
      'q'|'Q')
        _tog_clear
        tput cnorm
        return 0
        ;;
      '')
        if (( selected == count )); then
          _tog_clear
          tput cnorm
          return 0
        fi
        # Cycle to next option
        local next=$(( _TOG_STATES[selected] + 1 ))
        if (( next >= _tog_opt_counts[selected] )); then
          next=0
        fi
        _TOG_STATES[$selected]=$next
        ;;
      *)
        continue
        ;;
    esac

    _tog_clear
    _tog_draw
  done
}

_settings_open_config() {
  local config_dir
  config_dir="$(dirname "$CONFIG_FILE")"

  echo ""

  # Try to open in system file manager / reveal in GUI
  if [[ "$MUSTER_OS" == "macos" ]]; then
    # macOS: open Finder to the folder, highlighting deploy.json
    open -R "$CONFIG_FILE" 2>/dev/null && {
      ok "Opened in Finder"
      echo -e "  ${DIM}${CONFIG_FILE}${RESET}"
      echo ""
      return 0
    }
  elif [[ "$MUSTER_OS" == "linux" ]]; then
    # Linux: try xdg-open on the directory
    if has_cmd xdg-open; then
      xdg-open "$config_dir" 2>/dev/null &
      ok "Opened file manager"
      echo -e "  ${DIM}${CONFIG_FILE}${RESET}"
      echo ""
      return 0
    fi
  fi

  # No GUI or open failed — just print the path
  info "Config file:"
  echo ""
  echo -e "  ${WHITE}${CONFIG_FILE}${RESET}"
  echo ""
  echo -e "  ${DIM}Press any key to continue...${RESET}"
  IFS= read -rsn1 || true
}

# ── Non-interactive global settings ──

_settings_global_cli() {
  local key="$1"
  shift

  # No key: dump all global settings
  if [[ -z "$key" ]]; then
    global_config_dump
    return 0
  fi

  # Validate key
  case "$key" in
    color_mode|log_retention_days|default_stack|default_health_timeout|scanner_exclude|update_check) ;;
    *)
      err "Unknown global setting: ${key}"
      echo "  Valid keys: color_mode, log_retention_days, default_stack,"
      echo "              default_health_timeout, scanner_exclude, update_check"
      return 1
      ;;
  esac

  # scanner_exclude has sub-commands: add/remove
  if [[ "$key" == "scanner_exclude" ]]; then
    local action="${1:-}"
    shift 2>/dev/null || true
    case "$action" in
      add)
        local patterns="$*"
        if [[ -z "$patterns" ]]; then
          err "Usage: muster settings --global scanner_exclude add <patterns>"
          return 1
        fi
        # Split on comma and add each
        local IFS=','
        local p
        for p in $patterns; do
          # Trim whitespace
          p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [[ -z "$p" ]] && continue
          local quoted
          quoted=$(printf '%s' "$p" | sed 's/\\/\\\\/g;s/"/\\"/g')
          global_config_set "scanner_exclude" "(.scanner_exclude + [\"${quoted}\"] | unique)"
        done
        ok "Updated scanner_exclude"
        global_config_get "scanner_exclude"
        return 0
        ;;
      remove)
        local patterns="$*"
        if [[ -z "$patterns" ]]; then
          err "Usage: muster settings --global scanner_exclude remove <patterns>"
          return 1
        fi
        local IFS=','
        local p
        for p in $patterns; do
          p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [[ -z "$p" ]] && continue
          local quoted
          quoted=$(printf '%s' "$p" | sed 's/\\/\\\\/g;s/"/\\"/g')
          global_config_set "scanner_exclude" "([.scanner_exclude[] | select(. != \"${quoted}\")])"
        done
        ok "Updated scanner_exclude"
        global_config_get "scanner_exclude"
        return 0
        ;;
      *)
        # Just print current value
        global_config_get "scanner_exclude"
        return 0
        ;;
    esac
  fi

  local value="${1:-}"

  # No value: print current
  if [[ -z "$value" ]]; then
    global_config_get "$key"
    return 0
  fi

  # Validate and set
  case "$key" in
    color_mode)
      case "$value" in
        auto|always|never) ;;
        *) err "color_mode must be auto, always, or never"; return 1 ;;
      esac
      global_config_set "$key" "\"$value\""
      ;;
    log_retention_days|default_health_timeout)
      case "$value" in
        *[!0-9]*) err "${key} must be a number"; return 1 ;;
      esac
      global_config_set "$key" "$value"
      ;;
    default_stack)
      case "$value" in
        bare|docker|compose|k8s) ;;
        *) err "default_stack must be bare, docker, compose, or k8s"; return 1 ;;
      esac
      global_config_set "$key" "\"$value\""
      ;;
    update_check)
      case "$value" in
        on|off) ;;
        *) err "update_check must be on or off"; return 1 ;;
      esac
      global_config_set "$key" "\"$value\""
      ;;
  esac

  ok "${key} = ${value}"
  return 0
}

# ── Interactive global settings ──

_settings_muster_global() {
  while true; do
    local color_mode log_retention default_stack health_timeout update_check scanner_ex

    color_mode=$(global_config_get "color_mode" 2>/dev/null)
    : "${color_mode:=auto}"
    log_retention=$(global_config_get "log_retention_days" 2>/dev/null)
    : "${log_retention:=7}"
    default_stack=$(global_config_get "default_stack" 2>/dev/null)
    : "${default_stack:=bare}"
    health_timeout=$(global_config_get "default_health_timeout" 2>/dev/null)
    : "${health_timeout:=10}"
    update_check=$(global_config_get "update_check" 2>/dev/null)
    : "${update_check:=on}"
    scanner_ex=$(global_config_get "scanner_exclude" 2>/dev/null)
    if [[ "$scanner_ex" == "[]" || -z "$scanner_ex" ]]; then
      scanner_ex="(none)"
    fi

    # Build toggle data
    _TOG_LABELS=()
    _TOG_OPTIONS=()
    _TOG_STATES=()

    # Color mode: auto / always / never
    _TOG_LABELS[0]="Color mode"
    _TOG_OPTIONS[0]="auto|always|never"
    case "$color_mode" in
      always) _TOG_STATES[0]=1 ;;
      never)  _TOG_STATES[0]=2 ;;
      *)      _TOG_STATES[0]=0 ;;
    esac

    # Update check: on / off
    _TOG_LABELS[1]="Update check"
    _TOG_OPTIONS[1]="on|off"
    case "$update_check" in
      off) _TOG_STATES[1]=1 ;;
      *)   _TOG_STATES[1]=0 ;;
    esac

    # Default stack: bare / docker / compose / k8s
    _TOG_LABELS[2]="Default stack"
    _TOG_OPTIONS[2]="bare|docker|compose|k8s"
    case "$default_stack" in
      docker)  _TOG_STATES[2]=1 ;;
      compose) _TOG_STATES[2]=2 ;;
      k8s)     _TOG_STATES[2]=3 ;;
      *)       _TOG_STATES[2]=0 ;;
    esac

    echo ""
    _toggle_select "Muster Settings"

    # Read back chosen values
    local new_color new_update new_stack
    case $(( _TOG_STATES[0] )) in
      1) new_color="always" ;;
      2) new_color="never" ;;
      *) new_color="auto" ;;
    esac
    case $(( _TOG_STATES[1] )) in
      1) new_update="off" ;;
      *) new_update="on" ;;
    esac
    case $(( _TOG_STATES[2] )) in
      1) new_stack="docker" ;;
      2) new_stack="compose" ;;
      3) new_stack="k8s" ;;
      *) new_stack="bare" ;;
    esac

    # Save toggleable settings
    global_config_set "color_mode" "\"$new_color\""
    global_config_set "update_check" "\"$new_update\""
    global_config_set "default_stack" "\"$new_stack\""

    # Now prompt for numeric settings and scanner excludes
    _settings_muster_extras "$log_retention" "$health_timeout" "$scanner_ex"

    ok "Muster settings saved"
    echo ""
    return 0
  done
}

_settings_muster_extras() {
  local cur_retention="$1" cur_timeout="$2" cur_excludes="$3"

  echo ""

  # Log retention
  printf '%b' "  ${BOLD}Log retention days${RESET} ${DIM}[${cur_retention}]:${RESET} "
  local new_retention
  IFS= read -r new_retention
  new_retention=$(printf '%s' "$new_retention" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -n "$new_retention" ]]; then
    case "$new_retention" in
      *[!0-9]*)
        warn "Invalid number, keeping ${cur_retention}"
        ;;
      *)
        global_config_set "log_retention_days" "$new_retention"
        ;;
    esac
  fi

  # Health timeout
  printf '%b' "  ${BOLD}Default health timeout (s)${RESET} ${DIM}[${cur_timeout}]:${RESET} "
  local new_timeout
  IFS= read -r new_timeout
  new_timeout=$(printf '%s' "$new_timeout" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -n "$new_timeout" ]]; then
    case "$new_timeout" in
      *[!0-9]*)
        warn "Invalid number, keeping ${cur_timeout}"
        ;;
      *)
        global_config_set "default_health_timeout" "$new_timeout"
        ;;
    esac
  fi

  # Scanner excludes
  echo ""
  printf '%b\n' "  ${BOLD}Scanner excludes:${RESET} ${DIM}${cur_excludes}${RESET}"
  printf '%b' "  ${DIM}Add patterns (comma-sep, empty to skip):${RESET} "
  local add_patterns
  IFS= read -r add_patterns
  add_patterns=$(printf '%s' "$add_patterns" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -n "$add_patterns" ]]; then
    local IFS=','
    local p
    for p in $add_patterns; do
      p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$p" ]] && continue
      local quoted
      quoted=$(printf '%s' "$p" | sed 's/\\/\\\\/g;s/"/\\"/g')
      global_config_set "scanner_exclude" "(.scanner_exclude + [\"${quoted}\"] | unique)"
    done
  fi

  printf '%b' "  ${DIM}Remove patterns (comma-sep, empty to skip):${RESET} "
  local rm_patterns
  IFS= read -r rm_patterns
  rm_patterns=$(printf '%s' "$rm_patterns" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -n "$rm_patterns" ]]; then
    local IFS=','
    local p
    for p in $rm_patterns; do
      p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$p" ]] && continue
      local quoted
      quoted=$(printf '%s' "$p" | sed 's/\\/\\\\/g;s/"/\\"/g')
      global_config_set "scanner_exclude" "([.scanner_exclude[] | select(. != \"${quoted}\")])"
    done
  fi
}

cmd_settings() {
  # Handle --global flag for non-interactive use
  if [[ "${1:-}" == "--global" ]]; then
    shift
    _settings_global_cli "$@"
    return $?
  fi

  load_config

  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  while true; do
    clear
    echo ""
    echo -e "  ${BOLD}${ACCENT_BRIGHT}Settings${RESET}"
    echo ""

    menu_select "Settings" "Project Settings" "Muster Settings" "Back"

    case "$MENU_RESULT" in
      "Project Settings")
        _settings_project
        ;;
      "Muster Settings")
        _settings_muster_global
        ;;
      Back)
        return 0
        ;;
    esac
  done
}

_settings_project() {
  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  while true; do
    local project
    project=$(config_get '.project')
    local services
    services=$(config_services)

    clear
    echo ""
    echo -e "  ${BOLD}${ACCENT_BRIGHT}Project Settings${RESET}  ${WHITE}${project}${RESET}"
    echo ""

    local w=$(( TERM_COLS - 4 ))
    (( w > 50 )) && w=50
    (( w < 10 )) && w=10
    local inner=$(( w - 2 ))

    # Overview box
    local label="Overview"
    local label_pad_len=$(( w - ${#label} - 3 ))
    (( label_pad_len < 1 )) && label_pad_len=1
    local label_pad
    label_pad=$(printf '%*s' "$label_pad_len" "" | sed 's/ /─/g')
    printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$label" "${RESET}${ACCENT}" "$label_pad" "${RESET}"

    _settings_row "$inner" "Project" "$project"

    local config_display="$CONFIG_FILE"
    [[ "$config_display" == "$HOME"* ]] && config_display="~${config_display#$HOME}"
    _settings_row "$inner" "Config" "$config_display"

    local svc_count=0
    while IFS= read -r svc; do
      [[ -z "$svc" ]] && continue
      svc_count=$((svc_count + 1))
    done <<< "$services"
    _settings_row "$inner" "Services" "$svc_count"

    # Hooks summary per service
    while IFS= read -r svc; do
      [[ -z "$svc" ]] && continue
      local name
      name=$(config_get ".services.${svc}.name")
      local hooks=""
      local hook_dir="${project_dir}/.muster/hooks/${svc}"
      [[ -x "${hook_dir}/deploy.sh" ]] && hooks="${hooks}D"
      [[ -x "${hook_dir}/health.sh" ]] && hooks="${hooks}H"
      [[ -x "${hook_dir}/rollback.sh" ]] && hooks="${hooks}R"
      [[ -x "${hook_dir}/logs.sh" ]] && hooks="${hooks}L"
      [[ -x "${hook_dir}/cleanup.sh" ]] && hooks="${hooks}C"
      [[ -z "$hooks" ]] && hooks="none"
      _settings_row "$inner" "$name" "$hooks"
    done <<< "$services"

    local bottom
    bottom=$(printf '%*s' "$w" "" | sed 's/ /─/g')
    printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"
    echo -e "  ${DIM}D=deploy H=health R=rollback L=logs C=cleanup${RESET}"
    echo ""

    menu_select "Project Settings" "Services" "Open config" "Back"

    case "$MENU_RESULT" in
      Services)
        _settings_services
        ;;
      "Open config")
        _settings_open_config
        ;;
      Back)
        return 0
        ;;
    esac
  done
}

_settings_services() {
  local services
  services=$(config_services)

  local svc_list=()
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    svc_list[${#svc_list[@]}]="$svc"
  done <<< "$services"

  local svc_names=()
  local i=0
  while (( i < ${#svc_list[@]} )); do
    local name
    name=$(config_get ".services.${svc_list[$i]}.name")
    svc_names[$i]="$name"
    i=$((i + 1))
  done
  svc_names[${#svc_names[@]}]="Back"

  echo ""
  menu_select "Which service?" "${svc_names[@]}"

  [[ "$MENU_RESULT" == "Back" ]] && return 0

  # Find the service key from the selected name
  local target_svc=""
  i=0
  while (( i < ${#svc_list[@]} )); do
    if [[ "${svc_names[$i]}" == "$MENU_RESULT" ]]; then
      target_svc="${svc_list[$i]}"
      break
    fi
    i=$((i + 1))
  done

  [[ -z "$target_svc" ]] && return 0

  _settings_service_toggles "$target_svc"
}

_settings_service_toggles() {
  local svc="$1"
  local name
  name=$(config_get ".services.${svc}.name")

  # Build toggle data in globals
  local _tog_keys=()
  _TOG_LABELS=()
  _TOG_OPTIONS=()
  _TOG_STATES=()

  # Skip deploy — ON/OFF toggle
  local skip_deploy
  skip_deploy=$(config_get ".services.${svc}.skip_deploy")
  _tog_keys[${#_tog_keys[@]}]="skip_deploy"
  _TOG_LABELS[${#_TOG_LABELS[@]}]="Skip deploy"
  _TOG_OPTIONS[${#_TOG_OPTIONS[@]}]="OFF|ON"
  if [[ "$skip_deploy" == "true" ]]; then
    _TOG_STATES[${#_TOG_STATES[@]}]=1
  else
    _TOG_STATES[${#_TOG_STATES[@]}]=0
  fi

  # Health check — ON/OFF toggle
  local health_enabled
  health_enabled=$(config_get ".services.${svc}.health.enabled")
  _tog_keys[${#_tog_keys[@]}]="health"
  _TOG_LABELS[${#_TOG_LABELS[@]}]="Health check"
  _TOG_OPTIONS[${#_TOG_OPTIONS[@]}]="OFF|ON"
  if [[ "$health_enabled" == "false" ]]; then
    _TOG_STATES[${#_TOG_STATES[@]}]=0
  else
    local health_type
    health_type=$(config_get ".services.${svc}.health.type")
    if [[ "$health_type" != "null" && -n "$health_type" ]]; then
      _TOG_STATES[${#_TOG_STATES[@]}]=1
    else
      _TOG_STATES[${#_TOG_STATES[@]}]=0
    fi
  fi

  # Credentials — cycle: Off / Save always / Once per session / Every time
  local cred_mode
  cred_mode=$(config_get ".services.${svc}.credentials.mode")
  _tog_keys[${#_tog_keys[@]}]="credentials"
  _TOG_LABELS[${#_TOG_LABELS[@]}]="Credentials"
  _TOG_OPTIONS[${#_TOG_OPTIONS[@]}]="Off|Save always|Once per session|Every time"
  case "$cred_mode" in
    save)    _TOG_STATES[${#_TOG_STATES[@]}]=1 ;;
    session) _TOG_STATES[${#_TOG_STATES[@]}]=2 ;;
    always)  _TOG_STATES[${#_TOG_STATES[@]}]=3 ;;
    *)       _TOG_STATES[${#_TOG_STATES[@]}]=0 ;;
  esac

  echo ""
  _toggle_select "$name"

  # Apply changes
  local i=0
  while (( i < ${#_tog_keys[@]} )); do
    case "${_tog_keys[$i]}" in
      skip_deploy)
        if (( _TOG_STATES[i] >= 1 )); then
          config_set ".services.${svc}.skip_deploy" "true"
        else
          config_set ".services.${svc}.skip_deploy" "false"
        fi
        ;;
      health)
        if (( _TOG_STATES[i] >= 1 )); then
          config_set ".services.${svc}.health.enabled" "true"
        else
          config_set ".services.${svc}.health.enabled" "false"
        fi
        ;;
      credentials)
        case $(( _TOG_STATES[i] )) in
          0) config_set ".services.${svc}.credentials" '{"enabled":false,"mode":"off"}' ;;
          1) config_set ".services.${svc}.credentials" '{"enabled":true,"mode":"save"}' ;;
          2) config_set ".services.${svc}.credentials" '{"enabled":true,"mode":"session"}' ;;
          3) config_set ".services.${svc}.credentials" '{"enabled":true,"mode":"always"}' ;;
        esac
        ;;
    esac
    i=$((i + 1))
  done

  ok "Settings saved for ${name}"
  echo ""
}

# Print a key-value row inside a box
_settings_row() {
  local inner="$1" key="$2" val="$3"

  local max_val=$(( inner - ${#key} - 5 ))
  (( max_val < 3 )) && max_val=3
  if (( ${#val} > max_val )); then
    val="...${val: -$((max_val - 3))}"
  fi

  local content_len=$(( 3 + ${#key} + 2 + ${#val} ))
  local pad_len=$(( inner - content_len ))
  (( pad_len < 0 )) && pad_len=0
  local pad
  pad=$(printf '%*s' "$pad_len" "")

  printf '  %b│%b %b%s%b  %s%s%b│%b\n' \
    "${ACCENT}" "${RESET}" "${WHITE}" "$key" "${RESET}" "$val" "$pad" "${ACCENT}" "${RESET}"
}
