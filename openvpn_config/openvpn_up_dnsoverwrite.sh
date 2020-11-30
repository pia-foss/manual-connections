#!/bin/bash

# Write gateway IP for reference
echo $route_vpn_gateway > "$SCRIPTDIR"/route_info

# Back up resolv.conf and create new on with PIA DNS
cat /etc/resolv.conf > "$SCRIPTDIR"/resolv_conf_backup
echo "# Generated by /connect_to_openvpn_with_token.sh
nameserver 10.0.0.241" > /etc/resolv.conf
