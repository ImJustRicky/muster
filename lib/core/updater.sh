#!/usr/bin/env bash
# muster/lib/core/updater.sh — Auto-update check and apply

MUSTER_UPDATE_AVAILABLE="false"
_MUSTER_UPDATE_CACHE="$HOME/.muster/last_update_check"
_MUSTER_FETCH_PID=""

# Check if enough time has elapsed since last check (86400 = 24h)
_update_check_stale() {
  if [[ ! -f "$_MUSTER_UPDATE_CACHE" ]]; then
    return 0
  fi
  local last_ts now_ts
  last_ts=$(head -1 "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo 0)
  now_ts=$(date +%s)
  local diff=$(( now_ts - last_ts ))
  (( diff >= 86400 ))
}

# Start a background git fetch (non-blocking)
update_check_start() {
  # Guard: update_check setting
  local check_pref
  check_pref=$(global_config_get "update_check" 2>/dev/null)
  if [[ "$check_pref" == "off" ]]; then
    return 0
  fi

  # Guard: git must exist
  if ! has_cmd git; then
    return 0
  fi

  # Guard: MUSTER_ROOT must be a git repo
  if [[ ! -d "${MUSTER_ROOT}/.git" ]]; then
    return 0
  fi

  # Load cached result for instant display (fetch still runs to refresh)
  if [[ -f "$_MUSTER_UPDATE_CACHE" ]]; then
    local cached_result
    cached_result=$(tail -1 "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "current")
    if [[ "$cached_result" == "behind" ]]; then
      MUSTER_UPDATE_AVAILABLE="true"
    fi
  fi

  # Always run background fetch (non-blocking, <1s)
  # Cache provides instant display; fetch refreshes the result
  (
    cd "$MUSTER_ROOT" || exit 1
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
    printf '%s\n%s\n' "$(date +%s)" "$result" > "$_MUSTER_UPDATE_CACHE"
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
      local cached_result
      cached_result=$(tail -1 "$_MUSTER_UPDATE_CACHE" 2>/dev/null || echo "current")
      if [[ "$cached_result" == "behind" ]]; then
        MUSTER_UPDATE_AVAILABLE="true"
      fi
    fi
  fi
}

# Perform the actual update
update_apply() {
  echo ""
  info "Updating muster..."
  echo ""
  if (cd "$MUSTER_ROOT" && git pull --quiet origin main 2>&1); then
    printf '%s\n%s\n' "$(date +%s)" "current" > "$_MUSTER_UPDATE_CACHE"
    MUSTER_UPDATE_AVAILABLE="false"

    local new_ver
    new_ver=$(grep 'MUSTER_VERSION=' "${MUSTER_ROOT}/bin/muster" 2>/dev/null \
      | head -1 | sed 's/.*MUSTER_VERSION="//;s/".*//')

    echo ""
    ok "Updated to v${new_ver:-unknown}"
    echo ""
    echo -e "  ${DIM}Please re-run ${BOLD}muster${RESET}${DIM} to use the new version.${RESET}"
    echo ""
    echo -e "  ${DIM}Press any key to exit...${RESET}"
    IFS= read -rsn1 || true
    exit 0
  else
    err "Update failed. You can update manually:"
    echo -e "  ${DIM}cd ${MUSTER_ROOT} && git pull${RESET}"
    echo ""
  fi
}
