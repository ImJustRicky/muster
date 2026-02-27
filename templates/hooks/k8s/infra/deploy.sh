#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} (infrastructure) to Kubernetes

NAMESPACE="${MUSTER_K8S_NAMESPACE:-{{NAMESPACE}}}"
SERVICE="${MUSTER_K8S_SERVICE:-{{SERVICE_NAME}}}"
DEPLOY_NAME="${MUSTER_K8S_DEPLOYMENT:-{{K8S_DEPLOY_NAME}}}"

# Apply manifests (picks up any image/config changes in YAML)
echo "Applying Kubernetes manifests for ${SERVICE}..."
kubectl apply -f {{K8S_DIR}} -n "$NAMESPACE" 2>/dev/null || true

# Restart deployment (uses image version from manifest, not :latest)
echo "Restarting ${SERVICE}..."
kubectl rollout restart "deployment/${DEPLOY_NAME}" -n "$NAMESPACE"

# Wait for rollout
echo "Waiting for rollout..."
kubectl rollout status "deployment/${DEPLOY_NAME}" -n "$NAMESPACE" --timeout="${MUSTER_DEPLOY_TIMEOUT:-120}s"

echo "${SERVICE} deployed"
