#!/bin/bash

SCRIPTDIR=$(dirname $(realpath $BASH_SOURCE)/..)

# Remove process and route information when connection closes
rm -rf "$SCRIPTDIR"/pia_pid /opt/pia-manual/route_info

# Replace resolv.conf with original stored as backup
cat "$SCRIPTDIR"/resolv_conf_backup > /etc/resolv.conf
