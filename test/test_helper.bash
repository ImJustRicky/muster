MUSTER_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Source core libs only (no TUI, no commands)
source "$MUSTER_ROOT/lib/core/colors.sh"
source "$MUSTER_ROOT/lib/core/logger.sh"
source "$MUSTER_ROOT/lib/core/utils.sh"
source "$MUSTER_ROOT/lib/core/config.sh"
source "$MUSTER_ROOT/lib/core/platform.sh"

setup() {
  TEST_TEMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TEMP"
}

# Helper: create a minimal deploy.json in TEST_TEMP
create_test_config() {
  cat > "$TEST_TEMP/deploy.json" << 'CONF'
{
  "project": "test-project",
  "deploy_order": ["api", "redis"],
  "services": {
    "api": {
      "name": "API Server",
      "skip_deploy": false,
      "health": { "enabled": true, "type": "http", "path": "/health", "port": 8080 },
      "credentials": { "enabled": false, "mode": "off" },
      "k8s": { "deployment": "test-api", "namespace": "production" },
      "deploy_timeout": 300,
      "deploy_mode": "update"
    },
    "redis": {
      "name": "Redis",
      "skip_deploy": false,
      "health": { "enabled": true, "type": "tcp", "port": 6379 },
      "credentials": { "enabled": false, "mode": "off" },
      "k8s": { "deployment": "test-redis", "namespace": "production" }
    },
    "my-worker": {
      "name": "My Worker",
      "skip_deploy": false,
      "health": { "enabled": false }
    }
  }
}
CONF
  CONFIG_FILE="$TEST_TEMP/deploy.json"
}
