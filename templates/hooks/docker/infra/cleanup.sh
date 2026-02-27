#!/usr/bin/env bash
# Cleanup {{SERVICE_NAME}} (infrastructure) via Docker

echo "Removing stopped containers..."
docker rm "{{SERVICE_NAME}}" 2>/dev/null || true

echo "{{SERVICE_NAME}} cleanup complete"
