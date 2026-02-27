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
    *)
      err "Unknown skill command: ${action}"
      echo "Usage: muster skill [add|create|remove|list|run]"
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
