#!/usr/bin/env bash
set -euo pipefail
# Rollback {{SERVICE_NAME}} (infrastructure) — restart via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"

echo "Restarting {{SERVICE_NAME}}..."
docker compose -f "$COMPOSE_FILE" stop {{SERVICE_NAME}}
docker compose -f "$COMPOSE_FILE" up -d {{SERVICE_NAME}}

echo "{{SERVICE_NAME}} restarted"
