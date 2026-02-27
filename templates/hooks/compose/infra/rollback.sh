#!/usr/bin/env bash
set -eo pipefail
# Rollback {{SERVICE_NAME}} (infrastructure) via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"

echo "Restarting {{SERVICE_NAME}}..."
docker compose -f "$COMPOSE_FILE" down {{SERVICE_NAME}}
docker compose -f "$COMPOSE_FILE" up -d {{SERVICE_NAME}}

echo "{{SERVICE_NAME}} rolled back"
