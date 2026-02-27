#!/usr/bin/env bash
# muster/lib/commands/history.sh — Deploy history tracking and display

# ── Event logger ──
# Appends a structured line to deploy-events.log
# Usage: _history_log_event "service" "action" "status"
#   action: deploy | rollback
#   status: ok | failed
_history_log_event() {
  local svc="$1" action="$2" status="$3"
  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"
  local log_dir="${project_dir}/.muster/logs"
  mkdir -p "$log_dir"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${ts}|${svc}|${action}|${status}" >> "${log_dir}/deploy-events.log"
}

# ── History display ──
cmd_history() {
  load_config

  local show_all=false
  local filter=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all|-a) show_all=true; shift ;;
      --*) shift ;;
      *)
        filter="$1"
        shift
        ;;
    esac
  done

  local project_dir
  project_dir="$(dirname "$CONFIG_FILE")"
  local log_file="${project_dir}/.muster/logs/deploy-events.log"

  if [[ ! -f "$log_file" ]]; then
    info "No deploy history found."
    return 0
  fi

  # Read events into arrays (bash 3.2 compatible)
  local timestamps=()
  local services=()
  local actions=()
  local statuses=()

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local ts="" svc="" action="" status=""

    if [[ "$line" == *"|"* ]]; then
      # New format: YYYY-MM-DD HH:MM:SS|service|action|status
      ts="${line%%|*}"
      local rest="${line#*|}"
      svc="${rest%%|*}"
      rest="${rest#*|}"
      action="${rest%%|*}"
      status="${rest#*|}"
    elif [[ "$line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\]\ ([A-Z]+)\ ([A-Z]+):\ (.+) ]]; then
      # Legacy format: [YYYY-MM-DD HH:MM:SS] ACTION STATUS: service
      ts="${BASH_REMATCH[1]}"
      action="${BASH_REMATCH[2]}"
      status="${BASH_REMATCH[3]}"
      svc="${BASH_REMATCH[4]}"
      # Normalize legacy values
      action=$(printf '%s' "$action" | tr '[:upper:]' '[:lower:]')
      status=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')
      # Skip START entries — only show results
      [[ "$action" == *"start"* ]] && continue
      [[ "$status" == "start" ]] && continue
    else
      continue
    fi

    # Apply service filter
    if [[ -n "$filter" && "$svc" != "$filter" ]]; then
      continue
    fi

    timestamps[${#timestamps[@]}]="$ts"
    services[${#services[@]}]="$svc"
    actions[${#actions[@]}]="$action"
    statuses[${#statuses[@]}]="$status"
  done < "$log_file"

  local count=${#timestamps[@]}

  if (( count == 0 )); then
    if [[ -n "$filter" ]]; then
      info "No history found for '${filter}'."
    else
      info "No deploy history found."
    fi
    return 0
  fi

  # Determine range to display
  local start=0
  if [[ "$show_all" == "false" && $count -gt 20 ]]; then
    start=$(( count - 20 ))
  fi

  local project
  project=$(config_get '.project')

  echo ""
  echo -e "  ${BOLD}${ACCENT_BRIGHT}Deploy History${RESET} ${DIM}${project}${RESET}"
  if [[ -n "$filter" ]]; then
    echo -e "  ${DIM}Filtered: ${filter}${RESET}"
  fi
  echo ""

  # Table header
  printf "  ${BOLD}%-20s  %-12s  %-10s  %-8s${RESET}\n" "TIMESTAMP" "SERVICE" "ACTION" "STATUS"
  printf "  ${DIM}%-20s  %-12s  %-10s  %-8s${RESET}\n" "--------------------" "------------" "----------" "--------"

  local i
  for (( i = start; i < count; i++ )); do
    local ts="${timestamps[$i]}"
    local svc="${services[$i]}"
    local action="${actions[$i]}"
    local st="${statuses[$i]}"

    local color="$RESET"
    if [[ "$st" == "ok" ]]; then
      color="$GREEN"
    elif [[ "$st" == "failed" ]]; then
      color="$RED"
    fi

    printf "  %-20s  %-12s  %-10s  ${color}%-8s${RESET}\n" "$ts" "$svc" "$action" "$st"
  done

  echo ""
  if [[ "$show_all" == "false" && $start -gt 0 ]]; then
    echo -e "  ${DIM}Showing last 20 of ${count} events. Use --all to see all.${RESET}"
    echo ""
  fi
}
