#!/bin/bash
set -e

echo "=== K3S DEV AUTO SETUP ==="

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen"
  exit 1
fi

echo "=== Installiere Ansible ==="
apt update
apt install -y ansible sshpass

echo "=== Erstelle LXCs ==="
chmod +x create-k3s-lxc.sh
./create-k3s-lxc.sh

echo "=== Warte auf Container Start ==="
sleep 30

echo "=== SSH Vorbereitung ==="
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
fi

sshpass -p changeme ssh-copy-id -o StrictHostKeyChecking=no root@192.168.1.70 || true
sshpass -p changeme ssh-copy-id -o StrictHostKeyChecking=no root@192.168.1.71 || true
sshpass -p changeme ssh-copy-id -o StrictHostKeyChecking=no root@192.168.1.72 || true

echo "=== Deploy K3s Cluster via Ansible ==="
ansible-playbook -i inventory.ini site.yml

echo "=== Cluster Status ==="
ssh root@192.168.1.70 "kubectl get nodes -o wide"
ssh root@192.168.1.70 "kubectl get pods -A"

echo "=== FERTIG ==="
echo "Login: ssh root@192.168.1.70"
