#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} (infrastructure) via Docker

SERVICE="{{SERVICE_NAME}}"
IMAGE="{{SERVICE_IMAGE}}"

echo "Pulling ${IMAGE}..."
docker pull "${IMAGE}"

echo "Stopping existing container..."
docker stop "${SERVICE}" 2>/dev/null || true
docker rm "${SERVICE}" 2>/dev/null || true

echo "Starting ${SERVICE}..."
docker run -d \
  --name "${SERVICE}" \
  --restart unless-stopped \
  -p {{PORT}}:{{PORT}} \
  "${IMAGE}"

sleep 2
echo "${SERVICE} deployed"
