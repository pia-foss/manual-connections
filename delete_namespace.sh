#!/bin/bash

# Only allow script to run as
if [ "$(whoami)" != "root" ]; then
  echo "This script needs to be run as root. Try again with 'sudo $0'"
  exit 1
fi

if [ -z "$NETNS_NAME" ]; then
  echo Namespace name required, aborting.
  exit 1
fi

if [ -z "$ADDR_NET" ]; then
  echo IP address of namespace required, aborting.
  exit 1
fi

# name of the default interface to connect to the Internet
iface_default=$(route | grep '^default' | grep -o '[^ ]*$')

# name of paired interfaces
iface_local="$NETNS_NAME-veth0"

# deletes namespace, virtual interfaces associated with it, and iptables rules
ip netns delete "$NETNS_NAME"
ip link delete "$iface_local"
iptables -t nat -D POSTROUTING -s "$ADDR_NET" -o "$iface_default" -j MASQUERADE
iptables -D FORWARD -i "$iface_default" -o "$iface_local" -j ACCEPT
iptables -D FORWARD -o "$iface_default" -i "$iface_local" -j ACCEPT
