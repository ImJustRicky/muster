#!/usr/bin/env bash
# muster/lib/core/updater.sh — Auto-update check and apply (release + source modes)

MUSTER_UPDATE_AVAILABLE="false"
_MUSTER_UPDATE_CACHE="$HOME/.muster/last_update_check"
_MUSTER_FETCH_PID=""
_MUSTER_LATEST_TAG=""
_MUSTER_LATEST_NOTES_URL=""

_MUSTER_RELEASE_API="https://api.github.com/repos/Muster-dev/muster/releases/latest"

# Compare two semver strings: returns 0 (true) if $1 < $2
# Usage: _semver_lt "0.5.43" "0.5.44"
_semver_lt() {
  local a="$1" b="$2"
  a="${a#v}"; b="${b#v}"
  local a_maj a_min a_pat b_maj b_min b_pat
  a_maj="${a%%.*}"; local a_rest="${a#*.}"
  a_min="${a_rest%%.*}"; a_pat="${a_rest#*.}"
  b_maj="${b%%.*}"; local b_rest="${b#*.}"
  b_min="${b_rest%%.*}"; b_pat="${b_rest#*.}"
  : "${a_pat:=0}"; : "${b_pat:=0}"
  # Strip anything non-numeric from patch (e.g. "44-beta")
  a_pat="${a_pat%%[!0-9]*}"; : "${a_pat:=0}"
  b_pat="${b_pat%%[!0-9]*}"; : "${b_pat:=0}"

  if (( a_maj < b_maj )); then return 0; fi
  if (( a_maj > b_maj )); then return 1; fi
  if (( a_min < b_min )); then return 0; fi
  if (( a_min > b_min )); then return 1; fi
  if (( a_pat < b_pat )); then return 0; fi
  return 1
}

# Start a background update check (non-blocking)
update_check_start() {
  # Guard: update_check setting
  local check_pref
  check_pref=$(global_config_get "update_check" 2>/dev/null)
  if [[ "$check_pref" == "off" ]]; then
    return 0
  fi

  # Determine update mode
  local _mode
  _mode=$(global_config_get "update_mode" 2>/dev/null)
  : "${_mode:=release}"

  # Load cached result for instant display (fetch still runs to refresh)
  if [[ -f "$_MUSTER_UPDATE_CACHE" ]]; then
    local cached_result
    cached_result=$(sed -n '2p' "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "current")
    if [[ "$cached_result" == "behind" ]]; then
      MUSTER_UPDATE_AVAILABLE="true"
      _MUSTER_LATEST_TAG=$(sed -n '3p' "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "")
      _MUSTER_LATEST_NOTES_URL=$(sed -n '4p' "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "")
    fi
  fi

  if [[ "$_mode" == "release" ]]; then
    _update_check_release
  else
    _update_check_source
  fi
}

# Background check: GitHub Releases API
_update_check_release() {
  # Guard: curl must exist
  if ! has_cmd curl; then
    return 0
  fi

  (
    # Fetch latest release tag from GitHub API
    local _api_resp=""
    _api_resp=$(curl -fsSL --max-time 8 "$_MUSTER_RELEASE_API" 2>/dev/null) || exit 1

    # Parse tag_name with grep/sed (no jq needed)
    local _latest_tag=""
    _latest_tag=$(printf '%s' "$_api_resp" | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//;s/".*//')
    [[ -z "$_latest_tag" ]] && exit 1

    # Compare against current version
    local _cur_ver=""
    _cur_ver=$(grep 'MUSTER_VERSION=' "${MUSTER_ROOT}/bin/muster" 2>/dev/null \
      | head -1 | sed 's/.*MUSTER_VERSION="//;s/".*//')

    local result="current"
    if [[ -n "$_cur_ver" ]] && _semver_lt "$_cur_ver" "$_latest_tag"; then
      result="behind"
    fi

    local _notes_url="https://api.github.com/repos/Muster-dev/muster/releases/tags/${_latest_tag}"

    printf '%s\n%s\n%s\n%s\n' "$(date +%s)" "$result" "$_latest_tag" "$_notes_url" \
      > "$_MUSTER_UPDATE_CACHE"
  ) &
  _MUSTER_FETCH_PID=$!
  disown "$_MUSTER_FETCH_PID" 2>/dev/null || true
}

# Background check: git source (current behavior)
_update_check_source() {
  # Guard: git must exist
  if ! has_cmd git; then
    return 0
  fi

  # Guard: MUSTER_ROOT must be a git repo
  if [[ ! -d "${MUSTER_ROOT}/.git" ]]; then
    return 0
  fi

  (
    cd "$MUSTER_ROOT" || exit 1
    # Migrate remote URL to new org if still pointing to old
    _cr="$(git remote get-url origin 2>/dev/null || true)"
    if [[ "$_cr" == *"ImJustRicky/muster"* ]]; then
      git remote set-url origin "https://github.com/Muster-dev/muster.git" 2>/dev/null || true
    fi
    git fetch --quiet origin main 2>/dev/null || exit 1
    local local_head remote_head
    local_head=$(git rev-parse HEAD 2>/dev/null)
    remote_head=$(git rev-parse origin/main 2>/dev/null)
    local result="current"
    if [[ -n "$local_head" && -n "$remote_head" && "$local_head" != "$remote_head" ]]; then
      if git merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
        result="behind"
      fi
    fi
    printf '%s\n%s\n\n\n' "$(date +%s)" "$result" > "$_MUSTER_UPDATE_CACHE"
  ) &
  _MUSTER_FETCH_PID=$!
  disown "$_MUSTER_FETCH_PID" 2>/dev/null || true
}

# Collect background fetch result (non-blocking)
update_check_collect() {
  if [[ -n "$_MUSTER_FETCH_PID" ]]; then
    if ! kill -0 "$_MUSTER_FETCH_PID" 2>/dev/null; then
      wait "$_MUSTER_FETCH_PID" 2>/dev/null || true
      _MUSTER_FETCH_PID=""
      if [[ -f "$_MUSTER_UPDATE_CACHE" ]]; then
        local cached_result
        cached_result=$(sed -n '2p' "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "current")
        _MUSTER_LATEST_TAG=$(sed -n '3p' "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "")
        _MUSTER_LATEST_NOTES_URL=$(sed -n '4p' "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "")
        if [[ "$cached_result" == "behind" ]]; then
          MUSTER_UPDATE_AVAILABLE="true"
        else
          MUSTER_UPDATE_AVAILABLE="false"
        fi
      fi
    fi
  fi
}

# Perform the actual update (dispatcher)
update_apply() {
  local _mode
  _mode=$(global_config_get "update_mode" 2>/dev/null)
  : "${_mode:=release}"

  # Migrate remote URL to new org if still pointing to old
  if has_cmd git && [[ -d "${MUSTER_ROOT}/.git" ]]; then
    local _cur_remote
    _cur_remote="$(cd "$MUSTER_ROOT" && git remote get-url origin 2>/dev/null || true)"
    if [[ "$_cur_remote" == *"ImJustRicky/muster"* ]]; then
      (cd "$MUSTER_ROOT" && git remote set-url origin "https://github.com/Muster-dev/muster.git" 2>/dev/null) || true
    fi
  fi

  if [[ "$_mode" == "release" ]]; then
    _update_apply_release
  else
    _update_apply_source
  fi
}

# ── Release mode update ──

_update_apply_release() {
  echo ""

  # Need curl for release mode
  if ! has_cmd curl; then
    err "curl is required for release mode updates"
    printf '  %bSwitch to source mode: muster settings --global update_mode source%b\n' "${DIM}" "${RESET}"
    return 1
  fi

  # If no cached tag, do a synchronous fetch
  if [[ -z "$_MUSTER_LATEST_TAG" ]]; then
    info "Checking for latest release..."
    local _api_resp=""
    _api_resp=$(curl -fsSL --max-time 10 "$_MUSTER_RELEASE_API" 2>/dev/null)
    if [[ -z "$_api_resp" ]]; then
      err "Could not reach GitHub. Check your connection."
      return 1
    fi
    _MUSTER_LATEST_TAG=$(printf '%s' "$_api_resp" | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//;s/".*//')
    _MUSTER_LATEST_NOTES_URL="https://api.github.com/repos/Muster-dev/muster/releases/tags/${_MUSTER_LATEST_TAG}"
  fi

  if [[ -z "$_MUSTER_LATEST_TAG" ]]; then
    err "No releases found. The release channel may not be set up yet."
    printf '  %bSwitch to source mode: muster settings --global update_mode source%b\n' "${DIM}" "${RESET}"
    return 1
  fi

  # Check if already up to date
  local _cur_ver=""
  _cur_ver=$(grep 'MUSTER_VERSION=' "${MUSTER_ROOT}/bin/muster" 2>/dev/null \
    | head -1 | sed 's/.*MUSTER_VERSION="//;s/".*//')

  if ! _semver_lt "$_cur_ver" "$_MUSTER_LATEST_TAG"; then
    ok "Already up to date (v${_cur_ver})"
    echo ""
    return 0
  fi

  printf '  %b%bUpdate available%b  v%s → %s\n' "${BOLD}" "${ACCENT_BRIGHT}" "${RESET}" "$_cur_ver" "$_MUSTER_LATEST_TAG"
  echo ""

  # Fetch and display release notes
  local _notes=""
  if [[ -n "$_MUSTER_LATEST_NOTES_URL" ]]; then
    local _release_resp=""
    _release_resp=$(curl -fsSL --max-time 10 "$_MUSTER_LATEST_NOTES_URL" 2>/dev/null)
    if [[ -n "$_release_resp" ]]; then
      # Extract "body" field — JSON string between first "body": " and closing "
      _notes=$(printf '%s' "$_release_resp" | sed -n 's/.*"body"[[:space:]]*:[[:space:]]*"//p' \
        | sed 's/"[[:space:]]*,\{0,1\}[[:space:]]*$//' \
        | sed 's/\\n/\
/g; s/\\r//g; s/\\"/"/g; s/\\t/  /g')
    fi
  fi

  if [[ -n "$_notes" ]]; then
    printf '  %b%bWhat'\''s new:%b\n' "${BOLD}" "${WHITE}" "${RESET}"
    echo ""
    local _line_count=0
    while IFS= read -r _nline; do
      _line_count=$(( _line_count + 1 ))
      if (( _line_count > 25 )); then
        printf '  %b  ... see full notes at github.com/Muster-dev/muster/releases%b\n' "${DIM}" "${RESET}"
        break
      fi
      printf '  %b  %s%b\n' "${DIM}" "$_nline" "${RESET}"
    done <<< "$_notes"
    echo ""
  fi

  # Prompt for confirmation
  printf '  %bUpdate to %s? [y/N]%b ' "${WHITE}" "$_MUSTER_LATEST_TAG" "${RESET}"
  local _confirm=""
  IFS= read -rsn1 _confirm || true
  echo ""

  case "$_confirm" in
    y|Y)
      echo ""
      info "Updating to ${_MUSTER_LATEST_TAG}..."

      if ! has_cmd git || [[ ! -d "${MUSTER_ROOT}/.git" ]]; then
        err "Git repository not found at ${MUSTER_ROOT}"
        return 1
      fi

      if (cd "$MUSTER_ROOT" && git fetch --quiet --tags origin 2>&1 && git checkout --quiet "$_MUSTER_LATEST_TAG" 2>&1); then
        printf '%s\n%s\n%s\n%s\n' "$(date +%s)" "current" "$_MUSTER_LATEST_TAG" "" > "$_MUSTER_UPDATE_CACHE"
        MUSTER_UPDATE_AVAILABLE="false"

        echo ""
        ok "Updated to ${_MUSTER_LATEST_TAG}"
        echo ""
        printf '  %bPlease re-run %bmuster%b%b to use the new version.%b\n' "${DIM}" "${BOLD}" "${RESET}" "${DIM}" "${RESET}"
        echo ""
        printf '  %bPress any key to exit...%b\n' "${DIM}" "${RESET}"
        IFS= read -rsn1 || true
        exit 0
      else
        err "Update failed. You can update manually:"
        printf '  %bcd %s && git fetch --tags && git checkout %s%b\n' "${DIM}" "$MUSTER_ROOT" "$_MUSTER_LATEST_TAG" "${RESET}"
        echo ""
      fi
      ;;
    *)
      echo ""
      info "Update skipped."
      echo ""
      ;;
  esac
}

# ── Source mode update (risky) ──

_update_apply_source() {
  echo ""
  warn "Source mode — tracking HEAD of main"
  printf '  %bThis may include unstable or unreleased changes.%b\n' "${DIM}" "${RESET}"
  echo ""
  printf '  %bContinue? [y/N]%b ' "${YELLOW}" "${RESET}"
  local _confirm=""
  IFS= read -rsn1 _confirm || true
  echo ""

  case "$_confirm" in
    y|Y)
      echo ""
      info "Updating from source..."
      echo ""

      if ! has_cmd git || [[ ! -d "${MUSTER_ROOT}/.git" ]]; then
        err "Git repository not found at ${MUSTER_ROOT}"
        return 1
      fi

      if (cd "$MUSTER_ROOT" && git pull --quiet origin main 2>&1); then
        printf '%s\n%s\n\n\n' "$(date +%s)" "current" > "$_MUSTER_UPDATE_CACHE"
        # shellcheck disable=SC2034
        MUSTER_UPDATE_AVAILABLE="false"

        local new_ver
        new_ver=$(grep 'MUSTER_VERSION=' "${MUSTER_ROOT}/bin/muster" 2>/dev/null \
          | head -1 | sed 's/.*MUSTER_VERSION="//;s/".*//')

        echo ""
        ok "Updated to v${new_ver:-unknown}"
        echo ""
        printf '  %bPlease re-run %bmuster%b%b to use the new version.%b\n' "${DIM}" "${BOLD}" "${RESET}" "${DIM}" "${RESET}"
        echo ""
        printf '  %bPress any key to exit...%b\n' "${DIM}" "${RESET}"
        IFS= read -rsn1 || true
        exit 0
      else
        err "Update failed. You can update manually:"
        printf '  %bcd %s && git pull%b\n' "${DIM}" "$MUSTER_ROOT" "${RESET}"
        echo ""
      fi
      ;;
    *)
      echo ""
      info "Update cancelled."
      echo ""
      ;;
  esac
}
