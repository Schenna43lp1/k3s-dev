#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.7.0"
MASTER_IP="192.168.1.70"

info(){ echo "[INFO] $*"; }
success(){ echo "[OK] $*"; }
error(){ echo "[ERROR] $*"; }

run_master(){
  ssh -o StrictHostKeyChecking=no root@${MASTER_IP} "$@"
}

install_monitoring(){
  info "Installing Helm"
  run_master 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'

  info "Adding Helm repos"
  run_master 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update'

  info "Creating monitoring namespace"
  run_master 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -'

  info "Installing kube-prometheus-stack"
  run_master 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --wait --timeout 20m'

  info "Getting Grafana password"
  run_master 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d && echo'

  info "Validation"
  run_master 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get nodes && kubectl get pods -A'
}

main(){
  clear || true
  echo "======================================"
  echo " ${APP_NAME} ${VERSION}"
  echo "======================================"
  echo

  info "FULL Step 5 restore in progress"
  info "REAL Step 6 Monitoring"

  install_monitoring

  success "Monitoring stack installed"
}

main "$@"
