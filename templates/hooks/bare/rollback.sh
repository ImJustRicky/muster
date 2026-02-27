#!/usr/bin/env bash
set -eo pipefail
# Rollback {{SERVICE_NAME}} via systemd

SERVICE="{{SERVICE_NAME}}"

echo "Rolling back ${SERVICE}..."
git checkout HEAD~1 # TODO: adjust rollback strategy

echo "Rebuilding..."
# TODO: adjust build command
# make build

echo "Restarting ${SERVICE}..."
sudo systemctl restart "${SERVICE}"

sleep 2
if systemctl is-active --quiet "${SERVICE}"; then
  echo "${SERVICE} rolled back"
else
  echo "${SERVICE} rollback failed"
  exit 1
fi
