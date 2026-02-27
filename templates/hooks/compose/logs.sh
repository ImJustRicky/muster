#!/usr/bin/env bash
# Stream logs for {{SERVICE_NAME}} via Docker Compose

COMPOSE_FILE="${COMPOSE_FILE:-{{COMPOSE_FILE}}}"

docker compose -f "$COMPOSE_FILE" logs -f {{SERVICE_NAME}}
