#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} to Kubernetes

NAMESPACE="${MUSTER_K8S_NAMESPACE:-{{NAMESPACE}}}"
SERVICE="${MUSTER_K8S_SERVICE:-{{SERVICE_NAME}}}"
DEPLOY_NAME="${MUSTER_K8S_DEPLOYMENT:-{{K8S_DEPLOY_NAME}}}"
REGISTRY="${DOCKER_REGISTRY:-localhost:5000}"
TAG="${IMAGE_TAG:-latest}"

# Apply manifests
echo "Applying Kubernetes manifests..."
kubectl apply -f "{{K8S_DIR}}" -n "$NAMESPACE" 2>/dev/null || true

if [[ "${MUSTER_DEPLOY_MODE:-update}" == "restart" ]]; then
  # Restart only — uses image version from manifest
  echo "Restarting ${SERVICE}..."
  kubectl rollout restart "deployment/${DEPLOY_NAME}" -n "$NAMESPACE"
else
  # Build, push, and update image
  echo "Building ${SERVICE}..."
  docker build -t "${REGISTRY}/${SERVICE}:${TAG}" -f "{{DOCKERFILE}}" .

  echo "Pushing image..."
  docker push "${REGISTRY}/${SERVICE}:${TAG}"

  echo "Updating deployment..."
  kubectl set image "deployment/${DEPLOY_NAME}" \
    "${SERVICE}=${REGISTRY}/${SERVICE}:${TAG}" \
    -n "$NAMESPACE"
fi

# Wait for rollout
echo "Waiting for rollout..."
kubectl rollout status "deployment/${DEPLOY_NAME}" -n "$NAMESPACE" --timeout="${MUSTER_DEPLOY_TIMEOUT:-120}s"

echo "${SERVICE} deployed"
