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

# Quote path segments containing hyphens for jq
# .services.my-svc.name → .services["my-svc"].name
_jq_quote() {
  printf '%s' "$1" | sed -E 's/\.([a-zA-Z0-9_]*-[a-zA-Z0-9_-]*)/["\1"]/g'
}

# Read a value from deploy.json using jq or python fallback
config_get() {
  local query="$1"
  if has_cmd jq; then
    jq -r "$(_jq_quote "$query")" "$CONFIG_FILE"
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

# Set a value in deploy.json (requires jq)
config_set() {
  local path value="$2"
  path=$(_jq_quote "$1")
  if has_cmd jq; then
    local tmp="${CONFIG_FILE}.tmp"
    jq "$path = $value" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  else
    err "jq required to modify config"
    return 1
  fi
}
