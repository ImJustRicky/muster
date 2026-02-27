#!/usr/bin/env bash
# Health check for {{SERVICE_NAME}} (infrastructure) via Docker

SERVICE="{{SERVICE_NAME}}"

# Check if container is running
if ! docker ps --filter "name=${SERVICE}" --format "{{{{.ID}}}}" | grep -q .; then
  exit 1
fi

exit 0
