#!/usr/bin/env bash
# Cleanup stuck pods for {{SERVICE_NAME}} (infrastructure) on Kubernetes

NAMESPACE="${NAMESPACE:-{{NAMESPACE}}}"
SERVICE="{{SERVICE_NAME}}"

echo "Cleaning up failed pods..."
kubectl delete pods -n "$NAMESPACE" \
  -l app="${SERVICE}" \
  --field-selector=status.phase!=Running \
  2>/dev/null || true

echo "${SERVICE} cleanup complete"
