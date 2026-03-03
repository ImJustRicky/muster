#!/usr/bin/env bash
# muster/lib/core/trust.sh — Fleet Trust: identity, join requests, deploy gate

MUSTER_IDENTITY_FILE="$HOME/.muster/identity.json"
MUSTER_FLEET_DIR="$HOME/.muster/fleet"
MUSTER_TRUST_FILE="$HOME/.muster/fleet/trusted.json"
MUSTER_PENDING_FILE="$HOME/.muster/fleet/pending.json"

# ── Identity ──

# Ensure identity.json exists; generate fingerprint on first call
_trust_ensure_identity() {
  [[ -f "$MUSTER_IDENTITY_FILE" ]] && return 0

  mkdir -p "$HOME/.muster"
  chmod 700 "$HOME/.muster" 2>/dev/null || true

  local fp
  fp="mst_$(openssl rand -hex 16)"

  local hostname_val
  hostname_val=$(hostname -s 2>/dev/null || echo "unknown")

  local user_val="${USER:-unknown}"
  local created
  created=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  printf '{"fingerprint":"%s","hostname":"%s","user":"%s","created":"%s"}\n' \
    "$fp" "$hostname_val" "$user_val" "$created" > "$MUSTER_IDENTITY_FILE"
  chmod 600 "$MUSTER_IDENTITY_FILE"
}

# Read the local fingerprint (auto-creates identity if missing)
trust_fingerprint() {
  _trust_ensure_identity
  jq -r '.fingerprint' "$MUSTER_IDENTITY_FILE" 2>/dev/null
}

# Read the local label ("user@hostname")
trust_label() {
  _trust_ensure_identity
  local _u _h
  _u=$(jq -r '.user' "$MUSTER_IDENTITY_FILE" 2>/dev/null)
  _h=$(jq -r '.hostname' "$MUSTER_IDENTITY_FILE" 2>/dev/null)
  printf '%s@%s' "$_u" "$_h"
}

# ── Trust file management ──

_trust_ensure_files() {
  if [[ ! -d "$MUSTER_FLEET_DIR" ]]; then
    mkdir -p "$MUSTER_FLEET_DIR"
    chmod 700 "$MUSTER_FLEET_DIR" 2>/dev/null || true
  fi
  if [[ ! -f "$MUSTER_TRUST_FILE" ]]; then
    printf '[]\n' > "$MUSTER_TRUST_FILE"
    chmod 600 "$MUSTER_TRUST_FILE"
  fi
  if [[ ! -f "$MUSTER_PENDING_FILE" ]]; then
    printf '[]\n' > "$MUSTER_PENDING_FILE"
    chmod 600 "$MUSTER_PENDING_FILE"
  fi
}

# ── Pending requests ──

# Add a join request to pending.json
# Args: fingerprint label
trust_add_pending() {
  local fp="$1" label="$2"
  _trust_ensure_files

  # Skip if already trusted
  if trust_is_trusted "$fp"; then
    printf 'already_trusted\n'
    return 0
  fi

  # Skip if already pending
  if trust_is_pending "$fp"; then
    printf 'already_pending\n'
    return 0
  fi

  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local tmp="${MUSTER_PENDING_FILE}.tmp.$$"
  jq --arg fp "$fp" --arg label "$label" --arg ts "$ts" \
    '. + [{"fingerprint": $fp, "label": $label, "requested_at": $ts}]' \
    "$MUSTER_PENDING_FILE" > "$tmp" && mv "$tmp" "$MUSTER_PENDING_FILE"
  chmod 600 "$MUSTER_PENDING_FILE"
  printf 'pending\n'
}

# List pending requests
# Output: newline-separated "fingerprint|label|requested_at" lines
trust_list_pending() {
  _trust_ensure_files
  jq -r '.[] | [.fingerprint, .label, .requested_at] | join("|")' "$MUSTER_PENDING_FILE" 2>/dev/null
}

# Count pending requests
trust_pending_count() {
  _trust_ensure_files
  local c
  c=$(jq 'length' "$MUSTER_PENDING_FILE" 2>/dev/null)
  printf '%s' "${c:-0}"
}

# Check if a fingerprint is pending
trust_is_pending() {
  local fp="$1"
  _trust_ensure_files
  local match
  match=$(jq -r --arg fp "$fp" '[.[] | select(.fingerprint == $fp)] | length' "$MUSTER_PENDING_FILE" 2>/dev/null)
  [[ "$match" -gt 0 ]] 2>/dev/null
}

# Accept a pending request by fingerprint or 1-based index
# Returns 1 if not found
trust_accept() {
  local id="$1"
  _trust_ensure_files

  local fp=""
  if [[ "$id" =~ ^[0-9]+$ ]]; then
    # Index-based (1-based)
    local idx=$(( id - 1 ))
    fp=$(jq -r --argjson i "$idx" '.[$i].fingerprint // empty' "$MUSTER_PENDING_FILE" 2>/dev/null)
  else
    fp="$id"
  fi

  [[ -z "$fp" ]] && return 1

  # Get entry from pending
  local label
  label=$(jq -r --arg fp "$fp" '.[] | select(.fingerprint == $fp) | .label' "$MUSTER_PENDING_FILE" 2>/dev/null)
  [[ -z "$label" ]] && return 1

  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Add to trusted
  local tmp="${MUSTER_TRUST_FILE}.tmp.$$"
  jq --arg fp "$fp" --arg label "$label" --arg ts "$ts" \
    '. + [{"fingerprint": $fp, "label": $label, "accepted_at": $ts}]' \
    "$MUSTER_TRUST_FILE" > "$tmp" && mv "$tmp" "$MUSTER_TRUST_FILE"
  chmod 600 "$MUSTER_TRUST_FILE"

  # Remove from pending
  tmp="${MUSTER_PENDING_FILE}.tmp.$$"
  jq --arg fp "$fp" '[.[] | select(.fingerprint != $fp)]' \
    "$MUSTER_PENDING_FILE" > "$tmp" && mv "$tmp" "$MUSTER_PENDING_FILE"
  chmod 600 "$MUSTER_PENDING_FILE"
}

# Reject a pending request by fingerprint or 1-based index
trust_reject() {
  local id="$1"
  _trust_ensure_files

  local fp=""
  if [[ "$id" =~ ^[0-9]+$ ]]; then
    local idx=$(( id - 1 ))
    fp=$(jq -r --argjson i "$idx" '.[$i].fingerprint // empty' "$MUSTER_PENDING_FILE" 2>/dev/null)
  else
    fp="$id"
  fi

  [[ -z "$fp" ]] && return 1

  # Verify it exists
  local match
  match=$(jq -r --arg fp "$fp" '[.[] | select(.fingerprint == $fp)] | length' "$MUSTER_PENDING_FILE" 2>/dev/null)
  [[ "$match" -lt 1 ]] 2>/dev/null && return 1

  local tmp="${MUSTER_PENDING_FILE}.tmp.$$"
  jq --arg fp "$fp" '[.[] | select(.fingerprint != $fp)]' \
    "$MUSTER_PENDING_FILE" > "$tmp" && mv "$tmp" "$MUSTER_PENDING_FILE"
  chmod 600 "$MUSTER_PENDING_FILE"
}

# ── Trusted deployers ──

# List trusted deployers
# Output: newline-separated "fingerprint|label|accepted_at" lines
trust_list_trusted() {
  _trust_ensure_files
  jq -r '.[] | [.fingerprint, .label, .accepted_at] | join("|")' "$MUSTER_TRUST_FILE" 2>/dev/null
}

# Check if a fingerprint is trusted
trust_is_trusted() {
  local fp="$1"
  _trust_ensure_files
  local match
  match=$(jq -r --arg fp "$fp" '[.[] | select(.fingerprint == $fp)] | length' "$MUSTER_TRUST_FILE" 2>/dev/null)
  [[ "$match" -gt 0 ]] 2>/dev/null
}

# Revoke a trusted deployer by fingerprint or 1-based index
trust_revoke() {
  local id="$1"
  _trust_ensure_files

  local fp=""
  if [[ "$id" =~ ^[0-9]+$ ]]; then
    local idx=$(( id - 1 ))
    fp=$(jq -r --argjson i "$idx" '.[$i].fingerprint // empty' "$MUSTER_TRUST_FILE" 2>/dev/null)
  else
    fp="$id"
  fi

  [[ -z "$fp" ]] && return 1

  local match
  match=$(jq -r --arg fp "$fp" '[.[] | select(.fingerprint == $fp)] | length' "$MUSTER_TRUST_FILE" 2>/dev/null)
  [[ "$match" -lt 1 ]] 2>/dev/null && return 1

  local tmp="${MUSTER_TRUST_FILE}.tmp.$$"
  jq --arg fp "$fp" '[.[] | select(.fingerprint != $fp)]' \
    "$MUSTER_TRUST_FILE" > "$tmp" && mv "$tmp" "$MUSTER_TRUST_FILE"
  chmod 600 "$MUSTER_TRUST_FILE"
}

# ── Deploy gate ──

# Check if a fingerprint is authorized to deploy
# Returns: 0 if trusted, 1 if pending, 2 if unknown
# Outputs status to stdout: "trusted", "pending", or "unknown"
trust_check_deploy() {
  local fp="$1"
  _trust_ensure_files

  if trust_is_trusted "$fp"; then
    printf 'trusted\n'
    return 0
  fi

  if trust_is_pending "$fp"; then
    printf 'pending\n'
    return 1
  fi

  printf 'unknown\n'
  return 2
}
