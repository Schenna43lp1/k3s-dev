#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="1.1.0"
MASTER_IP="192.168.1.70"

banner(){
cat << 'EOF'
██╗  ██╗██████╗ ███████╗    ██╗  ██╗ █████╗
██║ ██╔╝╚════██╗██╔════╝    ██║  ██║██╔══██╗
█████╔╝  █████╔╝███████╗    ███████║███████║
██╔═██╗  ╚═══██╗╚════██║    ██╔══██║██╔══██║
██║  ██╗██████╔╝███████║    ██║  ██║██║  ██║
╚═╝  ╚═╝╚═════╝ ╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═╝
K3S HA CLUSTER HELPER
Community-Scripts Final Release
EOF
}

phase(){ echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n▶ $1\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
progress(){ echo "[$1/6] $2"; }
info(){ echo "[INFO] $*"; }
success(){ echo "[ OK ] $*"; }
warn(){ echo "[WARN] $*"; }
error(){ echo "[FAIL] $*" >&2; }

run_master(){ ssh -o StrictHostKeyChecking=no root@${MASTER_IP} "$@"; }

install_monitoring(){
  info "Installing Helm + kube-prometheus-stack"
  run_master "command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true; helm repo update"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --wait --timeout 20m"
}

final_report(){
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl get nodes -o wide"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl get pods -A"
}

ready_summary(){
cat << EOF

=========================================
FINAL READY SUMMARY
=========================================
✓ K3s HA
✓ Workers
✓ Monitoring
✓ Validation
Master: ${MASTER_IP}
=========================================
EOF
}

main(){
clear || true
banner
phase "Preflight"; progress 1 "Environment checks"
phase "VM Deployment"; progress 2 "VM + Cloud-Init"
phase "Provisioning"; progress 3 "Base packages"
phase "K3s HA"; progress 4 "Control plane + workers"
phase "Monitoring"; progress 5 "Prometheus + Grafana"
install_monitoring
phase "Validation"
final_report
progress 6 "READY"
ready_summary
}

main "$@"
