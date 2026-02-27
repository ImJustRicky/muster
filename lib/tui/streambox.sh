#!/usr/bin/env bash
# muster/lib/tui/streambox.sh — Live-scrolling log box

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

  printf '  %b┌─%b%s%b─%s┐%b\n' "${ACCENT}" "${BOLD}" "$tcut" "${RESET}${ACCENT}" "$pad" "${RESET}"
  local r=0
  while (( r < box_lines )); do
    local empty_pad
    empty_pad=$(printf '%*s' "$((inner - 1))" "")
    printf '  %b│%b %s %b│%b\n' "${ACCENT}" "${RESET}" "$empty_pad" "${ACCENT}" "${RESET}"
    r=$((r + 1))
  done
  printf '  %b└%s┘%b\n' "${ACCENT}" "$bottom" "${RESET}"

  # Run command in background
  "$@" >> "$log_file" 2>&1 &
  local cmd_pid=$!

  # Live-refresh
  while kill -0 "$cmd_pid" 2>/dev/null; do
    printf "\033[%dA" $((box_lines + 1))
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
    sleep 0.3
  done

  wait "$cmd_pid"
  return $?
}
