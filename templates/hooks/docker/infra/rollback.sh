#!/usr/bin/env bash
set -eo pipefail
# Rollback {{SERVICE_NAME}} (infrastructure) via Docker

SERVICE="{{SERVICE_NAME}}"
IMAGE="{{SERVICE_IMAGE}}"

echo "Stopping ${SERVICE}..."
docker stop "${SERVICE}" 2>/dev/null || true
docker rm "${SERVICE}" 2>/dev/null || true

# Restart with same image
echo "Restarting ${SERVICE}..."
docker run -d \
  --name "${SERVICE}" \
  --restart unless-stopped \
  -p {{PORT}}:{{PORT}} \
  "${IMAGE}"

echo "${SERVICE} rolled back"
