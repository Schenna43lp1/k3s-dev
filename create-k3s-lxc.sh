#!/bin/bash
set -e

STORAGE="mvme01"
BRIDGE="vmbr0"
GW="192.168.1.1"

pveam update

TPL=$(pveam available | grep debian-13-standard | tail -1 | awk '{print $2}')

if ! pveam list local | grep -q debian-13-standard; then
    pveam download local $TPL
fi

TEMPLATE="local:vztmpl/$(basename $TPL)"

create_ct() {
VMID=$1
HOST=$2
IP=$3

pct create $VMID $TEMPLATE \
  -hostname $HOST \
  -ostype debian \
  -storage $STORAGE \
  -rootfs ${STORAGE}:50 \
  -cores 4 \
  -memory 4096 \
  -swap 0 \
  -password changeme \
  -unprivileged 1 \
  -features nesting=1,keyctl=1 \
  -net0 name=eth0,bridge=$BRIDGE,ip=${IP}/24,gw=$GW \
  -onboot 1 \
  -start 1

sleep 10
}

create_ct 701 k3s01 192.168.1.70
create_ct 702 k3s02 192.168.1.71
create_ct 703 k3s03 192.168.1.72

echo "LXCs erstellt"
