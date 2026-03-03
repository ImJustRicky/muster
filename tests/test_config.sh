#!/usr/bin/env bash
# tests/test_config.sh — Tests for config loading and utilities
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MUSTER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helpers.sh"

# Minimal color stubs (no TTY in tests)
GREEN="" YELLOW="" RED="" RESET="" BOLD="" DIM="" ACCENT="" ACCENT_BRIGHT="" WHITE=""
MUSTER_QUIET="true"
MUSTER_VERBOSE="false"

source "$MUSTER_ROOT/lib/core/logger.sh"
source "$MUSTER_ROOT/lib/core/utils.sh"
source "$MUSTER_ROOT/lib/core/config.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  Config loading"

# Create a test deploy.json
cat > "${TMPDIR}/deploy.json" << 'EOF'
{
  "project": "test-app",
  "version": "1",
  "services": {
    "api": {
      "name": "API Server",
      "health": { "type": "http", "port": 8080, "endpoint": "/health" }
    },
    "redis": {
      "name": "Redis",
      "health": { "type": "tcp", "port": 6379 }
    },
    "my-svc": {
      "name": "My Service"
    }
  },
  "deploy_order": ["redis", "api"]
}
EOF

CONFIG_FILE="${TMPDIR}/deploy.json"

# Test config_get
_proj=$(config_get '.project')
_test_eq "config_get reads project name" "test-app" "$_proj"

_ver=$(config_get '.version')
_test_eq "config_get reads version" "1" "$_ver"

# Test config_get nested
_health_type=$(config_get '.services.api.health.type')
_test_eq "config_get reads nested value" "http" "$_health_type"

# Test config_services
_svcs=$(config_services)
_test_contains "config_services lists api" "api" "$_svcs"
_test_contains "config_services lists redis" "redis" "$_svcs"

# Test _jq_quote for hyphenated keys
_quoted=$(_jq_quote ".services.my-svc.name")
_test_eq "_jq_quote wraps hyphenated segment" '.services["my-svc"].name' "$_quoted"

_plain=$(_jq_quote ".services.api.name")
_test_eq "_jq_quote passes simple segments unchanged" ".services.api.name" "$_plain"

# Test config_get with hyphenated key via bracket notation
_hyph_name=$(jq -r '.services["my-svc"].name' "$CONFIG_FILE")
_test_eq "jq bracket notation reads hyphenated key" "My Service" "$_hyph_name"

echo ""
echo "  Missing config"

# Test missing config file
CONFIG_FILE="${TMPDIR}/nonexistent.json"
_missing=$(config_get '.project' 2>/dev/null || echo "FAIL")
_test_eq "config_get returns empty for missing file" "FAIL" "$_missing"

_test_summary
