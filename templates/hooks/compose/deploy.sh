#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"

echo "Building {{SERVICE_NAME}}..."
docker compose -f "$COMPOSE_FILE" build {{SERVICE_NAME}}

echo "Starting {{SERVICE_NAME}}..."
docker compose -f "$COMPOSE_FILE" up -d {{SERVICE_NAME}}

echo "Waiting for container..."
sleep 3

echo "{{SERVICE_NAME}} deployed"
