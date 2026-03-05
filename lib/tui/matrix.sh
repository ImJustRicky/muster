#!/usr/bin/env bash
# muster/lib/tui/matrix.sh — Matrix-style digital rain splash

_matrix_splash() {
  # Skip animation entirely in minimal mode
  if [[ "${MUSTER_MINIMAL:-false}" == "true" ]]; then
    return 0
  fi

  local cols=${TERM_COLS:-$(tput cols 2>/dev/null || echo 80)}
  local rows=${TERM_ROWS:-$(tput lines 2>/dev/null || echo 24)}

  # Animation area: half the terminal, clamped to 6-20 rows
  local rain_h=$(( rows / 2 ))
  if [[ $rain_h -lt 6 ]]; then rain_h=6; fi
  if [[ $rain_h -gt 20 ]]; then rain_h=20; fi

  local charset="0123456789abcdefghijklmnopqrstuvwxyz|/-\\"
  local charset_len=${#charset}

  # Number of rain drops (~1/3 of terminal width)
  local num_drops=$(( cols / 3 ))
  if [[ $num_drops -lt 4 ]]; then num_drops=4; fi

  # Trail length (characters visible behind the head)
  local trail=4

  # Initialize drop arrays — column, row (head position), speed
  local _dc _dr _ds
  _dc=()
  _dr=()
  _ds=()
  local i=0
  while [[ $i -lt $num_drops ]]; do
    _dc[${#_dc[@]}]=$(( RANDOM % cols ))
    _dr[${#_dr[@]}]=$(( -(RANDOM % (rain_h + trail)) ))
    _ds[${#_ds[@]}]=$(( (RANDOM % 2) + 1 ))
    i=$(( i + 1 ))
  done

  # Cache cursor-up sequence (avoid subshell per call in hot loop)
  local cuu1
  cuu1=$(tput cuu1 2>/dev/null || printf '\033[A')

  # Hide cursor, save trap state
  tput civis 2>/dev/null
  local _mprev_int
  _mprev_int=$(trap -p INT 2>/dev/null || true)
  trap 'tput cnorm 2>/dev/null; if [[ -n "$_mprev_int" ]]; then eval "$_mprev_int"; else trap - INT 2>/dev/null || true; fi; return 130' INT

  # Reserve animation area with blank lines
  i=0
  while [[ $i -lt $rain_h ]]; do
    printf '\n'
    i=$(( i + 1 ))
  done

  # Render frames — 15 frames x 0.1s = ~1.5s
  local frame=0
  while [[ $frame -lt 15 ]]; do
    # Build output buffer for this frame
    local buf=""

    # Move cursor to top of animation area
    i=0
    while [[ $i -lt $rain_h ]]; do
      buf="${buf}${cuu1}"
      i=$(( i + 1 ))
    done

    # Draw each row
    local row=0
    while [[ $row -lt $rain_h ]]; do
      # Clear the line, then position characters
      buf="${buf}\r\033[K"

      # Check each drop against this row
      local di=0
      while [[ $di -lt $num_drops ]]; do
        local dist=$(( row - _dr[di] ))
        if [[ $dist -ge 0 ]] && [[ $dist -le $trail ]]; then
          local ci=$(( RANDOM % charset_len ))
          local ch="${charset:$ci:1}"
          local cpos="\033[$(( _dc[di] + 1 ))G"
          if [[ $dist -eq 0 ]]; then
            buf="${buf}${cpos}${GREEN}${BOLD}${ch}${RESET}"
          elif [[ $dist -le 2 ]]; then
            buf="${buf}${cpos}${GREEN}${ch}${RESET}"
          else
            buf="${buf}${cpos}${DIM}${GREEN}${ch}${RESET}"
          fi
        fi
        di=$(( di + 1 ))
      done

      buf="${buf}\n"
      row=$(( row + 1 ))
    done

    # Flush the entire frame at once
    printf '%b' "$buf"

    # Advance drop positions
    i=0
    while [[ $i -lt $num_drops ]]; do
      _dr[$i]=$(( _dr[i] + _ds[i] ))
      # Reset drops that have fully fallen off screen
      if [[ ${_dr[$i]} -gt $(( rain_h + trail + 2 )) ]]; then
        _dr[$i]=$(( -(RANDOM % (rain_h / 2 + trail)) ))
      fi
      i=$(( i + 1 ))
    done

    sleep 0.1
    frame=$(( frame + 1 ))
  done

  # Clear animation area
  i=0
  while [[ $i -lt $rain_h ]]; do
    printf '%s' "$cuu1"
    i=$(( i + 1 ))
  done
  tput ed 2>/dev/null

  # Restore cursor and traps
  tput cnorm 2>/dev/null
  if [[ -n "$_mprev_int" ]]; then
    eval "$_mprev_int"
  else
    trap - INT 2>/dev/null || true
  fi
}
