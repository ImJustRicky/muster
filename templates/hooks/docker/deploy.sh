#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} via Docker

SERVICE="{{SERVICE_NAME}}"
TAG="${IMAGE_TAG:-latest}"

echo "Building ${SERVICE}..."
docker build -t "${SERVICE}:${TAG}" . # TODO: adjust Dockerfile path if needed

echo "Stopping existing container..."
docker stop "${SERVICE}" 2>/dev/null || true
docker rm "${SERVICE}" 2>/dev/null || true

echo "Starting ${SERVICE}..."
docker run -d \
  --name "${SERVICE}" \
  --restart unless-stopped \
  -p {{PORT}}:{{PORT}} \
  "${SERVICE}:${TAG}"

sleep 2
echo "${SERVICE} deployed"
