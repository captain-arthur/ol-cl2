#!/usr/bin/env bash
# UI에서 "Reset cluster" 한 뒤, 0.0.0.0 바인드(controller-manager/scheduler) 클러스터를 생성한다.
# 사용: ./scripts/kind-create-with-bind-address.sh
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/kind-config.yaml"

if ! command -v kind &>/dev/null; then
  echo "error: kind is not installed. Install from https://kind.sigs.k8s.io/"
  exit 1
fi

CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Deleting existing cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
fi

echo "Creating cluster with 0.0.0.0 bind (controller-manager, scheduler)..."
kind create cluster --config "${CONFIG}" --name "${CLUSTER_NAME}"

echo "Setting kubectl context to kind-${CLUSTER_NAME}..."
kubectl config use-context "kind-${CLUSTER_NAME}"

echo "Done. Cluster '${CLUSTER_NAME}' is ready with bind-address 0.0.0.0 for controller-manager and scheduler."
