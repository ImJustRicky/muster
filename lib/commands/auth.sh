#!/usr/bin/env bash
# muster/lib/commands/auth.sh — Token management CLI

cmd_auth() {
  case "${1:-}" in
    create)
      shift
      local name="" scope="read"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --scope|-s) scope="$2"; shift 2 ;;
          --help|-h)
            echo "Usage: muster auth create <name> [--scope <scope>]"
            echo ""
            echo "Generate a new API token for JSON API access."
            echo ""
            echo "Options:"
            echo "  --scope, -s <scope>   Token scope: read, deploy, admin (default: read)"
            echo ""
            echo "Scopes:"
            echo "  read     View status, history, doctor, settings"
            echo "  deploy   Read + deploy, rollback, logs"
            echo "  admin    Full access including setup, auth, uninstall"
            echo ""
            echo "Examples:"
            echo "  muster auth create my-laptop --scope admin"
            echo "  muster auth create ci-bot --scope deploy"
            echo "  muster auth create dashboard --scope read"
            return 0
            ;;
          --*)
            err "Unknown flag: $1"
            return 1
            ;;
          *)
            name="$1"
            shift
            ;;
        esac
      done

      if [[ -z "$name" ]]; then
        err "Usage: muster auth create <name> --scope <scope>"
        return 1
      fi

      local token
      token=$(auth_create_token "$name" "$scope") || return 1

      echo ""
      printf '%b\n' "  ${GREEN}Token created${RESET}"
      echo ""
      printf '%b\n' "  Name:   ${BOLD}${name}${RESET}"
      printf '%b\n' "  Scope:  ${scope}"
      printf '%b\n' "  Token:  ${ACCENT}${token}${RESET}"
      echo ""
      printf '%b\n' "  ${YELLOW}Save this token now -- it won't be shown again.${RESET}"
      printf '%b\n' "  ${DIM}Set MUSTER_TOKEN=<token> when using --json commands.${RESET}"
      echo ""
      ;;

    list)
      auth_list_tokens
      ;;

    revoke)
      shift
      if [[ -z "${1:-}" ]]; then
        err "Usage: muster auth revoke <name>"
        return 1
      fi
      auth_revoke_token "$1"
      ;;

    verify)
      if auth_validate_token; then
        printf '%b\n' "  ${GREEN}Valid${RESET} -- scope: ${BOLD}${AUTH_SCOPE}${RESET}"
      fi
      ;;

    --help|-h)
      echo "Usage: muster auth <command>"
      echo ""
      echo "Manage API tokens for secure JSON API access."
      echo ""
      echo "Commands:"
      echo "  create <name> --scope <scope>   Generate a new token"
      echo "  list                            List all tokens"
      echo "  revoke <name>                   Revoke a token"
      echo "  verify                          Validate MUSTER_TOKEN env var"
      echo ""
      echo "Scopes:"
      echo "  read     View status, history, doctor, settings"
      echo "  deploy   Read + deploy, rollback, logs"
      echo "  admin    Full access including setup, auth, uninstall"
      echo ""
      echo "Examples:"
      echo "  muster auth create ci-bot --scope deploy"
      echo "  MUSTER_TOKEN=abc123 muster status --json"
      ;;

    "")
      if [[ -t 0 ]]; then
        _auth_cmd_manager
      else
        echo "Usage: muster auth <command>"
        echo "Run 'muster auth --help' for usage."
      fi
      ;;

    *)
      err "Unknown auth command: $1"
      echo "Run 'muster auth --help' for usage."
      return 1
      ;;
  esac
}

# ── Interactive token manager ──

_auth_cmd_manager() {
  source "$MUSTER_ROOT/lib/tui/menu.sh"

  while true; do
    clear
    echo ""
    printf '%b\n' "  ${BOLD}${ACCENT_BRIGHT}Auth Tokens${RESET}"
    echo ""

    # Show token list
    _auth_ensure_file
    local _at_count
    _at_count=$(jq '.tokens | length' "$MUSTER_TOKENS_FILE" 2>/dev/null)
    : "${_at_count:=0}"

    if [[ "$_at_count" == "0" ]]; then
      printf '  %bNo tokens configured%b\n' "${DIM}" "${RESET}"
    else
      printf '  %b%-18s %-8s %s%b\n' "${DIM}" "NAME" "SCOPE" "CREATED" "${RESET}"
      local _at_i=0
      while (( _at_i < _at_count )); do
        local _at_name _at_scope _at_created
        _at_name=$(jq -r ".tokens[$_at_i].name" "$MUSTER_TOKENS_FILE")
        _at_scope=$(jq -r ".tokens[$_at_i].scope" "$MUSTER_TOKENS_FILE")
        _at_created=$(jq -r ".tokens[$_at_i].created" "$MUSTER_TOKENS_FILE")

        local _at_sc="${RESET}"
        case "$_at_scope" in
          admin)  _at_sc="$RED" ;;
          deploy) _at_sc="$YELLOW" ;;
          read)   _at_sc="$GREEN" ;;
        esac

        printf '  %-18s %b%-8s%b %b%s%b\n' \
          "$_at_name" "$_at_sc" "$_at_scope" "${RESET}" "${DIM}" "$_at_created" "${RESET}"
        _at_i=$(( _at_i + 1 ))
      done
    fi
    echo ""

    local _at_actions=()
    _at_actions[${#_at_actions[@]}]="Create token"
    if [[ "$_at_count" != "0" ]]; then
      _at_actions[${#_at_actions[@]}]="Revoke token"
    fi
    _at_actions[${#_at_actions[@]}]="Back"

    menu_select "Auth" "${_at_actions[@]}"

    case "$MENU_RESULT" in
      "Create token")
        echo ""
        printf '  Token name: '
        local _at_new_name=""
        IFS= read -r _at_new_name
        if [[ -z "$_at_new_name" ]]; then
          info "Cancelled"
          printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
          IFS= read -rsn1 || true
          continue
        fi

        menu_select "Scope" "read" "deploy" "admin"
        local _at_new_scope="$MENU_RESULT"
        if [[ "$_at_new_scope" == "__back__" ]]; then
          continue
        fi

        local _at_token
        _at_token=$(auth_create_token "$_at_new_name" "$_at_new_scope") || {
          printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
          IFS= read -rsn1 || true
          continue
        }

        echo ""
        printf '%b\n' "  ${GREEN}Token created${RESET}"
        echo ""
        printf '%b\n' "  Name:   ${BOLD}${_at_new_name}${RESET}"
        printf '%b\n' "  Scope:  ${_at_new_scope}"
        printf '%b\n' "  Token:  ${ACCENT}${_at_token}${RESET}"
        echo ""
        printf '%b\n' "  ${YELLOW}Save this token now -- it won't be shown again.${RESET}"
        echo ""
        printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
        IFS= read -rsn1 || true
        ;;
      "Revoke token")
        # Build list of token names
        local _at_names=()
        local _at_ri=0
        while (( _at_ri < _at_count )); do
          local _at_rn
          _at_rn=$(jq -r ".tokens[$_at_ri].name" "$MUSTER_TOKENS_FILE")
          _at_names[${#_at_names[@]}]="$_at_rn"
          _at_ri=$(( _at_ri + 1 ))
        done
        _at_names[${#_at_names[@]}]="Back"

        menu_select "Revoke" "${_at_names[@]}"

        if [[ "$MENU_RESULT" != "Back" && "$MENU_RESULT" != "__back__" ]]; then
          printf '  %bRevoke "%s"? [y/N]%b ' "${YELLOW}" "$MENU_RESULT" "${RESET}"
          local _at_rc=""
          IFS= read -rsn1 _at_rc || true
          echo ""
          case "$_at_rc" in
            y|Y)
              auth_revoke_token "$MENU_RESULT"
              ;;
          esac
          printf '%b\n' "  ${DIM}Press any key to continue...${RESET}"
          IFS= read -rsn1 || true
        fi
        ;;
      "Back"|"__back__")
        return 0
        ;;
    esac
  done
}
