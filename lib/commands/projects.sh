#!/usr/bin/env bash
# muster/lib/commands/projects.sh — List and manage registered projects

source "$MUSTER_ROOT/lib/core/registry.sh"
source "$MUSTER_ROOT/lib/tui/menu.sh"

cmd_projects() {
  local _json_mode=false
  local _prune=false
  local _remove_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        echo "Usage: muster projects [flags]"
        echo ""
        echo "List all muster projects registered on this machine."
        echo ""
        echo "Flags:"
        echo "  --json               Output as JSON"
        echo "  --prune              Remove stale entries (missing muster.json)"
        echo "  --remove <path>      Remove a project from registry (does not delete files)"
        echo "  -h, --help           Show this help"
        return 0
        ;;
      --json) _json_mode=true; shift ;;
      --prune) _prune=true; shift ;;
      --remove) _remove_path="${2:-}"; shift; shift 2>/dev/null || true ;;
      --*)
        err "Unknown flag: $1"
        echo "Run 'muster projects --help' for usage."
        return 1
        ;;
      *)
        err "Unknown argument: $1"
        return 1
        ;;
    esac
  done

  # Auth gate: JSON mode requires valid token
  if [[ "$_json_mode" == "true" ]]; then
    source "$MUSTER_ROOT/lib/core/auth.sh"
    _json_auth_gate "read" || return 1
  fi

  # Handle prune
  if [[ "$_prune" == "true" ]]; then
    local removed
    removed=$(_registry_prune)
    if [[ "$_json_mode" == "true" ]]; then
      printf '{"pruned":%s}\n' "${removed:-0}"
    else
      if [[ "${removed:-0}" -gt 0 ]]; then
        ok "Pruned ${removed} stale project(s)."
      else
        info "No stale projects found."
      fi
    fi
    return 0
  fi

  # Handle remove
  if [[ -n "$_remove_path" ]]; then
    if ! has_cmd jq; then
      err "jq is required"
      return 1
    fi
    _registry_ensure_file
    # Resolve to absolute path
    local _abs_remove
    if [[ "$_remove_path" == /* ]]; then
      _abs_remove="$_remove_path"
    elif [[ "$_remove_path" == "." ]]; then
      _abs_remove="$(pwd)"
    else
      _abs_remove="$(cd "$_remove_path" 2>/dev/null && pwd)" || _abs_remove="$_remove_path"
    fi
    # Check it exists in registry
    local _exists
    _exists=$(jq --arg p "$_abs_remove" '[.projects[] | select(.path == $p)] | length' "$MUSTER_PROJECTS_FILE" 2>/dev/null)
    if [[ "$_exists" == "0" || -z "$_exists" ]]; then
      err "Project not found in registry: ${_abs_remove}"
      return 1
    fi
    _registry_remove "$_abs_remove"
    ok "Removed from registry: ${_abs_remove}"
    printf '%b\n' "  ${DIM}(Project files are not deleted)${RESET}"
    return 0
  fi

  _registry_ensure_file

  if ! has_cmd jq; then
    err "jq is required for the projects command."
    return 1
  fi

  # JSON output
  if [[ "$_json_mode" == "true" ]]; then
    jq '.' "$MUSTER_PROJECTS_FILE"
    return 0
  fi

  # TUI output
  local count
  count=$(jq '.projects | length' "$MUSTER_PROJECTS_FILE" 2>/dev/null)
  [[ -z "$count" ]] && count=0

  echo ""
  printf '%b\n' "  ${BOLD}${ACCENT_BRIGHT}Registered Projects${RESET}"
  echo ""

  if (( count == 0 )); then
    printf '%b\n' "  ${DIM}No projects registered yet.${RESET}"
    printf '%b\n' "  ${DIM}Run 'muster setup' or any command in a project directory.${RESET}"
    echo ""
    return 0
  fi

  # Table header
  printf "  ${BOLD}%-20s  %-40s  %-5s  %-20s${RESET}\n" "NAME" "PATH" "SVCS" "LAST ACCESSED"
  printf "  ${DIM}%-20s  %-40s  %-5s  %-20s${RESET}\n" "--------------------" "----------------------------------------" "-----" "--------------------"

  local i=0
  while (( i < count )); do
    local name path svc_count last_accessed
    name=$(jq -r ".projects[$i].name" "$MUSTER_PROJECTS_FILE")
    path=$(jq -r ".projects[$i].path" "$MUSTER_PROJECTS_FILE")
    svc_count=$(jq -r ".projects[$i].service_count" "$MUSTER_PROJECTS_FILE")
    last_accessed=$(jq -r ".projects[$i].last_accessed" "$MUSTER_PROJECTS_FILE")

    # Truncate path if too long
    if (( ${#path} > 40 )); then
      path="...${path: -37}"
    fi

    # Format timestamp (remove T and Z)
    last_accessed="${last_accessed//T/ }"
    last_accessed="${last_accessed//Z/}"

    printf "  %-20s  %-40s  %-5s  ${DIM}%-20s${RESET}\n" "$name" "$path" "$svc_count" "$last_accessed"
    i=$(( i + 1 ))
  done

  echo ""
  printf '%b\n' "  ${DIM}${count} project(s) registered. Use --prune to remove stale entries.${RESET}"
  echo ""
}

# ── Interactive project manager (launched from settings) ──

_projects_manage() {
  _registry_ensure_file

  if ! has_cmd jq; then
    err "jq is required for project management."
    return 1
  fi

  while true; do
    clear
    echo ""
    printf '%b\n' "  ${BOLD}${ACCENT_BRIGHT}Projects${RESET}"
    echo ""

    local count
    count=$(jq '.projects | length' "$MUSTER_PROJECTS_FILE" 2>/dev/null)
    [[ -z "$count" ]] && count=0

    if (( count > 0 )); then
      local i=0
      while (( i < count )); do
        local _name _path _svcs
        _name=$(jq -r ".projects[$i].name" "$MUSTER_PROJECTS_FILE")
        _path=$(jq -r ".projects[$i].path" "$MUSTER_PROJECTS_FILE")
        _svcs=$(jq -r ".projects[$i].service_count" "$MUSTER_PROJECTS_FILE")

        local _display_path="${_path/#$HOME/~}"
        local _icon _color
        if [[ -d "$_path" ]]; then
          _icon="●"; _color="${GREEN}"
        else
          _icon="●"; _color="${RED}"
        fi

        printf '  %b%s%b %b%s%b %b(%s svc%s) %s%b\n' \
          "$_color" "$_icon" "${RESET}" \
          "${WHITE}" "$_name" "${RESET}" \
          "${DIM}" "$_svcs" "$([ "$_svcs" != "1" ] && echo "s")" "$_display_path" "${RESET}"

        i=$(( i + 1 ))
      done
    else
      printf '  %bNo projects registered yet.%b\n' "${DIM}" "${RESET}"
    fi
    echo ""

    local actions=()
    if (( count > 0 )); then
      actions[${#actions[@]}]="Open in file manager"
      actions[${#actions[@]}]="Remove project"
      actions[${#actions[@]}]="Prune stale entries"
    fi
    actions[${#actions[@]}]="Back"

    menu_select "Projects" "${actions[@]}"

    case "$MENU_RESULT" in
      "Open in file manager")
        _projects_open_picker
        ;;
      "Remove project")
        _projects_remove_picker
        ;;
      "Prune stale entries")
        echo ""
        local removed
        removed=$(_registry_prune)
        if [[ "${removed:-0}" -gt 0 ]]; then
          ok "Pruned ${removed} stale project(s)."
        else
          info "No stale projects found."
        fi
        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
        ;;
      "Back"|"__back__")
        return 0
        ;;
    esac
  done
}

_projects_remove_picker() {
  local count
  count=$(jq '.projects | length' "$MUSTER_PROJECTS_FILE" 2>/dev/null)
  [[ -z "$count" || "$count" == "0" ]] && return 0

  local options=()
  local paths=()
  local i=0
  while (( i < count )); do
    local _name _path
    _name=$(jq -r ".projects[$i].name" "$MUSTER_PROJECTS_FILE")
    _path=$(jq -r ".projects[$i].path" "$MUSTER_PROJECTS_FILE")
    options[${#options[@]}]="${_name} (${_path/#$HOME/~})"
    paths[${#paths[@]}]="$_path"
    i=$(( i + 1 ))
  done
  options[${#options[@]}]="Back"

  echo ""
  menu_select "Remove which project?" "${options[@]}"
  [[ "$MENU_RESULT" == "Back" || "$MENU_RESULT" == "__back__" ]] && return 0

  # Find the matching path
  local mi=0
  while (( mi < ${#paths[@]} )); do
    if [[ "$MENU_RESULT" == *"${paths[$mi]/#$HOME/~}"* ]]; then
      echo ""
      menu_select "Remove ${MENU_RESULT}?" "Remove" "Cancel"
      if [[ "$MENU_RESULT" == "Remove" ]]; then
        _registry_remove "${paths[$mi]}"
        echo ""
        ok "Project removed from registry"
        printf '%b\n' "  ${DIM}(Project files are not deleted)${RESET}"
        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
      fi
      return 0
    fi
    mi=$(( mi + 1 ))
  done
}

_projects_open_picker() {
  local count
  count=$(jq '.projects | length' "$MUSTER_PROJECTS_FILE" 2>/dev/null)
  [[ -z "$count" || "$count" == "0" ]] && return 0

  local options=()
  local paths=()
  local i=0
  while (( i < count )); do
    local _name _path
    _name=$(jq -r ".projects[$i].name" "$MUSTER_PROJECTS_FILE")
    _path=$(jq -r ".projects[$i].path" "$MUSTER_PROJECTS_FILE")
    options[${#options[@]}]="${_name} (${_path/#$HOME/~})"
    paths[${#paths[@]}]="$_path"
    i=$(( i + 1 ))
  done
  options[${#options[@]}]="Back"

  echo ""
  menu_select "Open which project?" "${options[@]}"
  [[ "$MENU_RESULT" == "Back" || "$MENU_RESULT" == "__back__" ]] && return 0

  # Find the matching path
  local mi=0
  while (( mi < ${#paths[@]} )); do
    if [[ "$MENU_RESULT" == *"${paths[$mi]/#$HOME/~}"* ]]; then
      local _target="${paths[$mi]}"
      echo ""
      if [[ ! -d "$_target" ]]; then
        err "Directory not found: ${_target}"
      elif [[ "$MUSTER_OS" == "macos" ]]; then
        open "$_target" 2>/dev/null && ok "Opened in Finder"
      elif [[ "$MUSTER_OS" == "linux" ]] && has_cmd xdg-open; then
        xdg-open "$_target" 2>/dev/null & ok "Opened file manager"
      else
        info "Project directory:"
        printf '%b\n' "  ${WHITE}${_target}${RESET}"
      fi
      echo ""
      printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
      IFS= read -rsn1 || true
      return 0
    fi
    mi=$(( mi + 1 ))
  done
}
