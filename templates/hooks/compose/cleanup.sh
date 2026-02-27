#!/usr/bin/env bash
# Cleanup {{SERVICE_NAME}} via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"

echo "Removing stopped containers..."
docker compose -f "$COMPOSE_FILE" rm -f {{SERVICE_NAME}} 2>/dev/null || true

echo "{{SERVICE_NAME}} cleanup complete"
