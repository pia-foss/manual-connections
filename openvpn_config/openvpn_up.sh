#!/bin/bash

mkdir -p /var/opt/piavpn-manual
# Write gateway IP for reference
echo $route_vpn_gateway > /var/opt/piavpn-manual/route_info
