#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.5.0"
STORAGE="mvme01"
BRIDGE="vmbr0"
GATEWAY="192.168.1.1"
CLOUD_IMAGE="debian-13-genericcloud-amd64.qcow2"
SSH_KEY="${HOME}/.ssh/id_ed25519.pub"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
K3S_VERSION=""

NODES=(
  "701:k3s01:4096:192.168.1.70:server-init"
  "702:k3s02:4096:192.168.1.71:server"
  "703:k3s03:4096:192.168.1.72:server"
  "704:k3s04:8192:192.168.1.73:agent"
  "705:k3s05:8192:192.168.1.74:agent"
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

run_remote(){
  IP=$1
  shift
  ssh ${SSH_OPTS} root@${IP} "$@"
}

provision_node(){
  IP=$1; NAME=$2
  info "Provisioning ${NAME}"
  run_remote "$IP" "export DEBIAN_FRONTEND=noninteractive; apt update && apt -y upgrade && apt install -y qemu-guest-agent curl git jq htop iptables nftables open-iscsi nfs-common ca-certificates gnupg lsb-release net-tools dnsutils"
  run_remote "$IP" "systemctl enable --now qemu-guest-agent || true"
  success "${NAME} provisioned"
}

install_k3s_init(){
  IP=$1
  info "Installing first control plane on ${IP}"
  run_remote "$IP" "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${K3S_VERSION}' sh -s - server --cluster-init --write-kubeconfig-mode 644 --node-name k3s01"
  run_remote "$IP" "echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc; echo 'alias kubectl=\"k3s kubectl\"' >> /root/.bashrc"
  success "k3s01 initialized"
}

get_node_token(){
  run_remote "192.168.1.70" "cat /var/lib/rancher/k3s/server/node-token"
}

join_server(){
  IP=$1; NAME=$2; TOKEN=$3
  info "Joining ${NAME} as control plane"
  run_remote "$IP" "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${K3S_VERSION}' K3S_TOKEN='${TOKEN}' sh -s - server --server https://192.168.1.70:6443 --write-kubeconfig-mode 644 --node-name ${NAME}"
  success "${NAME} joined as control plane"
}

join_agent(){
  IP=$1; NAME=$2; TOKEN=$3
  info "Joining ${NAME} as worker"
  run_remote "$IP" "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${K3S_VERSION}' K3S_URL=https://192.168.1.70:6443 K3S_TOKEN='${TOKEN}' sh -s - agent --node-name ${NAME}"
  success "${NAME} joined as worker"
}

wait_for_nodes(){
  info "Waiting for Kubernetes nodes"
  for i in {1..60}; do
    if run_remote "192.168.1.70" "k3s kubectl get nodes | grep -q k3s05" >/dev/null 2>&1; then
      success "All nodes registered"
      return
    fi
    sleep 5
  done
  error "Nodes did not register in time"
  run_remote "192.168.1.70" "k3s kubectl get nodes || true"
  exit 1
}

label_workers(){
  info "Applying worker labels"
  run_remote "192.168.1.70" "k3s kubectl label node k3s04 node-role.kubernetes.io/worker=worker --overwrite"
  run_remote "192.168.1.70" "k3s kubectl label node k3s05 node-role.kubernetes.io/worker=worker --overwrite"
  success "Worker labels applied"
}

install_k3s_cluster(){
  install_k3s_init "192.168.1.70"
  sleep 20
  TOKEN=$(get_node_token)
  join_server "192.168.1.71" "k3s02" "$TOKEN"
  join_server "192.168.1.72" "k3s03" "$TOKEN"
  join_agent "192.168.1.73" "k3s04" "$TOKEN"
  join_agent "192.168.1.74" "k3s05" "$TOKEN"
  wait_for_nodes
  label_workers
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

  info "STEP 5: VM Creation + Base Provisioning + K3s HA"

  for node in "${NODES[@]}"; do
    IFS=":" read -r ID NAME RAM IP ROLE <<< "$node"
    create_vm "$ID" "$NAME" "$RAM" "$IP"
  done

  for node in "${NODES[@]}"; do
    IFS=":" read -r ID NAME RAM IP ROLE <<< "$node"
    wait_for_ssh "$IP" "$NAME"
    provision_node "$IP" "$NAME"
  done

  install_k3s_cluster
  run_remote "192.168.1.70" "k3s kubectl get nodes -o wide"
  success "Step 5 complete"
}

main "$@"
