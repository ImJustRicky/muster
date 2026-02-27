#!/usr/bin/env bash
# Cleanup {{SERVICE_NAME}} via Docker

echo "Removing stopped containers..."
docker rm "{{SERVICE_NAME}}" 2>/dev/null || true

echo "Pruning dangling images..."
docker image prune -f >/dev/null 2>&1 || true

echo "{{SERVICE_NAME}} cleanup complete"
