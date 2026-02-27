#!/usr/bin/env bash
# Stream logs for {{SERVICE_NAME}}

SERVICE="{{SERVICE_NAME}}"
LOG_FILE=".muster/logs/${SERVICE}.log"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "No log file: ${LOG_FILE}"
  echo "Is ${SERVICE} running? Try: muster deploy"
  exit 1
fi

tail -f "$LOG_FILE"
