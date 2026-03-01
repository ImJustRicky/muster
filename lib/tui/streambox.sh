#!/usr/bin/env bash
# muster/lib/tui/streambox.sh — Live-scrolling log box

# Colorize a log line based on pattern matching
# Usage: _colorize_log_line "line text"
# Prints the colored line (no newline). Respects log_color_mode setting.
_colorize_log_line() {
  local _cl_line="$1"
  local _cl_mode="${_LOG_COLOR_MODE:-auto}"

  case "$_cl_mode" in
    none)
      printf '%s' "$_cl_line"
      return
      ;;
    raw)
      # Pass through as-is (caller should not strip ANSI)
      printf '%s' "$_cl_line"
      return
      ;;
  esac

  # auto mode: pattern-match coloring
  case "$_cl_line" in
    *[Ee][Rr][Rr][Oo][Rr]*|*[Ff][Aa][Tt][Aa][Ll]*)
      printf '%b%s%b' "${RED}" "$_cl_line" "${RESET}"
      ;;
    *[Ww][Aa][Rr][Nn]*|*WARNING*)
      printf '%b%s%b' "${YELLOW}" "$_cl_line" "${RESET}"
      ;;
    *[Ss]uccess*|*[Ss]uccessfully*|*built*|*healthy*|*[Cc]omplete*)
      printf '%b%s%b' "${GREEN}" "$_cl_line" "${RESET}"
      ;;
    *Step\ *|*"--->"*|*"-->"*)
      printf '%b%s%b' "${ACCENT}" "$_cl_line" "${RESET}"
      ;;
    *)
      printf '%b%s%b' "${DIM}" "$_cl_line" "${RESET}"
      ;;
  esac
}

# Full-screen log viewer (called on Ctrl+O)
# Usage: _log_viewer "Title" "logfile" [pid]
_log_viewer() {
  local _lv_title="$1" _lv_log="$2" _lv_pid="${3:-}"

  # Cache log color mode for the session (avoid spawning jq per line)
  _LOG_COLOR_MODE=$(global_config_get "log_color_mode" 2>/dev/null)
  : "${_LOG_COLOR_MODE:=auto}"

  tput smcup
  tput civis 2>/dev/null  # hide cursor

  update_term_size
  local _lv_rows=$TERM_ROWS
  local _lv_cols=$TERM_COLS
  local _lv_content_h=$(( _lv_rows - 3 ))  # header + separator + footer
  (( _lv_content_h < 1 )) && _lv_content_h=1

  # State
  local _lv_offset=0
  local _lv_follow="true"
  local _lv_total=0

  # ── Draw helpers ──

  _lv_draw_header() {
    tput cup 0 0
    # Yellow background header bar
    local _hdr_left="  // muster  ${_lv_title}"
    local _hdr_right="Ctrl+O close  "
    local _hdr_pad=$(( _lv_cols - ${#_hdr_left} - ${#_hdr_right} ))
    (( _hdr_pad < 1 )) && _hdr_pad=1
    printf '\033[48;5;178m\033[38;5;0m\033[1m%s%*s%s\033[0m' "$_hdr_left" "$_hdr_pad" "" "$_hdr_right"
    # Separator
    tput cup 1 0
    local _sep=""
    _sep=$(printf '%*s' "$_lv_cols" "" | sed 's/ /─/g')
    printf '%b%s%b' "${DIM}" "$_sep" "${RESET}"
  }

  _lv_draw_footer() {
    tput cup $(( _lv_rows - 1 )) 0
    local _ft_left="  ↑↓/jk scroll  g/G top/bottom"
    local _ft_mode=""
    if [[ "$_lv_follow" == "true" ]]; then
      _ft_mode="following"
    else
      local _lv_bot=$(( _lv_offset + _lv_content_h ))
      (( _lv_bot > _lv_total )) && _lv_bot=$_lv_total
      _ft_mode="line $(( _lv_offset + 1 ))–${_lv_bot}/${_lv_total}"
    fi
    local _ft_right="Ctrl+O close  "
    local _ft_mid="  •  ${_ft_mode}"
    local _ft_pad=$(( _lv_cols - ${#_ft_left} - ${#_ft_mid} - ${#_ft_right} ))
    (( _ft_pad < 1 )) && _ft_pad=1
    printf '\033[48;5;236m\033[38;5;250m%s%s%*s%s\033[0m' "$_ft_left" "$_ft_mid" "$_ft_pad" "" "$_ft_right"
  }

  _lv_draw_content() {
    # Read log lines into array
    local _lv_lines=()
    if [[ -f "$_lv_log" ]]; then
      local _ll=""
      while IFS= read -r _ll || [[ -n "$_ll" ]]; do
        # Strip ANSI codes for display
        _ll=$(printf '%s' "$_ll" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r')
        _lv_lines[${#_lv_lines[@]}]="$_ll"
      done < "$_lv_log"
    fi
    _lv_total=${#_lv_lines[@]}

    # Auto-follow: jump to bottom
    if [[ "$_lv_follow" == "true" ]]; then
      _lv_offset=$(( _lv_total - _lv_content_h ))
      (( _lv_offset < 0 )) && _lv_offset=0
    fi

    # Render visible lines
    local _vi=0
    while (( _vi < _lv_content_h )); do
      tput cup $(( _vi + 2 )) 0
      local _idx=$(( _lv_offset + _vi ))
      if (( _idx < _lv_total )); then
        local _vl="${_lv_lines[$_idx]}"
        local _max=$(( _lv_cols - 2 ))
        if (( ${#_vl} > _max )); then
          _vl="${_vl:0:$(( _max - 3 ))}..."
        fi
        printf ' '
        _colorize_log_line "$_vl"
      fi
      tput el  # clear to end of line
      _vi=$(( _vi + 1 ))
    done
  }

  # ── Initial draw ──
  tput clear
  _lv_draw_header
  _lv_draw_content
  _lv_draw_footer

  # ── Key loop ──
  while true; do
    local _k=""
    IFS= read -rsn1 -t 1 _k 2>/dev/null || true

    # Check if command process is still running (for live-follow refresh)
    local _lv_live="false"
    if [[ -n "$_lv_pid" ]] && kill -0 "$_lv_pid" 2>/dev/null; then
      _lv_live="true"
    fi

    if [[ "$_k" == $'\x0f' ]]; then
      # Ctrl+O — close viewer
      break
    elif [[ "$_k" == $'\x1b' ]]; then
      # Escape sequence — read 2 more chars for arrow keys
      local _k2="" _k3=""
      IFS= read -rsn1 -t 1 _k2 2>/dev/null || true
      IFS= read -rsn1 -t 1 _k3 2>/dev/null || true
      if [[ "$_k2" == "[" ]]; then
        case "$_k3" in
          A)  # Up arrow
            _lv_follow="false"
            (( _lv_offset > 0 )) && _lv_offset=$(( _lv_offset - 1 ))
            ;;
          B)  # Down arrow
            local _lv_max=$(( _lv_total - _lv_content_h ))
            (( _lv_max < 0 )) && _lv_max=0
            if (( _lv_offset < _lv_max )); then
              _lv_offset=$(( _lv_offset + 1 ))
            fi
            # Re-enable follow if at bottom
            if (( _lv_offset >= _lv_max )); then
              _lv_follow="true"
            fi
            ;;
        esac
      fi
    elif [[ "$_k" == "k" ]]; then
      # Scroll up
      _lv_follow="false"
      (( _lv_offset > 0 )) && _lv_offset=$(( _lv_offset - 1 ))
    elif [[ "$_k" == "j" ]]; then
      # Scroll down
      local _lv_max=$(( _lv_total - _lv_content_h ))
      (( _lv_max < 0 )) && _lv_max=0
      if (( _lv_offset < _lv_max )); then
        _lv_offset=$(( _lv_offset + 1 ))
      fi
      if (( _lv_offset >= _lv_max )); then
        _lv_follow="true"
      fi
    elif [[ "$_k" == "g" ]]; then
      # Jump to top
      _lv_follow="false"
      _lv_offset=0
    elif [[ "$_k" == "G" ]]; then
      # Jump to bottom
      _lv_follow="true"
    fi

    # Redraw content + footer (header stays)
    _lv_draw_content
    _lv_draw_footer
  done

  tput cnorm 2>/dev/null  # show cursor
  tput rmcup
}

# Usage: stream_in_box "Title" "logfile" command arg1 arg2...
stream_in_box() {
  local title="$1"
  local log_file="$2"
  shift 2

  update_term_size
  local box_lines=4
  # Box width: total line = 2 (margin) + 1 (border) + box_w (inner) + 1 (border) = box_w + 4
  local box_w=$(( TERM_COLS - 4 ))
  (( box_w > 72 )) && box_w=72
  (( box_w < 10 )) && box_w=10
  local inner=$(( box_w - 2 ))

  # Bottom border
  local bottom
  bottom=$(printf '%*s' "$box_w" "" | sed 's/ /─/g')

  # Title in top border
  local tcut="$title"
  if (( ${#tcut} > inner - 4 )); then
    tcut="${tcut:0:$((inner - 7))}..."
  fi
  local pad_len=$(( box_w - ${#tcut} - 3 ))
  (( pad_len < 1 )) && pad_len=1
  local pad
  pad=$(printf '%*s' "$pad_len" "" | sed 's/ /─/g')

  # Ctrl+O hint line
  local _hint="Ctrl+O expand"
  local _hint_pad=$(( box_w - ${#_hint} + 1 ))
  (( _hint_pad < 0 )) && _hint_pad=0

  printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$tcut" "${RESET}${ACCENT}" "$pad" "${RESET}"
  local r=0
  while (( r < box_lines )); do
    local empty_pad
    empty_pad=$(printf '%*s' "$((inner - 1))" "")
    printf '  %b│%b %s %b│%b\n' "${ACCENT}" "${RESET}" "$empty_pad" "${ACCENT}" "${RESET}"
    r=$((r + 1))
  done
  printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"
  printf '  %b%*s%s%b\n' "${DIM}" "$_hint_pad" "" "$_hint" "${RESET}"

  # Run command in background
  "$@" >> "$log_file" 2>&1 &
  local cmd_pid=$!

  # Live-refresh (box_lines + bottom border + hint = box_lines + 2)
  while kill -0 "$cmd_pid" 2>/dev/null; do
    printf "\033[%dA" $((box_lines + 2))
    local tl_0="" tl_1="" tl_2="" tl_3=""
    local tl_i=0
    while IFS= read -r l; do
      l=$(printf '%s' "$l" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r')
      case $tl_i in
        0) tl_0="$l" ;; 1) tl_1="$l" ;; 2) tl_2="$l" ;; 3) tl_3="$l" ;;
      esac
      tl_i=$((tl_i + 1))
    done < <(tail -n "$box_lines" "$log_file" 2>/dev/null)

    r=0
    while (( r < box_lines )); do
      local line=""
      case $r in
        0) line="$tl_0" ;; 1) line="$tl_1" ;; 2) line="$tl_2" ;; 3) line="$tl_3" ;;
      esac
      local max_len=$(( inner - 1 ))
      if (( ${#line} > max_len )); then
        line="${line:0:$((max_len - 3))}..."
      fi
      local line_pad_len=$(( inner - 1 - ${#line} ))
      (( line_pad_len < 0 )) && line_pad_len=0
      local line_pad
      line_pad=$(printf '%*s' "$line_pad_len" "")
      printf '  %b│%b %s%s %b│%b\n' "${ACCENT}" "${RESET}" "$line" "$line_pad" "${ACCENT}" "${RESET}"
      r=$((r + 1))
    done
    printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"
    printf '  %b%*s%s%b\n' "${DIM}" "$_hint_pad" "" "$_hint" "${RESET}"
    local _key=""
    IFS= read -rsn1 -t 1 _key 2>/dev/null || true
    if [[ "$_key" == $'\x0f' ]]; then
      # Ctrl+O pressed — open log viewer (placeholder for Task 2)
      _log_viewer "$title" "$log_file" "$cmd_pid"
      # After viewer returns, redraw the collapsed box
      printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$tcut" "${RESET}${ACCENT}" "$pad" "${RESET}"
      r=0
      while (( r < box_lines )); do
        local empty_pad
        empty_pad=$(printf '%*s' "$((inner - 1))" "")
        printf '  %b│%b %s %b│%b\n' "${ACCENT}" "${RESET}" "$empty_pad" "${ACCENT}" "${RESET}"
        r=$((r + 1))
      done
      printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"
      printf '  %b%*s%s%b\n' "${DIM}" "$_hint_pad" "" "$_hint" "${RESET}"
    fi
  done

  wait "$cmd_pid"
  return $?
}
