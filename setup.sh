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

mkdir -p ~/.ansible
cat > ~/.ansible.cfg <<EOF
[defaults]
host_key_checking=False
timeout=30
EOF

echo "=== Host Kernel Module ==="
modprobe br_netfilter || true
modprobe overlay || true
grep -q br_netfilter /etc/modules || echo br_netfilter >> /etc/modules
grep -q overlay /etc/modules || echo overlay >> /etc/modules

echo "=== SSH Cleanup ==="
rm -f /root/.ssh/known_hosts || true

echo "=== Erstelle LXCs ==="
chmod +x create-k3s-lxc.sh
./create-k3s-lxc.sh

echo "=== LXC Kubernetes Fixes ==="
for id in 701 702 703; do
  pct stop $id || true
  CONF="/etc/pve/lxc/$id.conf"

  grep -q "lxc.apparmor.profile: unconfined" "$CONF" || echo "lxc.apparmor.profile: unconfined" >> "$CONF"
  grep -q "lxc.apparmor.profile: unconfined" "$CONF" || echo "lxc.apparmor.allow_nesting: 1" >> "$CONF"
  grep -q "lxc.mount.auto: proc:rw sys:rw" "$CONF" || echo "lxc.mount.auto: proc:rw sys:rw" >> "$CONF"
  grep -q "/dev/kmsg dev/kmsg" "$CONF" || echo "lxc.mount.entry: /dev/kmsg dev/kmsg none bind,create=file,optional" >> "$CONF"

  pct start $id
  sleep 8
done

echo "=== SSH Vorbereitung ==="
if [ ! -f /root/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
fi

for ip in 192.168.1.70 192.168.1.71 192.168.1.72; do
  ssh-keyscan -H $ip >> /root/.ssh/known_hosts 2>/dev/null || true
  sshpass -p changeme ssh-copy-id -o StrictHostKeyChecking=no root@$ip || true
done

echo "=== Test SSH ==="
ssh root@192.168.1.70 hostname || true
ssh root@192.168.1.71 hostname || true
ssh root@192.168.1.72 hostname || true

echo "=== Deploy K3s Cluster via Ansible ==="
ansible-playbook -i inventory.ini site.yml

echo "=== Cluster Status ==="
ssh root@192.168.1.70 "kubectl get nodes -o wide" || true
ssh root@192.168.1.70 "kubectl get pods -A" || true

echo "=== FERTIG ==="
echo "Login: ssh root@192.168.1.70"
