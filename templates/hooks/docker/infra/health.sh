#!/usr/bin/env bash
set -euo pipefail
# Health check for {{SERVICE_NAME}} (infrastructure) via Docker

SERVICE="{{SERVICE_NAME}}"
: "${SERVICE:?SERVICE is required}"

# Check if container is running
if ! docker ps --filter "name=${SERVICE}" --format "{{{{.ID}}}}" | grep -q .; then
  exit 1
fi

exit 0
