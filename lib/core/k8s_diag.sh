#!/usr/bin/env bash
# muster/lib/core/k8s_diag.sh — K8s deploy failure diagnostics

# Run kubectl locally or via SSH for remote services
# Usage: _diag_run_kubectl "svc" "kubectl command string"
_diag_run_kubectl() {
  local svc="$1" cmd="$2"
  if remote_is_enabled "$svc"; then
    _remote_load_config "$svc"
    _remote_build_opts
    printf '%s\n' "$cmd" | ssh $_SSH_OPTS "${_REMOTE_USER}@${_REMOTE_HOST}" "bash -s" 2>/dev/null
  else
    bash -c "$cmd" 2>/dev/null
  fi
}

# Display a diagnosis line
_diag_show() {
  local diagnosis="$1" suggestion="$2"
  echo -e "  ${RED}*${RESET} ${BOLD}${diagnosis}${RESET}"
  echo -e "    ${DIM}${suggestion}${RESET}"
}

# Run k8s deploy failure diagnostics for a service
# Called after deploy/rollback failure, before the recovery menu
# Usage: k8s_diagnose_failure "svc"
k8s_diagnose_failure() {
  local svc="$1"
  local deployment="${MUSTER_K8S_DEPLOYMENT:-}"
  local namespace="${MUSTER_K8S_NAMESPACE:-default}"

  # Guard: only for k8s services with kubectl available
  [[ -z "$deployment" ]] && return 0
  [[ "$MUSTER_HAS_KUBECTL" != "true" ]] && return 0

  echo -e "  ${ACCENT}Diagnosing deploy failure...${RESET}"
  echo ""

  # Step 1: Describe the deployment (includes events, conditions, RS info)
  local deploy_desc
  deploy_desc=$(_diag_run_kubectl "$svc" "kubectl describe deployment ${deployment} -n ${namespace}")
  [[ -z "$deploy_desc" ]] && return 0

  # Step 2: Extract the new ReplicaSet name
  local new_rs
  new_rs=$(printf '%s\n' "$deploy_desc" | grep "NewReplicaSet:" | awk '{print $2}')

  local pod_name="" pod_desc="" pod_logs="" pod_prev_logs=""

  if [[ -n "$new_rs" && "$new_rs" != "<none>" ]]; then
    # Get pods list, then find the first pod from the new RS locally
    local _pods_output
    _pods_output=$(_diag_run_kubectl "$svc" "kubectl get pods -n ${namespace} --no-headers")

    if [[ -n "$_pods_output" ]]; then
      pod_name=$(printf '%s\n' "$_pods_output" | grep "^${new_rs}" | head -1 | awk '{print $1}')
    fi

    if [[ -n "$pod_name" ]]; then
      # Step 3: Describe the pod (events, conditions)
      pod_desc=$(_diag_run_kubectl "$svc" "kubectl describe pod ${pod_name} -n ${namespace}")

      # Step 4: Get pod logs (current + previous container)
      pod_logs=$(_diag_run_kubectl "$svc" "kubectl logs ${pod_name} -n ${namespace} --tail=30")
      pod_prev_logs=$(_diag_run_kubectl "$svc" "kubectl logs ${pod_name} -n ${namespace} --previous --tail=30")
    fi
  fi

  # Combine all output for pattern matching
  local all_output="${deploy_desc}
${pod_desc}
${pod_logs}
${pod_prev_logs}"

  local _diag_matched=false

  # ── Match known error patterns ──

  if printf '%s' "$all_output" | grep -qi "ImagePullBackOff\|ErrImagePull"; then
    _diag_matched=true
    _diag_show "Can't pull container image" \
      "Check registry auth, image name, and tag"
  fi

  if printf '%s' "$all_output" | grep -qi "OOMKilled"; then
    _diag_matched=true
    _diag_show "Out of memory (OOMKilled)" \
      "Increase memory limits in deployment spec"
  fi

  if printf '%s' "$all_output" | grep -qi "CrashLoopBackOff"; then
    _diag_matched=true
    _diag_show "Container keeps crashing (CrashLoopBackOff)" \
      "Check application logs and entrypoint config"
  fi

  if printf '%s' "$all_output" | grep -qi "Unschedulable"; then
    _diag_matched=true
    _diag_show "No node has enough capacity" \
      "Check node resources or scale up the cluster"
  fi

  if printf '%s' "$all_output" | grep -qi 'secret.*not found'; then
    _diag_matched=true
    _diag_show "Missing Kubernetes secret" \
      "Create the required secret before deploying"
  fi

  if printf '%s' "$all_output" | grep -qi 'persistentvolumeclaim.*not found'; then
    _diag_matched=true
    _diag_show "Missing PersistentVolumeClaim" \
      "Create the required PVC before deploying"
  fi

  if printf '%s' "$all_output" | grep -qi 'incompatible.*engine version\|version.*mismatch'; then
    _diag_matched=true
    _diag_show "Version mismatch" \
      "Pin to a compatible version or check migration docs"
  fi

  if [[ "$_diag_matched" == "false" ]]; then
    echo -e "  ${DIM}No specific error pattern detected (likely a timeout)${RESET}"
    if [[ -n "$pod_name" ]]; then
      echo -e "  ${DIM}Inspect: kubectl describe pod ${pod_name} -n ${namespace}${RESET}"
    else
      echo -e "  ${DIM}Inspect: kubectl describe deployment ${deployment} -n ${namespace}${RESET}"
    fi
  fi

  echo ""
}
