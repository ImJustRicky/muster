#!/usr/bin/env bash
# Stream logs for {{SERVICE_NAME}} on Kubernetes

NAMESPACE="${MUSTER_K8S_NAMESPACE:-{{NAMESPACE}}}"
DEPLOY_NAME="${MUSTER_K8S_DEPLOYMENT:-{{K8S_DEPLOY_NAME}}}"

kubectl logs -n "$NAMESPACE" \
  "deployment/${DEPLOY_NAME}" \
  --all-containers \
  -f \
  --tail=100
