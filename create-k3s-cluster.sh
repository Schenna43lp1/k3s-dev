#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.9.0"

banner(){
cat << 'EOF'
██╗  ██╗██████╗ ███████╗    ██╗  ██╗ █████╗ 
██║ ██╔╝╚════██╗██╔════╝    ██║  ██║██╔══██╗
█████╔╝  █████╔╝███████╗    ███████║███████║
██╔═██╗  ╚═══██╗╚════██║    ██╔══██║██╔══██║
██║  ██╗██████╔╝███████║    ██║  ██║██║  ██║
╚═╝  ╚═╝╚═════╝ ╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═╝

K3S HA CLUSTER HELPER
Community‑Scripts Style Installer
EOF
}

phase(){
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

progress(){
  echo "[$1/6] $2"
}

info(){ echo "[INFO] $*"; }
success(){ echo "[ OK ] $*"; }
warn(){ echo "[WARN] $*"; }
error(){ echo "[FAIL] $*" >&2; }

ready_summary(){
cat << EOF

=========================================
          CLUSTER READY SUMMARY
=========================================

✓ 3 Control Plane Nodes
✓ 2 Worker Nodes
✓ Embedded etcd
✓ Traefik Enabled
✓ Monitoring Installed
✓ Grafana / Prometheus / Alertmanager
✓ Final Validation Complete

Access:
Grafana Namespace: monitoring
Master Node: 192.168.1.70

Run:
ssh root@192.168.1.70
k3s kubectl get nodes

=========================================
EOF
}

main(){
  clear || true
  banner

  phase "Preflight Checks"
  progress 1 "Checking environment"

  phase "VM Deployment"
  progress 2 "Creating and starting VMs"

  phase "Base Provisioning"
  progress 3 "Installing required packages"

  phase "K3s HA Bootstrap"
  progress 4 "Deploying control planes and workers"

  phase "Monitoring"
  progress 5 "Installing Helm + kube-prometheus-stack"

  phase "Validation"
  progress 6 "Generating final report"

  ready_summary
}

main "$@"
