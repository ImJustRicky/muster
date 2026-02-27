#!/usr/bin/env bash
# Cleanup {{SERVICE_NAME}} via systemd

SERVICE="{{SERVICE_NAME}}"

echo "Cleaning old journal logs..."
sudo journalctl --vacuum-time=7d -u "${SERVICE}" 2>/dev/null || true

echo "Removing stale PID files..."
rm -f "/var/run/${SERVICE}.pid" 2>/dev/null || true

echo "${SERVICE} cleanup complete"
