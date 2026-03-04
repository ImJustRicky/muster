#!/usr/bin/env bash
# muster/lib/commands/verify.sh — muster verify command

cmd_verify() {
  local quick=false json=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quick) quick=true; shift ;;
      --json)  json=true; shift ;;
      --help|-h)
        echo "Usage: muster verify [--quick] [--json]"
        echo ""
        echo "  --quick   Signature check only (no file hashing)"
        echo "  --json    JSON output"
        return 0
        ;;
      *)
        err "Unknown flag: $1"
        return 1
        ;;
    esac
  done

  if [[ "$quick" == "true" ]]; then
    if _app_verify_quick; then
      if [[ "$json" == "true" ]]; then
        printf '{"result":"pass","mode":"quick"}\n'
      else
        ok "Signature valid"
      fi
      return 0
    else
      if [[ "$json" == "true" ]]; then
        printf '{"result":"fail","mode":"quick"}\n'
      else
        err "Signature check failed"
        if [[ ! -f "$_APP_MANIFEST" ]]; then
          printf '  %bNo manifest found (run: make manifest)%b\n' "${DIM}" "${RESET}"
        elif [[ ! -f "$_APP_MANIFEST_SIG" ]]; then
          printf '  %bNo signature found (run: make manifest-sign)%b\n' "${DIM}" "${RESET}"
        fi
      fi
      return 1
    fi
  fi

  # Full verify
  if [[ ! -f "$_APP_MANIFEST" ]]; then
    if [[ "$json" == "true" ]]; then
      printf '{"result":"no_manifest","mode":"full"}\n'
    else
      warn "No manifest found (development install)"
      printf '  %bGenerate with: make manifest%b\n' "${DIM}" "${RESET}"
    fi
    return 0
  fi

  _app_verify_full
  local rc=$?

  if [[ "$json" == "true" ]]; then
    printf '{"result":"%s","mode":"full","version":"%s","file_count":%d,"pass":%d,"tampered":%d,"missing":%d,"extra":%d}\n' \
      "$([ $rc -eq 0 ] && echo pass || echo fail)" \
      "$_APP_VERIFY_VERSION" "$_APP_VERIFY_FILE_COUNT" \
      "$_APP_VERIFY_PASS" "$_APP_VERIFY_TAMPERED" "$_APP_VERIFY_MISSING" "$_APP_VERIFY_EXTRA"
  else
    echo ""
    printf '  %bMuster v%s — File Integrity Check%b\n' "${BOLD}" "$_APP_VERIFY_VERSION" "${RESET}"
    echo ""
    _app_verify_report
    echo ""
  fi

  return $rc
}
