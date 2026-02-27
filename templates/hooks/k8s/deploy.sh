#!/usr/bin/env bash
set -eo pipefail
# Deploy {{SERVICE_NAME}} to Kubernetes

NAMESPACE="${NAMESPACE:-{{NAMESPACE}}}"
SERVICE="{{SERVICE_NAME}}"
REGISTRY="${DOCKER_REGISTRY:-localhost:5000}"
TAG="${IMAGE_TAG:-latest}"

# Build Docker image
echo "Building ${SERVICE}..."
docker build -t "${REGISTRY}/${SERVICE}:${TAG}" . # TODO: adjust build context/Dockerfile path

# Push to registry
echo "Pushing image..."
docker push "${REGISTRY}/${SERVICE}:${TAG}"

# Apply manifests
echo "Applying Kubernetes manifests..."
kubectl apply -f k8s/${SERVICE}/ -n "$NAMESPACE" 2>/dev/null || true

# Update deployment image
echo "Updating deployment..."
kubectl set image deployment/${SERVICE} \
  ${SERVICE}="${REGISTRY}/${SERVICE}:${TAG}" \
  -n "$NAMESPACE"

# Wait for rollout
echo "Waiting for rollout..."
kubectl rollout status deployment/${SERVICE} -n "$NAMESPACE" --timeout=120s

echo "${SERVICE} deployed"
