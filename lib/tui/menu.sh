#!/usr/bin/env bash
# muster/lib/tui/menu.sh — Arrow-key interactive menu (bash 3.2+, macOS compatible)
# Uses tput cuu1 + tput ed for reliable in-place redraw (no tput sc/rc)

MENU_RESULT=""

menu_select() {
  local title="$1"
  shift
  local options=("$@")
  local selected=0
  local count=${#options[@]}

  tput civis

  echo ""
  echo -e "  ${BOLD}${title}${RESET}"
  echo ""

  _menu_draw() {
    local i=0
    while (( i < count )); do
      if (( i == selected )); then
        echo -e "  ${ACCENT}> ${options[$i]}${RESET}"
      else
        echo -e "    ${DIM}${options[$i]}${RESET}"
      fi
      i=$((i + 1))
    done
  }

  _menu_clear() {
    local i=0
    while (( i < count )); do
      tput cuu1
      i=$((i + 1))
    done
    tput ed
  }

  _menu_read_key() {
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

  _menu_draw

  while true; do
    _menu_read_key

    case "$REPLY" in
      $'\x1b[A')
        (( selected > 0 )) && selected=$((selected - 1))
        ;;
      $'\x1b[B')
        (( selected < count - 1 )) && selected=$((selected + 1))
        ;;
      '')
        # Enter — collapse to selected choice
        _menu_clear
        echo -e "  ${GREEN}*${RESET} ${options[$selected]}"
        tput cnorm
        MENU_RESULT="${options[$selected]}"
        return 0
        ;;
      *)
        # Ignore other keys, no redraw
        continue
        ;;
    esac

    _menu_clear
    _menu_draw
  done
}
