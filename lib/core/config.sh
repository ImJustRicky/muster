#!/usr/bin/env bash
# muster/lib/core/config.sh — Read and write deploy.json

CONFIG_FILE=""

# Load config from deploy.json
load_config() {
  CONFIG_FILE=$(find_config) || {
    err "No deploy.json found. Run 'muster setup' first."
    exit 1
  }
}

# Read a value from deploy.json using jq or python fallback
config_get() {
  local query="$1"
  if has_cmd jq; then
    jq -r "$query" "$CONFIG_FILE"
  elif has_cmd python3; then
    python3 -c "
import json, sys
with open('$CONFIG_FILE') as f:
    data = json.load(f)
keys = '$query'.strip('.').split('.')
for k in keys:
    if k: data = data.get(k, '')
print(data if isinstance(data, str) else json.dumps(data))
"
  else
    err "jq or python3 required to read config"
    exit 1
  fi
}

# List service names from deploy.json
config_services() {
  if has_cmd jq; then
    jq -r '.services | keys[]' "$CONFIG_FILE"
  elif has_cmd python3; then
    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    data = json.load(f)
for k in data.get('services', {}):
    print(k)
"
  fi
}

# Write deploy.json from stdin
config_write() {
  local target="$1"
  cat > "$target"
}
