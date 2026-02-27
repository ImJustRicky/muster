#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} to Kubernetes

NAMESPACE="${MUSTER_K8S_NAMESPACE:-{{NAMESPACE}}}"
SERVICE="${MUSTER_K8S_SERVICE:-{{SERVICE_NAME}}}"
DEPLOY_NAME="${MUSTER_K8S_DEPLOYMENT:-{{K8S_DEPLOY_NAME}}}"
REGISTRY="${DOCKER_REGISTRY:-localhost:5000}"
TAG="${IMAGE_TAG:-latest}"

# Build Docker image
echo "Building ${SERVICE}..."
docker build -t "${REGISTRY}/${SERVICE}:${TAG}" -f "{{DOCKERFILE}}" .

# Push to registry
echo "Pushing image..."
docker push "${REGISTRY}/${SERVICE}:${TAG}"

# Apply manifests
echo "Applying Kubernetes manifests..."
kubectl apply -f "{{K8S_DIR}}" -n "$NAMESPACE" 2>/dev/null || true

# Update deployment image
echo "Updating deployment..."
kubectl set image "deployment/${DEPLOY_NAME}" \
  "${SERVICE}=${REGISTRY}/${SERVICE}:${TAG}" \
  -n "$NAMESPACE"

# Wait for rollout
echo "Waiting for rollout..."
kubectl rollout status "deployment/${DEPLOY_NAME}" -n "$NAMESPACE" --timeout="${MUSTER_DEPLOY_TIMEOUT:-120}s"

echo "${SERVICE} deployed"
