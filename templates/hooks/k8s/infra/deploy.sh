#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} (infrastructure) to Kubernetes

NAMESPACE="${NAMESPACE:-{{NAMESPACE}}}"
SERVICE="{{SERVICE_NAME}}"
IMAGE="{{SERVICE_IMAGE}}"

# Apply manifests
echo "Applying Kubernetes manifests for ${SERVICE}..."
kubectl apply -f {{K8S_DIR}} -n "$NAMESPACE" 2>/dev/null || true

# Update deployment image (pull only, no build)
echo "Updating deployment to ${IMAGE}..."
kubectl set image deployment/${SERVICE} \
  ${SERVICE}="${IMAGE}" \
  -n "$NAMESPACE"

# Wait for rollout
echo "Waiting for rollout..."
kubectl rollout status deployment/${SERVICE} -n "$NAMESPACE" --timeout=120s

echo "${SERVICE} deployed"
