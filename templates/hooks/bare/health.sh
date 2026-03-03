#!/usr/bin/env bash
set -euo pipefail
# Health check for {{SERVICE_NAME}} via systemd

SERVICE="{{SERVICE_NAME}}"
: "${SERVICE:?SERVICE is required}"

if systemctl is-active --quiet "${SERVICE}"; then
  exit 0
else
  exit 1
fi
