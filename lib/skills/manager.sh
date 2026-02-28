#!/usr/bin/env bash
# muster/lib/skills/manager.sh — Skill management

SKILLS_DIR="${HOME}/.muster/skills"

cmd_skill() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: muster skill <command> [args]"
      echo ""
      echo "Manage addon skills."
      echo ""
      echo "Commands:"
      echo "  add <url>            Install a skill from a git URL or local path"
      echo "  create <name>        Scaffold a new skill"
      echo "  remove <name>        Remove an installed skill"
      echo "  list                 List installed skills"
      echo "  run <name>           Run a skill manually"
      echo "  marketplace [query]  Browse and install skills from the official registry"
      return 0
      ;;
  esac

  local action="${1:-list}"
  shift 2>/dev/null || true

  case "$action" in
    add|install)
      skill_add "$@"
      ;;
    create|new)
      skill_create "$@"
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
    marketplace|browse|search)
      skill_marketplace "$@"
      ;;
    *)
      err "Unknown skill command: ${action}"
      echo "Usage: muster skill [add|create|remove|list|run|marketplace]"
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
    skill_name="${skill_name#muster-skill-}"  # strip common prefix

    # Read name from skill.json if available
    local source_dir="$source"
    if [[ -f "${source_dir}/skill.json" ]]; then
      local json_name=""
      if has_cmd jq; then
        json_name=$(jq -r '.name // ""' "${source_dir}/skill.json")
      elif has_cmd python3; then
        json_name=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('name',''))" "${source_dir}/skill.json" 2>/dev/null)
      fi
      if [[ -n "$json_name" ]]; then
        skill_name="$json_name"
      fi
    fi

    if [[ -d "${SKILLS_DIR}/${skill_name}" ]]; then
      warn "Skill '${skill_name}' already installed. Updating..."
      rm -rf "${SKILLS_DIR}/${skill_name}"
    fi

    cp -r "$source" "${SKILLS_DIR}/${skill_name}"
    ok "Skill '${skill_name}' installed from local path"
  fi
}

skill_create() {
  local name="${1:-}"

  if [[ -z "$name" ]]; then
    err "Usage: muster skill create <name>"
    exit 1
  fi

  # Sanitize: lowercase, hyphens for spaces/underscores
  name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[_ ]/-/g')

  mkdir -p "$SKILLS_DIR"

  if [[ -d "${SKILLS_DIR}/${name}" ]]; then
    err "Skill '${name}' already exists at ${SKILLS_DIR}/${name}"
    return 1
  fi

  mkdir -p "${SKILLS_DIR}/${name}"

  # Write skill.json
  cat > "${SKILLS_DIR}/${name}/skill.json" << SKILLJSON
{
  "name": "${name}",
  "version": "1.0.0",
  "description": "TODO: describe your skill",
  "author": "",
  "hooks": [],
  "requires": []
}
SKILLJSON

  # Write run.sh stub
  cat > "${SKILLS_DIR}/${name}/run.sh" << 'RUNSH'
#!/usr/bin/env bash
# run.sh — skill entry point
#
# Environment variables available:
#   MUSTER_PROJECT_DIR   — path to the project root
#   MUSTER_CONFIG_FILE   — path to deploy.json
#   MUSTER_SERVICE       — current service name (if run per-service)
#   MUSTER_HOOK          — which hook triggered this (e.g. "post-deploy")

echo "Hello from skill!"

# Your logic here
RUNSH
  chmod +x "${SKILLS_DIR}/${name}/run.sh"

  ok "Skill '${name}' created"
  echo ""
  echo -e "  ${DIM}${SKILLS_DIR}/${name}/${RESET}"
  echo -e "  ${DIM}  skill.json  — edit name, description, hooks${RESET}"
  echo -e "  ${DIM}  run.sh      — add your logic${RESET}"
  echo ""
  echo -e "  ${DIM}Hooks: add \"pre-deploy\", \"post-deploy\", \"pre-rollback\",${RESET}"
  echo -e "  ${DIM}       \"post-rollback\" to the hooks array in skill.json${RESET}"
  echo ""
  echo -e "  ${DIM}Test: muster skill run ${name}${RESET}"
  echo ""
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

  # Export context env vars
  if [[ -n "${CONFIG_FILE:-}" ]]; then
    export MUSTER_PROJECT_DIR="$(dirname "$CONFIG_FILE")"
    export MUSTER_CONFIG_FILE="$CONFIG_FILE"
  fi

  _load_env_file

  "$run_script" "$@"
  local rc=$?

  _unload_env_file
  unset MUSTER_PROJECT_DIR MUSTER_CONFIG_FILE 2>/dev/null
  return $rc
}

# Run all skills that declare a given hook
# Usage: run_skill_hooks "post-deploy" "api"
# Non-fatal: warns on failure, never blocks deploy/rollback
run_skill_hooks() {
  local hook_name="${1:-}" svc_name="${2:-}"

  # Guard: no skills dir
  [[ ! -d "$SKILLS_DIR" ]] && return 0

  local skill_dir
  for skill_dir in "${SKILLS_DIR}"/*/; do
    [[ ! -d "$skill_dir" ]] && continue
    [[ ! -f "${skill_dir}/skill.json" ]] && continue
    [[ ! -x "${skill_dir}/run.sh" ]] && continue

    # Check if this skill declares the hook
    local has_hook="false"
    if has_cmd jq; then
      local match=""
      match=$(jq -r --arg h "$hook_name" '.hooks // [] | map(select(. == $h)) | length' "${skill_dir}/skill.json" 2>/dev/null)
      [[ "$match" != "0" && -n "$match" ]] && has_hook="true"
    elif has_cmd python3; then
      local match=""
      match=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('yes' if sys.argv[2] in d.get('hooks',[]) else 'no')
" "${skill_dir}/skill.json" "$hook_name" 2>/dev/null)
      [[ "$match" == "yes" ]] && has_hook="true"
    fi

    if [[ "$has_hook" == "true" ]]; then
      local skill_name
      skill_name=$(basename "$skill_dir")

      # Export context
      if [[ -n "${CONFIG_FILE:-}" ]]; then
        export MUSTER_PROJECT_DIR="$(dirname "$CONFIG_FILE")"
        export MUSTER_CONFIG_FILE="$CONFIG_FILE"
      fi
      export MUSTER_SERVICE="$svc_name"
      export MUSTER_HOOK="$hook_name"

      "${skill_dir}/run.sh" 2>&1 || {
        warn "Skill '${skill_name}' failed on ${hook_name} (non-fatal)"
      }

      unset MUSTER_PROJECT_DIR MUSTER_CONFIG_FILE MUSTER_SERVICE MUSTER_HOOK 2>/dev/null
    fi
  done
}

# ---------------------------------------------------------------------------
# Skill Marketplace — browse and install from the official registry
# ---------------------------------------------------------------------------

SKILL_REGISTRY_URL="https://raw.githubusercontent.com/ImJustRicky/muster-skills/main/registry.json"

skill_marketplace() {
  source "$MUSTER_ROOT/lib/tui/checklist.sh"
  source "$MUSTER_ROOT/lib/tui/spinner.sh"

  if ! has_cmd jq; then
    err "The marketplace requires jq. Install it first: https://jqlang.github.io/jq/download/"
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp)

  start_spinner "Fetching skill registry..."
  if ! curl -fsSL "$SKILL_REGISTRY_URL" -o "$tmp_file" 2>/dev/null; then
    stop_spinner
    err "Failed to fetch skill registry"
    rm -f "$tmp_file"
    return 1
  fi
  stop_spinner

  local query="${1:-}"

  if [[ -z "$query" && -t 0 ]]; then
    echo ""
    printf '%b\n' "  ${BOLD}Skill Marketplace${RESET}"
    echo ""
    printf '%b' "  ${DIM}Search (or press enter to browse all):${RESET} "
    read -r query
  fi

  if [[ -n "$query" ]]; then
    _marketplace_search "$tmp_file" "$query"
  else
    _marketplace_browse "$tmp_file"
  fi

  rm -f "$tmp_file"
}

_marketplace_search() {
  local registry="$1"
  local query="$2"

  local matches
  matches=$(jq -r --arg q "$query" \
    '[.skills[] | select((.name | ascii_downcase | contains($q | ascii_downcase)) or (.description | ascii_downcase | contains($q | ascii_downcase)))]' \
    "$registry")

  local match_count
  match_count=$(printf '%s' "$matches" | jq 'length')

  if [[ "$match_count" -eq 0 ]]; then
    echo ""
    warn "No skills matching '${query}'"
    echo ""
    return 0
  fi

  echo ""
  printf '%b\n' "  ${BOLD}Marketplace results for '${query}'${RESET}"
  echo ""

  local i=0
  local names=()
  while [[ "$i" -lt "$match_count" ]]; do
    local name desc version installed_tag=""
    name=$(printf '%s' "$matches" | jq -r ".[$i].name")
    desc=$(printf '%s' "$matches" | jq -r ".[$i].description // \"\"")
    version=$(printf '%s' "$matches" | jq -r ".[$i].version // \"0.0.0\"")

    if [[ -d "${SKILLS_DIR}/${name}" ]]; then
      installed_tag=" ${GREEN}(installed)${RESET}"
    fi

    printf '%b\n' "  ${BOLD}${name}${RESET}${installed_tag}  ${DIM}${desc}${RESET}  ${ACCENT}v${version}${RESET}"
    names[${#names[@]}]="$name"
    i=$((i + 1))
  done
  echo ""

  if [[ "$match_count" -eq 1 ]]; then
    local single_name="${names[0]}"
    if [[ -d "${SKILLS_DIR}/${single_name}" ]]; then
      info "Skill '${single_name}' is already installed"
      return 0
    fi
    printf '%b' "  Install ${BOLD}${single_name}${RESET}? (y/n) "
    local answer=""
    read -rsn1 answer
    echo ""
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
      skill_marketplace_install "$single_name"
    fi
  else
    # Build checklist items with descriptions
    local items=()
    i=0
    while [[ "$i" -lt "$match_count" ]]; do
      local item_name
      item_name=$(printf '%s' "$matches" | jq -r ".[$i].name")
      items[${#items[@]}]="$item_name"
      i=$((i + 1))
    done

    checklist_select --none "Select skills to install" "${items[@]}"

    if [[ -n "$CHECKLIST_RESULT" ]]; then
      local IFS=$'\n'
      local selected
      for selected in $CHECKLIST_RESULT; do
        if [[ -d "${SKILLS_DIR}/${selected}" ]]; then
          info "Skill '${selected}' is already installed, skipping"
        else
          skill_marketplace_install "$selected"
        fi
      done
    fi
  fi
}

_marketplace_browse() {
  local registry="$1"

  local skill_count
  skill_count=$(jq '.skills | length' "$registry")

  if [[ "$skill_count" -eq 0 ]]; then
    echo ""
    info "No skills available in the registry"
    echo ""
    return 0
  fi

  echo ""
  printf '%b\n' "  ${BOLD}Skill Marketplace${RESET}"
  echo ""

  local i=0
  local items=()
  while [[ "$i" -lt "$skill_count" ]]; do
    local name desc version installed_tag=""
    name=$(jq -r ".skills[$i].name" "$registry")
    desc=$(jq -r ".skills[$i].description // \"\"" "$registry")
    version=$(jq -r ".skills[$i].version // \"0.0.0\"" "$registry")

    if [[ -d "${SKILLS_DIR}/${name}" ]]; then
      installed_tag=" (installed)"
    fi

    printf '%b\n' "  ${ACCENT}${name}${RESET}${installed_tag}  ${DIM}${desc}${RESET}  ${DIM}v${version}${RESET}"
    items[${#items[@]}]="$name"
    i=$((i + 1))
  done
  echo ""

  checklist_select --none "Select skills to install" "${items[@]}"

  if [[ -n "$CHECKLIST_RESULT" ]]; then
    local IFS=$'\n'
    local selected
    for selected in $CHECKLIST_RESULT; do
      if [[ -d "${SKILLS_DIR}/${selected}" ]]; then
        info "Skill '${selected}' is already installed, skipping"
      else
        skill_marketplace_install "$selected"
      fi
    done
  fi
}

skill_marketplace_install() {
  local name="$1"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  start_spinner "Installing ${name}..."
  git clone --quiet --depth 1 https://github.com/ImJustRicky/muster-skills.git "$tmp_dir" 2>/dev/null
  stop_spinner

  if [[ -d "${tmp_dir}/${name}" && -f "${tmp_dir}/${name}/skill.json" ]]; then
    skill_add "${tmp_dir}/${name}"
  else
    err "Skill '${name}' not found in registry"
  fi

  rm -rf "$tmp_dir"
}
