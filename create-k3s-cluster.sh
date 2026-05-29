#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.4.0"
STORAGE="mvme01"
BRIDGE="vmbr0"
GATEWAY="192.168.1.1"
CLOUD_IMAGE="debian-13-genericcloud-amd64.qcow2"
SSH_KEY="${HOME}/.ssh/id_ed25519.pub"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

NODES=(
  "701:k3s01:4096:192.168.1.70"
  "702:k3s02:4096:192.168.1.71"
  "703:k3s03:4096:192.168.1.72"
  "704:k3s04:8192:192.168.1.73"
  "705:k3s05:8192:192.168.1.74"
)

info(){ echo "[INFO] $*"; }
success(){ echo "[OK] $*"; }
error(){ echo "[ERROR] $*" >&2; }

require_root(){ [[ "$EUID" -eq 0 ]] || { error "Run as root"; exit 1; }; }

check_cloud_image(){
  [[ -f /var/lib/vz/template/iso/${CLOUD_IMAGE} ]] || {
    error "Missing cloud image"
    echo "Download: wget -O /var/lib/vz/template/iso/${CLOUD_IMAGE} https://cloud.debian.org/images/cloud/trixie/latest/${CLOUD_IMAGE}"
    exit 1
  }
}

check_ssh_key(){
  info "Checking SSH key"
  [[ -f ${SSH_KEY} ]] || ssh-keygen -t ed25519 -N "" -f "${HOME}/.ssh/id_ed25519"
  success "SSH key ready"
}

create_vm(){
  ID=$1; NAME=$2; RAM=$3; IP=$4
  if qm status "$ID" >/dev/null 2>&1; then
    info "VM ${ID} exists, skipping"
    return
  fi
  info "Creating ${NAME} (${ID})"
  qm create "$ID" --name "$NAME" --memory "$RAM" --cores 4 --cpu host --net0 virtio,bridge=${BRIDGE} --agent enabled=1 --ostype l26
  qm importdisk "$ID" /var/lib/vz/template/iso/${CLOUD_IMAGE} ${STORAGE}
  qm set "$ID" --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${ID}-disk-0 --ide2 ${STORAGE}:cloudinit --boot order=scsi0 --ciuser root --sshkeys ${SSH_KEY} --ipconfig0 ip=${IP}/24,gw=${GATEWAY} --onboot 1
  qm start "$ID"
  success "${NAME} ready + started"
}

wait_for_ssh(){
  IP=$1; NAME=$2
  info "Waiting for SSH on ${NAME} (${IP})"
  for i in {1..60}; do
    if ssh ${SSH_OPTS} root@${IP} "echo ok" >/dev/null 2>&1; then
      success "SSH ready on ${NAME}"
      return
    fi
    sleep 5
  done
  error "SSH not ready on ${NAME}"
  exit 1
}

provision_node(){
  IP=$1; NAME=$2
  info "Provisioning ${NAME}"
  ssh ${SSH_OPTS} root@${IP} "export DEBIAN_FRONTEND=noninteractive; apt update && apt -y upgrade && apt install -y qemu-guest-agent curl git jq htop iptables nftables open-iscsi nfs-common ca-certificates gnupg lsb-release net-tools dnsutils"
  ssh ${SSH_OPTS} root@${IP} "systemctl enable --now qemu-guest-agent || true"
  success "${NAME} provisioned"
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

  info "STEP 4: VM Creation + Base Provisioning"

  for node in "${NODES[@]}"; do
    IFS=":" read -r ID NAME RAM IP <<< "$node"
    create_vm "$ID" "$NAME" "$RAM" "$IP"
  done

  for node in "${NODES[@]}"; do
    IFS=":" read -r ID NAME RAM IP <<< "$node"
    wait_for_ssh "$IP" "$NAME"
    provision_node "$IP" "$NAME"
  done

  success "Step 4 complete"
}

main "$@"
