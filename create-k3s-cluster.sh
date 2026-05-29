#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="K3s HA Cluster Helper"
VERSION="0.8.0"

STORAGE="mvme01"
BRIDGE="vmbr0"
GATEWAY="192.168.1.1"
CLOUD_IMAGE="debian-13-genericcloud-amd64.qcow2"
SSH_KEY="${HOME}/.ssh/id_ed25519.pub"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
MASTER_IP="192.168.1.70"

NODES=(
  "701:k3s01:4096:192.168.1.70:server-init"
  "702:k3s02:4096:192.168.1.71:server"
  "703:k3s03:4096:192.168.1.72:server"
  "704:k3s04:8192:192.168.1.73:agent"
  "705:k3s05:8192:192.168.1.74:agent"
)

info(){ echo "[INFO] $*"; }
success(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
error(){ echo "[ERROR] $*" >&2; }

require_root(){
  [[ "$EUID" -eq 0 ]] || { error "Run this script as root on the Proxmox host"; exit 1; }
}

check_commands(){
  for cmd in qm ssh wget; do
    command -v "$cmd" >/dev/null 2>&1 || { error "Missing command: $cmd"; exit 1; }
  done
}

check_cloud_image(){
  if [[ ! -f /var/lib/vz/template/iso/${CLOUD_IMAGE} ]]; then
    error "Missing cloud image: /var/lib/vz/template/iso/${CLOUD_IMAGE}"
    echo "Download it with:"
    echo "wget -O /var/lib/vz/template/iso/${CLOUD_IMAGE} https://cloud.debian.org/images/cloud/trixie/latest/${CLOUD_IMAGE}"
    exit 1
  fi
  success "Debian cloud image found"
}

check_ssh_key(){
  info "Checking SSH key"
  if [[ ! -f ${SSH_KEY} ]]; then
    ssh-keygen -t ed25519 -N "" -f "${HOME}/.ssh/id_ed25519"
  fi
  success "SSH key ready"
}

create_vm(){
  local ID=$1 NAME=$2 RAM=$3 IP=$4

  if qm status "$ID" >/dev/null 2>&1; then
    info "VM ${ID} (${NAME}) already exists, skipping creation"
    return
  fi

  info "Creating VM ${ID} (${NAME})"

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
  success "${NAME} created and started"
}

wait_for_ssh(){
  local IP=$1 NAME=$2
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
  local IP=$1
  shift
  ssh ${SSH_OPTS} root@${IP} "$@"
}

run_master(){
  run_remote "${MASTER_IP}" "$@"
}

provision_node(){
  local IP=$1 NAME=$2
  info "Provisioning ${NAME}"

  run_remote "$IP" "export DEBIAN_FRONTEND=noninteractive; apt update && apt -y upgrade && apt install -y qemu-guest-agent curl git jq htop iptables nftables open-iscsi nfs-common ca-certificates gnupg lsb-release net-tools dnsutils"
  run_remote "$IP" "systemctl enable --now qemu-guest-agent || true"

  success "${NAME} provisioned"
}

install_k3s_init(){
  info "Installing first control plane on k3s01"

  if run_master "test -x /usr/local/bin/k3s" >/dev/null 2>&1; then
    warn "K3s already installed on k3s01, skipping init"
    return
  fi

  run_master "curl -sfL https://get.k3s.io | sh -s - server --cluster-init --write-kubeconfig-mode 644 --node-name k3s01"
  run_master "grep -q KUBECONFIG /root/.bashrc || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc"
  run_master "grep -q 'alias kubectl' /root/.bashrc || echo 'alias kubectl=\"k3s kubectl\"' >> /root/.bashrc"

  success "k3s01 initialized"
}

get_node_token(){
  run_master "cat /var/lib/rancher/k3s/server/node-token"
}

join_server(){
  local IP=$1 NAME=$2 TOKEN=$3
  info "Joining ${NAME} as control plane"

  if run_remote "$IP" "test -x /usr/local/bin/k3s" >/dev/null 2>&1; then
    warn "K3s already installed on ${NAME}, skipping"
    return
  fi

  run_remote "$IP" "curl -sfL https://get.k3s.io | K3S_TOKEN='${TOKEN}' sh -s - server --server https://${MASTER_IP}:6443 --write-kubeconfig-mode 644 --node-name ${NAME}"
  success "${NAME} joined as control plane"
}

join_agent(){
  local IP=$1 NAME=$2 TOKEN=$3
  info "Joining ${NAME} as worker"

  if run_remote "$IP" "test -x /usr/local/bin/k3s" >/dev/null 2>&1; then
    warn "K3s already installed on ${NAME}, skipping"
    return
  fi

  run_remote "$IP" "curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN='${TOKEN}' sh -s - agent --node-name ${NAME}"
  success "${NAME} joined as worker"
}

wait_for_nodes(){
  info "Waiting for Kubernetes nodes"

  for i in {1..80}; do
    if run_master "KUBECONFIG=/etc/rancher/k3s/k3s.yaml k3s kubectl get nodes | grep -q k3s05" >/dev/null 2>&1; then
      success "All nodes registered"
      return
    fi
    sleep 5
  done

  error "Nodes did not register in time"
  run_master "KUBECONFIG=/etc/rancher/k3s/k3s.yaml k3s kubectl get nodes || true"
  exit 1
}

label_workers(){
  info "Applying worker labels"
  run_master "KUBECONFIG=/etc/rancher/k3s/k3s.yaml k3s kubectl label node k3s04 node-role.kubernetes.io/worker=worker --overwrite"
  run_master "KUBECONFIG=/etc/rancher/k3s/k3s.yaml k3s kubectl label node k3s05 node-role.kubernetes.io/worker=worker --overwrite"
  success "Worker labels applied"
}

install_k3s_cluster(){
  install_k3s_init
  sleep 20

  local TOKEN
  TOKEN=$(get_node_token)

  join_server "192.168.1.71" "k3s02" "$TOKEN"
  join_server "192.168.1.72" "k3s03" "$TOKEN"
  join_agent "192.168.1.73" "k3s04" "$TOKEN"
  join_agent "192.168.1.74" "k3s05" "$TOKEN"

  wait_for_nodes
  label_workers
}

install_monitoring(){
  info "Installing Helm"
  run_master "command -v helm >/dev/null 2>&1 || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

  info "Adding Helm repos"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true; helm repo update"

  info "Creating monitoring namespace"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; k3s kubectl create namespace monitoring --dry-run=client -o yaml | k3s kubectl apply -f -"

  info "Installing kube-prometheus-stack"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --wait --timeout 20m"

  success "Monitoring stack installed"
}

final_report(){
  info "Final cluster report"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; k3s kubectl get nodes -o wide"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; k3s kubectl get pods -A"

  echo
  echo "Grafana admin password:"
  run_master "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; k3s kubectl get secret monitoring-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true; echo"
  echo

  success "Cluster setup complete"
}

main(){
  clear || true
  echo "======================================"
  echo " ${APP_NAME} ${VERSION}"
  echo "======================================"
  echo

  require_root
  check_commands
  check_cloud_image
  check_ssh_key

  info "STEP 1-3: VM Creation + Cloud-Init"
  for node in "${NODES[@]}"; do
    IFS=":" read -r ID NAME RAM IP ROLE <<< "$node"
    create_vm "$ID" "$NAME" "$RAM" "$IP"
  done

  info "STEP 4: Base Provisioning"
  for node in "${NODES[@]}"; do
    IFS=":" read -r ID NAME RAM IP ROLE <<< "$node"
    wait_for_ssh "$IP" "$NAME"
    provision_node "$IP" "$NAME"
  done

  info "STEP 5: K3s HA Bootstrap"
  install_k3s_cluster

  info "STEP 6: Monitoring Stack"
  install_monitoring

  final_report
}

main "$@"
