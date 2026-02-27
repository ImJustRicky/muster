#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} — start dev process in background

SERVICE="{{SERVICE_NAME}}"
PORT="{{PORT}}"
START_CMD="{{START_CMD}}"
PID_DIR=".muster/pids"
LOG_DIR=".muster/logs"

mkdir -p "$PID_DIR" "$LOG_DIR"

PID_FILE="${PID_DIR}/${SERVICE}.pid"
LOG_FILE="${LOG_DIR}/${SERVICE}.log"

# Kill existing process if running
if [[ -f "$PID_FILE" ]]; then
  old_pid=$(cat "$PID_FILE" 2>/dev/null)
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Stopping existing ${SERVICE} (PID ${old_pid})..."
    kill "$old_pid" 2>/dev/null || true
    sleep 1
    kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

echo "Starting ${SERVICE}: ${START_CMD}"
nohup bash -c "${START_CMD}" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 2

if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "${SERVICE} started (PID $(cat "$PID_FILE"), port ${PORT})"
else
  echo "${SERVICE} failed to start — last 20 lines:"
  tail -20 "$LOG_FILE"
  exit 1
fi
