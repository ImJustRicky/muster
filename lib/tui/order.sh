#!/usr/bin/env bash
# muster/lib/tui/order.sh — Reorderable list (bash 3.2+)
# Arrow keys navigate, Enter grabs/drops, q confirms

ORDER_RESULT=()

order_select() {
  local title="$1"
  shift
  local items=("$@")
  local count=${#items[@]}
  local selected=0
  local grabbed=-1  # -1 = nothing grabbed

  tput civis

  local w=$(( TERM_COLS - 4 ))
  (( w > 50 )) && w=50
  (( w < 10 )) && w=10
  local inner=$(( w - 2 ))

  _ord_draw_header() {
    echo ""
    echo -e "  ${BOLD}${title}${RESET}"
    if (( grabbed >= 0 )); then
      echo -e "  ${DIM}↑/↓ move item  ⏎ drop  q done${RESET}"
    else
      echo -e "  ${DIM}↑/↓ navigate  ⏎ grab  q done${RESET}"
    fi
    echo ""
  }

  _ord_draw() {
    local border
    border=$(printf '%*s' "$w" "" | sed 's/ /─/g')
    printf '%b' "  ${ACCENT}┌${border}┐${RESET}\n"

    local i=0
    while (( i < count )); do
      local label="${items[$i]}"
      local num=$((i + 1))
      local prefix="  "

      if (( i == selected && grabbed >= 0 )); then
        # Currently grabbed and selected — highlight with accent
        prefix="${ACCENT_BRIGHT}*${RESET} "
      elif (( i == selected )); then
        prefix="${ACCENT}>${RESET} "
      fi

      local num_str="${num}."
      local content_len=$(( 4 + ${#num_str} + 1 + ${#label} ))
      local pad_len=$(( inner - content_len ))
      (( pad_len < 0 )) && pad_len=0
      local pad
      pad=$(printf '%*s' "$pad_len" "")

      if (( i == grabbed )); then
        printf '%b' "  ${ACCENT}│${RESET} ${prefix}${DIM}${num_str}${RESET} ${ACCENT_BRIGHT}${label}${RESET}${pad}${ACCENT}│${RESET}\n"
      else
        printf '%b' "  ${ACCENT}│${RESET} ${prefix}${DIM}${num_str}${RESET} ${label}${pad}${ACCENT}│${RESET}\n"
      fi
      i=$((i + 1))
    done

    border=$(printf '%*s' "$w" "" | sed 's/ /─/g')
    printf '%b' "  ${ACCENT}└${border}┘${RESET}\n"
  }

  local total_lines=$(( count + 2 ))

  _ord_clear() {
    local i=0
    while (( i < total_lines )); do
      tput cuu1
      i=$((i + 1))
    done
    tput ed
  }

  _ord_read_key() {
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

  _ord_swap() {
    local a="$1" b="$2"
    local tmp="${items[$a]}"
    items[$a]="${items[$b]}"
    items[$b]="$tmp"
  }

  _ord_draw_header
  _ord_draw

  while true; do
    _ord_read_key

    if [[ "$_MUSTER_INPUT_DIRTY" == "true" ]]; then
      _MUSTER_INPUT_DIRTY="false"
      _ord_draw_header
      _ord_draw
      continue
    fi

    case "$REPLY" in
      $'\x1b[A')
        if (( grabbed >= 0 && selected > 0 )); then
          # Move grabbed item up
          _ord_swap "$selected" "$((selected - 1))"
          grabbed=$((selected - 1))
          selected=$((selected - 1))
        elif (( grabbed < 0 && selected > 0 )); then
          selected=$((selected - 1))
        fi
        ;;
      $'\x1b[B')
        if (( grabbed >= 0 && selected < count - 1 )); then
          # Move grabbed item down
          _ord_swap "$selected" "$((selected + 1))"
          grabbed=$((selected + 1))
          selected=$((selected + 1))
        elif (( grabbed < 0 && selected < count - 1 )); then
          selected=$((selected + 1))
        fi
        ;;
      'q'|'Q')
        _ord_clear
        tput cnorm
        # Show final order
        local i=0
        while (( i < count )); do
          echo -e "  ${GREEN}${i+1}.${RESET} ${items[$i]}"
          i=$((i + 1))
        done
        ORDER_RESULT=("${items[@]}")
        return 0
        ;;
      '')
        # Enter — toggle grab
        if (( grabbed >= 0 )); then
          grabbed=-1
        else
          grabbed=$selected
        fi
        ;;
      *)
        continue
        ;;
    esac

    _ord_clear
    _ord_draw
  done
}
