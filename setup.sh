#!/bin/bash
set -e

echo "=== K3S DEV AUTO SETUP ==="

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen"
  exit 1
fi

echo "=== Installiere Pakete ==="
apt update
apt install -y ansible sshpass iptables nftables

echo "=== Host Kernel Module ==="
modprobe br_netfilter || true
modprobe overlay || true
grep -q br_netfilter /etc/modules || echo br_netfilter >> /etc/modules
grep -q overlay /etc/modules || echo overlay >> /etc/modules

echo "=== Erstelle LXCs ==="
chmod +x create-k3s-lxc.sh
./create-k3s-lxc.sh

echo "=== LXC Kubernetes Fixes ==="
for id in 701 702 703; do
  pct stop $id || true
  CONF="/etc/pve/lxc/$id.conf"

  grep -q "lxc.apparmor.profile: unconfined" "$CONF" || echo "lxc.apparmor.profile: unconfined" >> "$CONF"
  grep -q "^lxc.cap.drop:" "$CONF" || echo "lxc.cap.drop:" >> "$CONF"
  grep -q "lxc.mount.auto: proc:rw sys:rw" "$CONF" || echo "lxc.mount.auto: proc:rw sys:rw" >> "$CONF"
  grep -q "/dev/kmsg dev/kmsg" "$CONF" || echo "lxc.mount.entry: /dev/kmsg dev/kmsg none bind,create=file,optional" >> "$CONF"

  pct start $id
  sleep 5
done

echo "=== Warte auf Container Start ==="
sleep 20

echo "=== Test /dev/kmsg ==="
for id in 701 702 703; do
  echo "CT $id"
  pct exec $id -- timeout 2 cat /dev/kmsg | head || true
done

echo "=== SSH Vorbereitung ==="
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
fi

sshpass -p changeme ssh-copy-id -o StrictHostKeyChecking=no root@192.168.1.70 || true
sshpass -p changeme ssh-copy-id -o StrictHostKeyChecking=no root@192.168.1.71 || true
sshpass -p changeme ssh-copy-id -o StrictHostKeyChecking=no root@192.168.1.72 || true

echo "=== Cleanup alter K3s States ==="
pct exec 701 -- systemctl stop k3s || true
pct exec 702 -- /usr/local/bin/k3s-uninstall.sh || true
pct exec 703 -- /usr/local/bin/k3s-uninstall.sh || true
pct exec 702 -- rm -rf /var/lib/rancher /etc/rancher || true
pct exec 703 -- rm -rf /var/lib/rancher /etc/rancher || true
pct exec 701 -- rm -rf /var/lib/rancher/k3s/server/db/* || true
pct exec 701 -- rm -rf /var/lib/rancher/k3s/server/tls || true

echo "=== Cluster Reset k3s01 ==="
pct exec 701 -- sh -c 'k3s server --cluster-reset || true'
sleep 10
pct exec 701 -- systemctl start k3s || true
sleep 40

echo "=== Deploy K3s Cluster via Ansible ==="
ansible-playbook -i inventory.ini site.yml

echo "=== Cluster Status ==="
ssh root@192.168.1.70 "kubectl get nodes -o wide" || true
ssh root@192.168.1.70 "kubectl get pods -A" || true

echo "=== FERTIG ==="
echo "Login: ssh root@192.168.1.70"
