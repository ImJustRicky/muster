#!/usr/bin/env bash
# tests/test_tokens.sh — Tests for token creation, validation, and revocation
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MUSTER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helpers.sh"

# Minimal stubs
GREEN="" YELLOW="" RED="" RESET="" BOLD="" DIM="" ACCENT="" ACCENT_BRIGHT="" WHITE=""
MUSTER_QUIET="true"
MUSTER_VERBOSE="false"

source "$MUSTER_ROOT/lib/core/logger.sh"
source "$MUSTER_ROOT/lib/core/utils.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Override token file to temp location
export HOME="$TMPDIR"
mkdir -p "$TMPDIR/.muster/tokens"

source "$MUSTER_ROOT/lib/core/auth.sh"

echo "  Token creation"

# Test file creation
_auth_ensure_file
_test_file_exists "tokens file created" "$MUSTER_TOKENS_FILE"

# Test path uses new consolidated location
_test_contains "tokens file in tokens/ subdir" "/tokens/auth.json" "$MUSTER_TOKENS_FILE"

# Test token creation
_raw=$(_auth_create_token_internal "test-token" "admin")
_test "token creation returns non-empty" test -n "$_raw"

# Test token length (64 hex chars = 32 bytes)
_len=${#_raw}
_test_eq "token is 64 hex chars" "64" "$_len"

# Test duplicate rejection
_dup_result=$(_auth_create_token_internal "test-token" "admin" 2>&1 || true)
_test_contains "duplicate name rejected" "already exists" "$_dup_result"

echo ""
echo "  Token validation"

# Test valid token
export MUSTER_TOKEN="$_raw"
_test "valid token validates" auth_validate_token

_test_eq "scope set to admin" "admin" "$AUTH_SCOPE"

# Test invalid token
export MUSTER_TOKEN="invalid_token_value"
_invalid_result=0
auth_validate_token 2>/dev/null && _invalid_result=1 || _invalid_result=0
_test_eq "invalid token rejected" "0" "$_invalid_result"

echo ""
echo "  Token revocation"

export MUSTER_TOKEN="$_raw"
auth_revoke_token "test-token" >/dev/null 2>&1
_count=$(jq '.tokens | length' "$MUSTER_TOKENS_FILE")
_test_eq "token revoked (count=0)" "0" "$_count"

echo ""
echo "  Scope checking"

_test "read scope allows read" auth_check_scope "read" "read"
_test "deploy scope allows read" auth_check_scope "deploy" "read"
_test "admin scope allows deploy" auth_check_scope "admin" "deploy"

_deny1=0; auth_check_scope "read" "deploy" && _deny1=1 || _deny1=0
_test_eq "read scope denies deploy" "0" "$_deny1"

_deny2=0; auth_check_scope "deploy" "admin" && _deny2=1 || _deny2=0
_test_eq "deploy scope denies admin" "0" "$_deny2"

_test_summary
