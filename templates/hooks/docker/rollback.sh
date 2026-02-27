#!/usr/bin/env bash
set -eo pipefail
# Rollback {{SERVICE_NAME}} via Docker

SERVICE="{{SERVICE_NAME}}"

echo "Stopping ${SERVICE}..."
docker stop "${SERVICE}" 2>/dev/null || true
docker rm "${SERVICE}" 2>/dev/null || true

# Restart with previous image
echo "Starting previous version..."
docker run -d \
  --name "${SERVICE}" \
  --restart unless-stopped \
  -p {{PORT}}:{{PORT}} \
  "${SERVICE}:previous" # TODO: adjust your rollback image tag

echo "${SERVICE} rolled back"
