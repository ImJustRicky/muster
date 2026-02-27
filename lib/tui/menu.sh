#!/usr/bin/env bash
# muster/lib/tui/menu.sh — Arrow-key interactive menu

# Usage: menu_select RESULT_VAR "Title" "option1" "option2" "option3"
menu_select() {
  local -n _result=$1
  local title="$2"
  shift 2
  local options=("$@")
  local selected=0
  local count=${#options[@]}

  tput civis  # hide cursor

  # Print title
  echo -e "\n  ${BOLD}${title}${RESET}\n"

  # Print options
  for ((i=0; i<count; i++)); do
    if (( i == selected )); then
      echo -e "  ${CYAN}> ${options[$i]}${RESET}"
    else
      echo -e "    ${DIM}${options[$i]}${RESET}"
    fi
  done

  while true; do
    # Read keypress
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.1 key
        case "$key" in
          '[A') (( selected > 0 )) && (( selected-- )) ;;           # up
          '[B') (( selected < count - 1 )) && (( selected++ )) ;;   # down
        esac
        ;;
      '') break ;;  # enter
    esac

    # Redraw
    printf "\033[%dA" "$count"
    for ((i=0; i<count; i++)); do
      printf "\033[K"
      if (( i == selected )); then
        echo -e "  ${CYAN}> ${options[$i]}${RESET}"
      else
        echo -e "    ${DIM}${options[$i]}${RESET}"
      fi
    done
  done

  tput cnorm  # show cursor
  _result="${options[$selected]}"
}
