#!/usr/bin/env bash
# Stream logs for {{SERVICE_NAME}} (infrastructure) on Kubernetes

NAMESPACE="${NAMESPACE:-{{NAMESPACE}}}"
SERVICE="{{SERVICE_NAME}}"

kubectl logs -n "$NAMESPACE" \
  -l app="${SERVICE}" \
  --all-containers \
  -f \
  --tail=100
