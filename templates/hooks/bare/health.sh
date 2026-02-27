#!/usr/bin/env bash
# Health check for {{SERVICE_NAME}} via systemd

SERVICE="{{SERVICE_NAME}}"

if systemctl is-active --quiet "${SERVICE}"; then
  exit 0
else
  exit 1
fi
