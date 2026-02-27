#!/usr/bin/env bash
# Cleanup {{SERVICE_NAME}} — kill process, remove PID + log files

SERVICE="{{SERVICE_NAME}}"
PID_FILE=".muster/pids/${SERVICE}.pid"
LOG_FILE=".muster/logs/${SERVICE}.log"

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "Stopping ${SERVICE} (PID ${pid})..."
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "Removed PID file"
fi

if [[ -f "$LOG_FILE" ]]; then
  rm -f "$LOG_FILE"
  echo "Removed log file"
fi

echo "${SERVICE} cleanup complete"
