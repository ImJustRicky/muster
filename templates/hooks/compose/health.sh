#!/usr/bin/env bash
# Health check for {{SERVICE_NAME}} via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"
SERVICE="{{SERVICE_NAME}}"

# Check if container is running
if ! docker compose -f "$COMPOSE_FILE" ps "$SERVICE" 2>/dev/null | grep -q "running\|Up"; then
  exit 1
fi

exit 0
