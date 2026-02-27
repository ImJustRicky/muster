#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} (infrastructure) via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"

echo "Pulling {{SERVICE_NAME}} image..."
docker compose -f "$COMPOSE_FILE" pull {{SERVICE_NAME}}

echo "Starting {{SERVICE_NAME}}..."
docker compose -f "$COMPOSE_FILE" up -d {{SERVICE_NAME}}

echo "Waiting for container..."
sleep 3

echo "{{SERVICE_NAME}} deployed"
