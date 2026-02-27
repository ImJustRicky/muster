#!/usr/bin/env bash
# muster/lib/skills/manager.sh — Skill management

SKILLS_DIR="${HOME}/.muster/skills"

cmd_skill() {
  local action="${1:-list}"
  shift 2>/dev/null || true

  case "$action" in
    add|install)
      skill_add "$@"
      ;;
    remove|uninstall)
      skill_remove "$@"
      ;;
    list|ls)
      skill_list
      ;;
    run)
      skill_run "$@"
      ;;
    *)
      err "Unknown skill command: ${action}"
      echo "Usage: muster skill [add|remove|list|run]"
      exit 1
      ;;
  esac
}

skill_add() {
  local source="${1:-}"

  if [[ -z "$source" ]]; then
    err "Usage: muster skill add <git-url-or-path>"
    exit 1
  fi

  mkdir -p "$SKILLS_DIR"

  # Clone from git
  if [[ "$source" =~ ^https?:// || "$source" =~ ^git@ ]]; then
    local skill_name
    skill_name=$(basename "$source" .git)
    skill_name="${skill_name#muster-skill-}"  # strip common prefix

    if [[ -d "${SKILLS_DIR}/${skill_name}" ]]; then
      warn "Skill '${skill_name}' already installed. Updating..."
      (cd "${SKILLS_DIR}/${skill_name}" && git pull --quiet)
    else
      start_spinner "Installing skill: ${skill_name}"
      git clone --quiet "$source" "${SKILLS_DIR}/${skill_name}" 2>/dev/null
      stop_spinner
    fi

    # Validate
    if [[ ! -f "${SKILLS_DIR}/${skill_name}/skill.json" ]]; then
      err "Invalid skill: missing skill.json"
      rm -rf "${SKILLS_DIR}/${skill_name}"
      exit 1
    fi

    ok "Skill '${skill_name}' installed"
  else
    # Local path
    local skill_name
    skill_name=$(basename "$source")
    cp -r "$source" "${SKILLS_DIR}/${skill_name}"
    ok "Skill '${skill_name}' installed from local path"
  fi
}

skill_remove() {
  local name="${1:-}"

  if [[ -z "$name" ]]; then
    err "Usage: muster skill remove <name>"
    exit 1
  fi

  if [[ -d "${SKILLS_DIR}/${name}" ]]; then
    rm -rf "${SKILLS_DIR}/${name}"
    ok "Skill '${name}' removed"
  else
    err "Skill '${name}' not found"
    exit 1
  fi
}

skill_list() {
  echo ""
  echo -e "  ${BOLD}Installed Skills${RESET}"
  echo ""

  if [[ ! -d "$SKILLS_DIR" ]] || [[ -z "$(ls -A "$SKILLS_DIR" 2>/dev/null)" ]]; then
    info "No skills installed"
    echo -e "  ${DIM}Run 'muster skill add <git-url>' to install one${RESET}"
    echo ""
    return
  fi

  for skill_dir in "${SKILLS_DIR}"/*/; do
    [[ ! -d "$skill_dir" ]] && continue
    local name
    name=$(basename "$skill_dir")
    local desc=""

    if [[ -f "${skill_dir}/skill.json" ]]; then
      if has_cmd jq; then
        desc=$(jq -r '.description // ""' "${skill_dir}/skill.json")
      fi
    fi

    echo -e "  ${ACCENT}*${RESET} ${BOLD}${name}${RESET}  ${DIM}${desc}${RESET}"
  done
  echo ""
}

skill_run() {
  local name="${1:-}"
  shift 2>/dev/null || true

  if [[ -z "$name" ]]; then
    err "Usage: muster skill run <name> [args...]"
    exit 1
  fi

  local run_script="${SKILLS_DIR}/${name}/run.sh"

  if [[ ! -x "$run_script" ]]; then
    err "Skill '${name}' not found or not executable"
    exit 1
  fi

  "$run_script" "$@"
}
