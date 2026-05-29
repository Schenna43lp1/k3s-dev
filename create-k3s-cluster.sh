#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.2.0"
STORAGE="mvme01"
BRIDGE="vmbr0"
CLOUD_IMAGE="debian-13-genericcloud-amd64.qcow2"

info(){ echo "[INFO] $*"; }
success(){ echo "[OK] $*"; }
error(){ echo "[ERROR] $*" >&2; }

require_root(){
  [[ "$EUID" -eq 0 ]] || { error "Run as root"; exit 1; }
}

check_cloud_image(){
  info "Checking Debian cloud image..."
  if [[ ! -f /var/lib/vz/template/iso/${CLOUD_IMAGE} ]]; then
    error "Missing cloud image: ${CLOUD_IMAGE}"
    echo "Download with:"
    echo "wget -O /var/lib/vz/template/iso/${CLOUD_IMAGE} https://cloud.debian.org/images/cloud/trixie/latest/${CLOUD_IMAGE}"
    exit 1
  fi
  success "Cloud image found"
}

create_vm(){
  ID=$1
  NAME=$2
  RAM=$3

  if qm status "$ID" >/dev/null 2>&1; then
    info "VM ${ID} exists, skipping"
    return
  fi

  info "Creating ${NAME} (${ID})"

  qm create "$ID" \
    --name "$NAME" \
    --memory "$RAM" \
    --cores 4 \
    --cpu host \
    --net0 virtio,bridge=${BRIDGE} \
    --agent enabled=1 \
    --ostype l26

  qm importdisk "$ID" /var/lib/vz/template/iso/${CLOUD_IMAGE} ${STORAGE}

  qm set "$ID" \
    --scsihw virtio-scsi-pci \
    --scsi0 ${STORAGE}:vm-${ID}-disk-0 \
    --ide2 ${STORAGE}:cloudinit \
    --boot order=scsi0

  success "${NAME} created"
}

main(){
  clear || true
  echo "======================================"
  echo " ${APP_NAME} ${VERSION}"
  echo "======================================"
  echo

  require_root
  check_cloud_image

  info "STEP 2: VM Creation"

  create_vm 701 k3s01 4096
  create_vm 702 k3s02 4096
  create_vm 703 k3s03 4096
  create_vm 704 k3s04 8192
  create_vm 705 k3s05 8192

  success "Step 2 complete"
}

main "$@"
