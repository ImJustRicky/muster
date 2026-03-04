#!/usr/bin/env bash
# muster/lib/core/app_verify.sh — App file integrity verification

# ── Manifest paths ──

_APP_MANIFEST="${MUSTER_ROOT}/.muster.manifest"
_APP_MANIFEST_SIG="${MUSTER_ROOT}/.muster.manifest.sig"

# ── Tracked file patterns ──

_app_tracked_files() {
  local root="${MUSTER_ROOT:-.}"
  local files=()

  # Binaries
  for f in "$root"/bin/muster "$root"/bin/muster-mcp; do
    [[ -f "$f" ]] && files[${#files[@]}]="${f#${root}/}"
  done

  # Core libs
  for f in "$root"/lib/core/*.sh; do
    [[ -f "$f" ]] && files[${#files[@]}]="${f#${root}/}"
  done

  # Command libs
  for f in "$root"/lib/commands/*.sh; do
    [[ -f "$f" ]] && files[${#files[@]}]="${f#${root}/}"
  done

  # TUI libs
  for f in "$root"/lib/tui/*.sh; do
    [[ -f "$f" ]] && files[${#files[@]}]="${f#${root}/}"
  done

  # Skills libs
  for f in "$root"/lib/skills/*.sh; do
    [[ -f "$f" ]] && files[${#files[@]}]="${f#${root}/}"
  done

  # Agent libs
  for f in "$root"/lib/agent/*.sh; do
    [[ -f "$f" ]] && files[${#files[@]}]="${f#${root}/}"
  done

  # Hook templates (recursive — two levels deep)
  for f in "$root"/templates/hooks/*.sh "$root"/templates/hooks/*/*.sh "$root"/templates/hooks/*/*/*.sh; do
    [[ -f "$f" ]] && files[${#files[@]}]="${f#${root}/}"
  done

  # Installer
  [[ -f "$root/install.sh" ]] && files[${#files[@]}]="install.sh"

  local i=0
  while (( i < ${#files[@]} )); do
    printf '%s\n' "${files[$i]}"
    i=$(( i + 1 ))
  done
}

# ── Manifest generation ──

_app_manifest_generate() {
  local root="${MUSTER_ROOT:-.}"
  local manifest="${root}/.muster.manifest"

  # Get version from bin/muster
  local version=""
  if [[ -f "$root/bin/muster" ]]; then
    version=$(grep 'MUSTER_VERSION=' "$root/bin/muster" 2>/dev/null \
      | head -1 | sed 's/.*MUSTER_VERSION="//;s/".*//')
  fi

  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local file_count=0
  local json_files=""
  local first=true

  while IFS= read -r relpath; do
    [[ -z "$relpath" ]] && continue
    local fullpath="$root/$relpath"
    [[ ! -f "$fullpath" ]] && continue

    local sha
    sha=$(shasum -a 256 "$fullpath" 2>/dev/null | cut -d' ' -f1)
    [[ -z "$sha" ]] && continue

    local size
    size=$(wc -c < "$fullpath" | tr -d ' ')

    # Escape JSON special chars in filename (\ and ")
    local safe_relpath
    safe_relpath=$(printf '%s' "$relpath" | sed 's/\\/\\\\/g;s/"/\\"/g')

    [[ "$first" == "true" ]] && first=false || json_files="${json_files},"
    json_files="${json_files}\"${safe_relpath}\":{\"sha256\":\"${sha}\",\"size\":${size}}"
    file_count=$(( file_count + 1 ))
  done < <(_app_tracked_files)

  printf '{"version":"%s","generated_at":"%s","file_count":%d,"files":{%s}}\n' \
    "$version" "$ts" "$file_count" "$json_files" > "$manifest"
  chmod 644 "$manifest"
}

# ── Manifest signing ──

_app_manifest_sign() {
  [[ ! -f "$_APP_MANIFEST" ]] && return 1

  # Ensure keypair exists
  _payload_ensure_keypair || return 1

  local sig
  sig=$(payload_sign "$_APP_MANIFEST")
  [[ -z "$sig" ]] && return 1

  printf '%s' "$sig" > "$_APP_MANIFEST_SIG"
  chmod 644 "$_APP_MANIFEST_SIG"
}

# ── Quick verify (signature only — no file hashing) ──

_app_verify_quick() {
  # No manifest → dev install, pass
  [[ ! -f "$_APP_MANIFEST" ]] && return 0

  # No signature → fail (manifest exists but unsigned)
  [[ ! -f "$_APP_MANIFEST_SIG" ]] && return 1

  # No pubkey → signing not configured, pass
  [[ ! -f "$_PAYLOAD_PUBKEY" ]] && return 0

  local sig
  sig=$(cat "$_APP_MANIFEST_SIG" 2>/dev/null)
  [[ -z "$sig" ]] && return 1

  payload_verify "$_APP_MANIFEST" "$sig" "$_PAYLOAD_PUBKEY"
}

# ── Full verify (re-hash every file) ──

# Result counters (set after _app_verify_full runs)
_APP_VERIFY_PASS=0
_APP_VERIFY_TAMPERED=0
_APP_VERIFY_MISSING=0
_APP_VERIFY_EXTRA=0
_APP_VERIFY_VERSION=""
_APP_VERIFY_FILE_COUNT=0

# Per-file results: parallel arrays
_APP_VERIFY_FILES=()
_APP_VERIFY_RESULTS=()

_app_verify_full() {
  local root="${MUSTER_ROOT:-.}"
  _APP_VERIFY_PASS=0
  _APP_VERIFY_TAMPERED=0
  _APP_VERIFY_MISSING=0
  _APP_VERIFY_EXTRA=0
  _APP_VERIFY_FILES=()
  _APP_VERIFY_RESULTS=()

  [[ ! -f "$_APP_MANIFEST" ]] && return 1

  # Verify signature if sig exists
  local sig_ok=true
  if [[ -f "$_APP_MANIFEST_SIG" && -f "$_PAYLOAD_PUBKEY" ]]; then
    if ! _app_verify_quick; then
      sig_ok=false
    fi
  fi

  # Parse manifest — use jq if available, fallback to grep/sed
  local manifest_json
  manifest_json=$(cat "$_APP_MANIFEST" 2>/dev/null)
  [[ -z "$manifest_json" ]] && return 1

  # Extract version
  if command -v jq >/dev/null 2>&1; then
    _APP_VERIFY_VERSION=$(printf '%s' "$manifest_json" | jq -r '.version // ""' 2>/dev/null)
    _APP_VERIFY_FILE_COUNT=$(printf '%s' "$manifest_json" | jq -r '.file_count // 0' 2>/dev/null)
  else
    _APP_VERIFY_VERSION=$(printf '%s' "$manifest_json" | sed 's/.*"version":"\([^"]*\)".*/\1/')
    _APP_VERIFY_FILE_COUNT=$(printf '%s' "$manifest_json" | sed 's/.*"file_count":\([0-9]*\).*/\1/')
  fi

  # Build list of expected files from manifest
  local expected_files=""
  if command -v jq >/dev/null 2>&1; then
    expected_files=$(printf '%s' "$manifest_json" | jq -r '.files | keys[]' 2>/dev/null)
  else
    # Fallback: extract keys from the files object
    expected_files=$(printf '%s' "$manifest_json" \
      | sed 's/.*"files":{//;s/}}//' \
      | grep -o '"[^"]*":{"sha256"' \
      | sed 's/":{"sha256"//;s/"//g')
  fi

  # Check each expected file
  while IFS= read -r relpath; do
    [[ -z "$relpath" ]] && continue
    local fullpath="$root/$relpath"

    _APP_VERIFY_FILES[${#_APP_VERIFY_FILES[@]}]="$relpath"

    if [[ ! -f "$fullpath" ]]; then
      _APP_VERIFY_RESULTS[${#_APP_VERIFY_RESULTS[@]}]="missing"
      _APP_VERIFY_MISSING=$(( _APP_VERIFY_MISSING + 1 ))
      continue
    fi

    # Get expected hash
    local expected_sha=""
    if command -v jq >/dev/null 2>&1; then
      expected_sha=$(printf '%s' "$manifest_json" | jq -r --arg f "$relpath" '.files[$f].sha256 // ""' 2>/dev/null)
    else
      # Escape regex metacharacters in filename for grep safety
      local safe_relpath
      safe_relpath=$(printf '%s' "$relpath" | sed 's/[][\\.^$*+?{}()|]/\\&/g')
      expected_sha=$(printf '%s' "$manifest_json" \
        | grep -o "\"${safe_relpath}\":{\"sha256\":\"[a-f0-9]*\"" \
        | sed 's/.*"sha256":"//;s/"//')
    fi

    # Empty hash = extraction failed or file not in manifest — treat as tampered
    if [[ -z "$expected_sha" ]]; then
      _APP_VERIFY_RESULTS[${#_APP_VERIFY_RESULTS[@]}]="tampered"
      _APP_VERIFY_TAMPERED=$(( _APP_VERIFY_TAMPERED + 1 ))
      continue
    fi

    local actual_sha
    actual_sha=$(shasum -a 256 "$fullpath" 2>/dev/null | cut -d' ' -f1)

    if [[ -n "$actual_sha" && "$actual_sha" == "$expected_sha" ]]; then
      _APP_VERIFY_RESULTS[${#_APP_VERIFY_RESULTS[@]}]="pass"
      _APP_VERIFY_PASS=$(( _APP_VERIFY_PASS + 1 ))
    else
      _APP_VERIFY_RESULTS[${#_APP_VERIFY_RESULTS[@]}]="tampered"
      _APP_VERIFY_TAMPERED=$(( _APP_VERIFY_TAMPERED + 1 ))
    fi
  done <<< "$expected_files"

  # Check for extra files not in manifest
  while IFS= read -r relpath; do
    [[ -z "$relpath" ]] && continue
    local in_manifest=false

    if command -v jq >/dev/null 2>&1; then
      local check
      check=$(printf '%s' "$manifest_json" | jq -r --arg f "$relpath" '.files[$f] // empty' 2>/dev/null)
      [[ -n "$check" ]] && in_manifest=true
    else
      # Use grep -F for literal string match (no regex interpretation)
      if printf '%s' "$manifest_json" | grep -qF "\"${relpath}\":" 2>/dev/null; then
        in_manifest=true
      fi
    fi

    if [[ "$in_manifest" == "false" ]]; then
      _APP_VERIFY_FILES[${#_APP_VERIFY_FILES[@]}]="$relpath"
      _APP_VERIFY_RESULTS[${#_APP_VERIFY_RESULTS[@]}]="extra"
      _APP_VERIFY_EXTRA=$(( _APP_VERIFY_EXTRA + 1 ))
    fi
  done < <(_app_tracked_files)

  # Return failure if any issues
  if (( _APP_VERIFY_TAMPERED > 0 || _APP_VERIFY_MISSING > 0 )) || [[ "$sig_ok" == "false" ]]; then
    return 1
  fi
  return 0
}

# ── Report ──

_app_verify_report() {
  local i=0
  while (( i < ${#_APP_VERIFY_FILES[@]} )); do
    local relpath="${_APP_VERIFY_FILES[$i]}"
    local result="${_APP_VERIFY_RESULTS[$i]}"

    case "$result" in
      pass)
        printf '  %b✓%b %s\n' "${GREEN}" "${RESET}" "$relpath"
        ;;
      tampered)
        printf '  %b✗%b %s %b— tampered%b\n' "${RED}" "${RESET}" "$relpath" "${RED}" "${RESET}"
        ;;
      missing)
        printf '  %b✗%b %s %b— missing%b\n' "${RED}" "${RESET}" "$relpath" "${RED}" "${RESET}"
        ;;
      extra)
        printf '  %b!%b %s %b— not in manifest%b\n' "${YELLOW}" "${RESET}" "$relpath" "${YELLOW}" "${RESET}"
        ;;
    esac

    i=$(( i + 1 ))
  done

  echo ""
  if (( _APP_VERIFY_TAMPERED > 0 || _APP_VERIFY_MISSING > 0 )); then
    printf '  %bFAIL%b — %d passed, %d tampered, %d missing' \
      "${RED}" "${RESET}" "$_APP_VERIFY_PASS" "$_APP_VERIFY_TAMPERED" "$_APP_VERIFY_MISSING"
    (( _APP_VERIFY_EXTRA > 0 )) && printf ', %d extra' "$_APP_VERIFY_EXTRA"
    printf '\n'
  else
    printf '  %bPASS%b — all %d files verified' "${GREEN}" "${RESET}" "$_APP_VERIFY_PASS"
    (( _APP_VERIFY_EXTRA > 0 )) && printf ' (%d extra not in manifest)' "$_APP_VERIFY_EXTRA"
    printf '\n'
  fi
}
