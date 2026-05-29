# K3S HA Cluster Helper

Community-style Proxmox installer for automated K3s HA clusters.

## Features

### VM Deployment

Automatic creation:

- 701 k3s01 (control-plane + etcd)
- 702 k3s02 (control-plane + etcd)
- 703 k3s03 (control-plane + etcd)
- 704 k3s04 (worker)
- 705 k3s05 (worker)

## Included

- Debian 13 Cloud-Init
- SSH Key Automation
- Base Provisioning
- K3s HA Bootstrap
- 3 Control Plane Nodes
- 2 Worker Nodes
- Worker Labels
- Cluster Validation

## Planned

- Helm
- Traefik Validation
- kube-prometheus-stack
- Grafana
- Prometheus
- Alertmanager
- Final READY Report

## Usage

```bash
chmod +x create-k3s-cluster.sh
./create-k3s-cluster.sh
```
