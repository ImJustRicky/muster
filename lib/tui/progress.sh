#!/usr/bin/env bash
# muster/lib/tui/progress.sh — Progress bars

progress_bar() {
  local current=$1
  local total=$2
  local label="${3:-}"
  local bar_width=$(( TERM_COLS - 20 ))
  (( bar_width > 50 )) && bar_width=50
  (( bar_width < 10 )) && bar_width=10

  local pct=0
  (( total > 0 )) && pct=$(( current * 100 / total ))
  local filled=$(( pct * bar_width / 100 ))
  local empty=$(( bar_width - filled ))

  local bar_filled=""
  local bar_empty=""
  for ((i=0; i<filled; i++)); do bar_filled+="#"; done
  for ((i=0; i<empty; i++)); do bar_empty+="-"; done

  local color="$RED"
  (( pct > 33 )) && color="$YELLOW"
  (( pct > 66 )) && color="$GREEN"

  printf "\r  ${color}${bar_filled}${GRAY}${bar_empty}${RESET} ${WHITE}%3d%%${RESET} ${DIM}%s${RESET}" "$pct" "$label"
}
