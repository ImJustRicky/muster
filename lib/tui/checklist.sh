#!/usr/bin/env bash
# muster/lib/tui/checklist.sh — Toggle checklist for setup wizard

# Usage: checklist_select RESULT_ARRAY "Title" "item1" "item2" "item3"
# Returns space-separated indices of selected items in RESULT_ARRAY
checklist_select() {
  local -n _result=$1
  local title="$2"
  shift 2
  local items=("$@")
  local count=${#items[@]}
  local selected=0
  local -a checked=()

  # Default all checked
  for ((i=0; i<count; i++)); do checked[$i]=1; done

  tput civis

  echo -e "\n  ${BOLD}${title}${RESET}"
  echo -e "  ${DIM}↑/↓ navigate  ␣ toggle  ⏎ confirm${RESET}\n"

  # Draw border top
  local w=$(( TERM_COLS - 6 ))
  (( w > 50 )) && w=50
  (( w < 30 )) && w=30
  local inner=$(( w - 2 ))
  local border
  border=$(printf '─%.0s' $(seq 1 "$w"))

  echo -e "  ${CYAN}┌${border}┐${RESET}"
  for ((i=0; i<count; i++)); do
    local mark="✓"
    local color="$GREEN"
    if (( checked[i] == 0 )); then
      mark=" "
      color="$DIM"
    fi
    local prefix="   "
    (( i == selected )) && prefix="${CYAN}>"
    printf "  ${prefix} [${color}${mark}${RESET}] %-$((inner - 8))s ${CYAN}│${RESET}\n" "${items[$i]}"
  done
  echo -e "  ${CYAN}└${border}┘${RESET}"

  while true; do
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.1 key
        case "$key" in
          '[A') (( selected > 0 )) && (( selected-- )) ;;
          '[B') (( selected < count - 1 )) && (( selected++ )) ;;
        esac
        ;;
      ' ')
        # Toggle
        if (( checked[selected] == 1 )); then
          checked[$selected]=0
        else
          checked[$selected]=1
        fi
        ;;
      '') break ;;
    esac

    # Redraw items
    printf "\033[%dA" $(( count + 1 ))
    for ((i=0; i<count; i++)); do
      printf "\033[K"
      local mark="✓"
      local color="$GREEN"
      if (( checked[i] == 0 )); then
        mark=" "
        color="$DIM"
      fi
      local prefix="   "
      (( i == selected )) && prefix="${CYAN}>"
      printf "  ${prefix} [${color}${mark}${RESET}] %-$((inner - 8))s ${CYAN}│${RESET}\n" "${items[$i]}"
    done
    echo -e "  ${CYAN}└${border}┘${RESET}"
  done

  tput cnorm

  # Build result
  _result=()
  for ((i=0; i<count; i++)); do
    if (( checked[i] == 1 )); then
      _result+=("${items[$i]}")
    fi
  done
}
