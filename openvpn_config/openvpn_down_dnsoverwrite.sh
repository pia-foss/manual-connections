#!/usr/bin/env bash

# Remove process and route information when connection closes
rm -rf /opt/piavpn-manual/pia_pid /opt/pia-manual/route_info

# Replace resolv.conf with original stored as backup
cat /opt/piavpn-manual/resolv_conf_backup > /etc/resolv.conf
