#!/usr/bin/env bash
# Stream logs for {{SERVICE_NAME}} on Kubernetes

NAMESPACE="${NAMESPACE:-{{NAMESPACE}}}"
SERVICE="{{SERVICE_NAME}}"

kubectl logs -n "$NAMESPACE" \
  -l app="${SERVICE}" \
  --all-containers \
  -f \
  --tail=100
