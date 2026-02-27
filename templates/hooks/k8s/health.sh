#!/usr/bin/env bash
# Health check for {{SERVICE_NAME}} on Kubernetes

NAMESPACE="${NAMESPACE:-{{NAMESPACE}}}"
SERVICE="{{SERVICE_NAME}}"

# Check pod readiness
kubectl wait --for=condition=Ready pod \
  -l app="${SERVICE}" \
  -n "$NAMESPACE" \
  --timeout=10s &>/dev/null || exit 1

exit 0
