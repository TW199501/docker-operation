#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

scripts=(
  "$PROJECT_ROOT/proxmox-k8s/k8s-cluster/create-cluster.sh"
  "$PROJECT_ROOT/proxmox-k8s/k8s-cluster/join-worker.sh"
  "$PROJECT_ROOT/proxmox-k8s/k8s-cluster/reset-cluster.sh"
  "$PROJECT_ROOT/proxmox-k8s/k8s-apps/deploy-app.sh"
)

for s in "${scripts[@]}"; do
  if [ -f "$s" ]; then
    bash -n "$s"
  fi
done
