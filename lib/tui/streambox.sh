#!/usr/bin/env bash
# muster/lib/tui/streambox.sh — Live-scrolling log box

# Usage: stream_in_box "Title" "logfile" command arg1 arg2...
stream_in_box() {
  local title="$1"
  local log_file="$2"
  shift 2

  update_term_size
  local box_lines=4
  local box_w=$(( TERM_COLS - 6 ))
  (( box_w > 72 )) && box_w=72
  (( box_w < 30 )) && box_w=30
  local inner=$(( box_w - 2 ))

  # Bottom border
  local bottom
  bottom=$(printf '─%.0s' $(seq 1 "$box_w"))

  # Title in top border
  local tcut="$title"
  [[ ${#tcut} -gt $((inner - 4)) ]] && tcut="${tcut:0:$((inner - 7))}..."
  local pad_len=$(( box_w - ${#tcut} - 3 ))
  (( pad_len < 1 )) && pad_len=1
  local pad
  pad=$(printf '─%.0s' $(seq 1 "$pad_len"))

  echo -e "  ${CYAN}┌─${BOLD}${tcut}${RESET}${CYAN}─${pad}┐${RESET}"
  for ((r=0; r<box_lines; r++)); do
    printf "  ${CYAN}│${RESET} %-$((inner - 1))s ${CYAN}│${RESET}\n" ""
  done
  echo -e "  ${CYAN}└${bottom}┘${RESET}"

  # Run command in background
  "$@" >> "$log_file" 2>&1 &
  local cmd_pid=$!

  # Live-refresh
  while kill -0 "$cmd_pid" 2>/dev/null; do
    printf "\033[%dA" $((box_lines + 1))
    local -a tl=()
    while IFS= read -r l; do
      l=$(printf '%s' "$l" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r')
      tl+=("$l")
    done < <(tail -n "$box_lines" "$log_file" 2>/dev/null)

    for ((r=0; r<box_lines; r++)); do
      local line="${tl[$r]:-}"
      [[ ${#line} -gt $((inner - 1)) ]] && line="${line:0:$((inner - 4))}..."
      printf "  ${CYAN}│${RESET} %-$((inner - 1))s ${CYAN}│${RESET}\n" "$line"
    done
    echo -e "  ${CYAN}└${bottom}┘${RESET}"
    sleep 0.3
  done

  wait "$cmd_pid"
  return $?
}
