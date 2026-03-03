#!/usr/bin/env bash
set -euo pipefail
# Deploy {{SERVICE_NAME}} (infrastructure) via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"
: "${COMPOSE_FILE:?COMPOSE_FILE is required}"

echo "Starting {{SERVICE_NAME}}..."
docker compose -f "$COMPOSE_FILE" up -d {{SERVICE_NAME}}

echo "Waiting for container..."
sleep 3

echo "{{SERVICE_NAME}} started"
