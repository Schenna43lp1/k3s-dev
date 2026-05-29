# 🚀 K3S HA Cluster Helper

Community-Scripts inspired Proxmox installer for a complete K3s High Availability cluster with monitoring.

---

# ✨ Features

## 🖥 VM Deployment

Automatic deployment of:

| VMID | Hostname | Role | RAM |
|---|---|---|---:|
| 701 | k3s01 | Control Plane + etcd | 4GB |
| 702 | k3s02 | Control Plane + etcd | 4GB |
| 703 | k3s03 | Control Plane + etcd | 4GB |
| 704 | k3s04 | Worker | 8GB |
| 705 | k3s05 | Worker | 8GB |

---

# ⚙ Included

## Cloud-Init

- Debian 13 Cloud Image
- SSH-Key Deployment
- Static Networking
- Auto Boot
- QEMU Guest Agent

## Base Provisioning

- apt update + upgrade
- curl
- git
- jq
- htop
- iptables / nftables
- open-iscsi
- nfs-common
- dnsutils
- guest-agent enable

## K3s HA

- 3 Control Plane Nodes
- Embedded etcd
- 2 Worker Nodes
- Auto Node Join
- Worker Labels
- KUBECONFIG Export
- kubectl Alias

## Monitoring Stack

- Helm
- kube-prometheus-stack
- Grafana
- Prometheus
- Alertmanager
- Node Exporter
- Final Validation Report

---

# 🌐 Network Layout

| Host | IP |
|---|---|
| k3s01 | 192.168.1.70 |
| k3s02 | 192.168.1.71 |
| k3s03 | 192.168.1.72 |
| k3s04 | 192.168.1.73 |
| k3s05 | 192.168.1.74 |

Gateway:

```text
192.168.1.1
```

---

# 📦 Requirements

Proxmox:

- Proxmox VE 8+
- Storage: mvme01
- Bridge: vmbr0

Debian cloud image:

```bash
wget -O /var/lib/vz/template/iso/debian-13-genericcloud-amd64.qcow2 \
https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
```

---

# ▶ Installation

```bash
chmod +x create-k3s-cluster.sh
./create-k3s-cluster.sh
```

---

# ✅ Final Result

After installation:

- 5-node K3s cluster
- HA Control Plane
- Worker nodes labeled
- Traefik enabled
- Monitoring installed
- Grafana password output
- Final readiness validation

---

# 🎯 Community-Script Style

Inspired by tteck/community-scripts.

One script.
One command.
Ready cluster.
