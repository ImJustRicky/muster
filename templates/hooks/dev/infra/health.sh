#!/usr/bin/env bash
# Health check for {{SERVICE_NAME}} (infrastructure) via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"

if ! docker compose -f "$COMPOSE_FILE" ps {{SERVICE_NAME}} 2>/dev/null | grep -qi "running\|Up"; then
  exit 1
fi

exit 0
