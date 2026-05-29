#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.1.0"

info() {
  echo "[INFO] $*"
}

success() {
  echo "[OK] $*"
}

error() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "Please run this script as root on the Proxmox host."
    exit 1
  fi
}

main() {
  clear || true
  echo "======================================"
  echo " ${APP_NAME} ${VERSION}"
  echo "======================================"
  echo
  require_root
  info "Base helper ready. Next commits will add VM creation, cloud-init, K3s, and monitoring."
}

main "$@"
