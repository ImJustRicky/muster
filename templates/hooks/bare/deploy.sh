#!/usr/bin/env bash
set -euo pipefail
# Deploy {{SERVICE_NAME}} via systemd

SERVICE="{{SERVICE_NAME}}"
: "${SERVICE:?SERVICE is required}"

echo "Pulling latest code..."
git pull origin main # TODO: adjust branch if needed

echo "Building ${SERVICE}..."
# TODO: adjust build command for your project
# make build
# go build -o "${SERVICE}" .
# cargo build --release

echo "Restarting ${SERVICE}..."
sudo systemctl restart "${SERVICE}"

sleep 2
if systemctl is-active --quiet "${SERVICE}"; then
  echo "${SERVICE} deployed"
else
  echo "${SERVICE} failed to start"
  exit 1
fi
