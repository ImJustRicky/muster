#!/usr/bin/env bash
set -eo pipefail
# Rollback {{SERVICE_NAME}} (infrastructure) on Kubernetes

NAMESPACE="${NAMESPACE:-{{NAMESPACE}}}"
SERVICE="{{SERVICE_NAME}}"

echo "Rolling back ${SERVICE}..."
kubectl rollout undo deployment/${SERVICE} -n "$NAMESPACE"

echo "Waiting for rollback..."
kubectl rollout status deployment/${SERVICE} -n "$NAMESPACE" --timeout=120s

echo "${SERVICE} rolled back"
