#!/bin/bash

# Only allow script to run as
if [ "$(whoami)" != "root" ]; then
  echo "This script needs to be run as root. Try again with 'sudo $0'"
  exit 1
fi

echo
echo -n "Namespace name [piaVPN]: "
read -r NETNS_NAME
NETNS_NAME=${NETNS_NAME:-piaVPN} # sets default name
export NETNS_NAME

echo
echo -n "IP address and netmask of namespace network [192.168.255.0/24]: "
read -r ADDR_NET
ADDR_NET=${ADDR_NET:-192.168.255.0/24} # set default network
export ADDR_NET

# Check if namespace already exists
if ip netns list | grep -q "$NETNS_NAME"; then
  echo Namespace already exits, aborting.
  exit 1
fi

# name of the default interface to connect to the Internet
iface_default=$(route | grep '^default' | grep -o '[^ ]*$')

# name of paired interfaces
iface_local="$NETNS_NAME-veth0"
iface_peer="$NETNS_NAME-veth1"

# IP address of interfaces, can be any private IP address range in the same subnet
addr_local=$(sed -r 's|[0-9]+/|1/|' <<< "$ADDR_NET")
addr_peer=$(sed -r 's|[0-9]+/|2/|' <<< "$ADDR_NET")

# Set correct nameserver for DNS
mkdir -p "/etc/netns/$NETNS_NAME"
# we can change the following line to any DNS server, including PIAs
echo "nameserver 1.1.1.1" > "/etc/netns/$NETNS_NAME/resolv.conf"

# create namespace
ip netns add "$NETNS_NAME"

# creates the interfaces
ip link add name "$iface_local" type veth peer name "$iface_peer" netns "$NETNS_NAME"

# assign addresses and start interfaces
ip addr add "$addr_local" dev "$iface_local"
ip link set "$iface_local" up
ip netns exec "$NETNS_NAME" ip addr add "$addr_peer" dev "$iface_peer"
ip -n "$NETNS_NAME" link set "$iface_peer" up
ip -n "$NETNS_NAME" link set lo up

# adds default route inside namespace
ip -n "$NETNS_NAME" route add default via "${addr_local%/*}"

# Forward traffic
iptables -t nat -A POSTROUTING -s "$ADDR_NET" -o "$iface_default" -j MASQUERADE
iptables -A FORWARD -i "$iface_default" -o "$iface_local" -j ACCEPT
iptables -A FORWARD -o "$iface_default" -i "$iface_local" -j ACCEPT

echo Namespace and rules created succesfully.
echo You can now start the VPN by running this command:
echo
echo ip netns exec $NETNS_NAME ./run_setup.sh
echo
echo Only programs started inside the namespace will use the VPN connection
echo
echo Example:
echo ip netns exec $NETNS_NAME firefox
