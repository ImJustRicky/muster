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

cmd_settings() {
  load_config

  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"

  while true; do
    local project
    project=$(config_get '.project')
    local services
    services=$(config_services)

    clear
    echo ""
    echo -e "  ${BOLD}${ACCENT_BRIGHT}Settings${RESET}  ${WHITE}${project}${RESET}"
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

    menu_select "Settings" "Services" "Open config" "Back"

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
