#!/bin/bash

# Remove process and route information when connection closes
rm -rf /var/run/piavpn-manual.pid /var/opt/piavpn-manual/route_info

# Replace resolv.conf with original stored as backup
cat /var/opt/piavpn-manual/resolv_conf_backup > /etc/resolv.conf
