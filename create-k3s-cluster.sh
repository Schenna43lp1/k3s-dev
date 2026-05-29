#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.3.0"
STORAGE="mvme01"
BRIDGE="vmbr0"
GATEWAY="192.168.1.1"
CLOUD_IMAGE="debian-13-genericcloud-amd64.qcow2"
SSH_KEY="${HOME}/.ssh/id_ed25519.pub"

info(){ echo "[INFO] $*"; }
success(){ echo "[OK] $*"; }
error(){ echo "[ERROR] $*" >&2; }

require_root(){ [[ "$EUID" -eq 0 ]] || { error "Run as root"; exit 1; }; }

check_cloud_image(){
  [[ -f /var/lib/vz/template/iso/${CLOUD_IMAGE} ]] || {
    error "Missing cloud image"
    exit 1
  }
}

check_ssh_key(){
  info "Checking SSH key"
  [[ -f ${SSH_KEY} ]] || {
    error "Missing SSH key: ${SSH_KEY}"
    exit 1
  }
  success "SSH key found"
}

create_vm(){
  ID=$1
  NAME=$2
  RAM=$3
  IP=$4

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
    --boot order=scsi0 \
    --ciuser root \
    --sshkeys ${SSH_KEY} \
    --ipconfig0 ip=${IP}/24,gw=${GATEWAY} \
    --onboot 1

  qm start "$ID"
  success "${NAME} ready + started"
}

main(){
  clear || true
  echo "======================================"
  echo " ${APP_NAME} ${VERSION}"
  echo "======================================"
  echo

  require_root
  check_cloud_image
  check_ssh_key

  info "STEP 3: Cloud-Init + Network"

  create_vm 701 k3s01 4096 192.168.1.70
  create_vm 702 k3s02 4096 192.168.1.71
  create_vm 703 k3s03 4096 192.168.1.72
  create_vm 704 k3s04 8192 192.168.1.73
  create_vm 705 k3s05 8192 192.168.1.74

  success "Step 3 complete"
}

main "$@"
