#!/usr/bin/env bash
# muster/lib/tui/checklist.sh — Toggle checklist (bash 3.2+, macOS compatible)
# Uses tput cuu1 + tput ed for reliable in-place redraw

CHECKLIST_RESULT=""

checklist_select() {
  local title="$1"
  shift
  local items=("$@")
  local count=${#items[@]}
  local selected=0
  local checked=()

  local i=0
  while (( i < count )); do checked[$i]=1; i=$((i + 1)); done

  tput civis

  echo ""
  echo -e "  ${BOLD}${title}${RESET}"
  echo -e "  ${DIM}↑/↓ navigate  ␣ toggle  ⏎ confirm${RESET}"
  echo ""

  local w=$(( TERM_COLS - 6 ))
  (( w > 50 )) && w=50
  (( w < 30 )) && w=30
  local inner=$(( w - 2 ))
  local border
  border=$(printf '─%.0s' $(seq 1 "$w"))

  # total drawn lines = top border + items + bottom border
  local total_lines=$((count + 2))

  _cl_draw() {
    echo -e "  ${ACCENT}┌${border}┐${RESET}"
    local i=0
    while (( i < count )); do
      local mark="✓"
      local mcolor="${GREEN}"
      if (( checked[i] == 0 )); then
        mark=" "
        mcolor="${DIM}"
      fi
      if (( i == selected )); then
        printf "  ${ACCENT}│ > [${mcolor}${mark}${RESET}${ACCENT}]${RESET} %-$((inner - 9))s ${ACCENT}│${RESET}\n" "${items[$i]}"
      else
        printf "  ${ACCENT}│${RESET}   [${mcolor}${mark}${RESET}] %-$((inner - 9))s ${ACCENT}│${RESET}\n" "${items[$i]}"
      fi
      i=$((i + 1))
    done
    echo -e "  ${ACCENT}└${border}┘${RESET}"
  }

  _cl_clear() {
    local i=0
    while (( i < total_lines )); do
      tput cuu1
      i=$((i + 1))
    done
    tput ed
  }

  _cl_read_key() {
    local key
    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      local seq1 seq2
      IFS= read -rsn1 -t 1 seq1
      IFS= read -rsn1 -t 1 seq2
      key="${key}${seq1}${seq2}"
    fi
    REPLY="$key"
  }

  _cl_draw

  while true; do
    _cl_read_key

    case "$REPLY" in
      $'\x1b[A')
        (( selected > 0 )) && selected=$((selected - 1))
        ;;
      $'\x1b[B')
        (( selected < count - 1 )) && selected=$((selected + 1))
        ;;
      ' ')
        if (( checked[selected] == 1 )); then
          checked[$selected]=0
        else
          checked[$selected]=1
        fi
        ;;
      '')
        # Enter — collapse to summary
        _cl_clear
        i=0
        while (( i < count )); do
          if (( checked[i] == 1 )); then
            echo -e "  ${GREEN}*${RESET} ${items[$i]}"
          fi
          i=$((i + 1))
        done

        tput cnorm

        CHECKLIST_RESULT=""
        i=0
        while (( i < count )); do
          if (( checked[i] == 1 )); then
            if [[ -n "$CHECKLIST_RESULT" ]]; then
              CHECKLIST_RESULT="${CHECKLIST_RESULT}"$'\n'"${items[$i]}"
            else
              CHECKLIST_RESULT="${items[$i]}"
            fi
          fi
          i=$((i + 1))
        done
        return 0
        ;;
      *)
        continue
        ;;
    esac

    _cl_clear
    _cl_draw
  done
}
