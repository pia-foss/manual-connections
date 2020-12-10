#!/bin/bash

# Copyright (C) 2020 Private Internet Access, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Only allow script to run as
if [ "$(whoami)" != "root" ]; then
  echo "This script needs to be run as root. Try again with 'sudo $0'"
  exit 1
fi

# Erase previous authentication token if present
rm -f /opt/piavpn-manual/token /opt/piavpn-manual/latencyList

# This section asks for PIA user credentials
echo
echo -n "PIA username (pNNNNNNN): "
read PIA_USER

if [ -z "$PIA_USER" ]; then
  echo Username is required, aborting.
  exit 1
fi
echo
export PIA_USER

echo -n "PIA password: "
read -s PIA_PASS
echo

if [ -z "$PIA_PASS" ]; then
  echo Password is required, aborting.
  exit 1
fi
export PIA_PASS

echo -n "Checking login credentials..."
# Confirm MAX_LATENCY allowance, then confirm credentials and generate token
./get_token.sh

# If the script failed to generate an authentication token, the script will exit early.
tokenLocation=/opt/piavpn-manual/token
if [ ! -f "$tokenLocation" ]; then
  exit 1
fi

# This section asks for connection preferences that are
# relevant to manual server selection
echo -n "Do you want a forwarding port assigned ([N]o/[y]es): "
read portForwarding
echo

PIA_PF="false"
if echo ${portForwarding:0:1} | grep -iq y; then
  PIA_PF="true"
fi
export PIA_PF
echo PIA_PF=$PIA_PF

# Set this to the maximum allowed latency in seconds.
# All servers that respond slower than this will be ignored.
echo -n "
With no input, the maximum allowed latency will be set to 0.05s (50ms).
If your connection has high latency, you may need to increase this value.
For example, you can try 0.2 for 200ms allowed latency.
Custom latency (no input required for 50ms): "
read customLatency
echo

MAX_LATENCY=0.05
if [[ $customLatency != "" ]]; then
  MAX_LATENCY=$customLatency
fi
export MAX_LATENCY
echo "MAX_LATENCY=\"$MAX_LATENCY\"
"

# Prompt the user to specify a server or auto-connect to the lowest latency
echo
echo -n "Do you want to manually select a server, instead of auto-connecting to the
server with the lowest latency ([N]o/[y]es): "
read selectServer
echo

# Call the region script with input to create an ordered list based upon latency
# When $CONNECT_TO is set to false, get_region.sh will generate a list of servers
# that meet the latency requirements speciied by $MAX_LATENCY.
# When $PIA_AUTOCONNECT is set to no, get_region.sh will sort that list of servers
# to allow for numeric selection, or an easy manual review of options.
if echo ${selectServer:0:1} | grep -iq y; then
  CONNECT_TO="false"
  export CONNECT_TO
  PIA_AUTOCONNECT="no"
  export PIA_AUTOCONNECT
  ./get_region.sh
  
  # Output the ordered list of servers that meet the latency specification $MAX_LATENCY
  i=0
  while read line; do
    i=$((i+1))
    echo $i ":" $line
  done < /opt/piavpn-manual/latencyList
  
  # Receive input to specify the server to connect to manually
  echo
  echo -n "Input the number of the server you want to connect to ([1]-[$i]) : "
  read serverSelection
  echo

  if [[ -z "$serverSelection" ]]; then
    echo Invalid input, you must input the number of the server you want to connect to.
    exit 1
  else
    bestServer=$( awk 'NR == '$serverSelection' {print $4 $5}' /opt/piavpn-manual/latencyList )
    CONNECT_TO=$( awk 'NR == '$serverSelection' {print $2}' /opt/piavpn-manual/latencyList )
  fi
  
  # Write the serverID for use when connecting, and display the serverName for user confirmation
  export CONNECT_TO
  echo You will attempt to connect to $bestServer.
  echo
else
  echo You will auto-connect to the server with the lowest latency.
  echo
fi

# This section asks for user connection preferences
echo -n "Connection method ([W]ireguard/[o]penvpn): "
read connection_method
echo

PIA_AUTOCONNECT="wireguard"
if echo ${connection_method:0:1} | grep -iq o; then
  echo -n "Connection method ([U]dp/[t]cp): "
  read protocolInput
  echo

  protocol="udp"
  if echo ${protocolInput:0:1} | grep -iq t; then
    protocol="tcp"
  fi

  echo "Higher levels of encryption trade performance for security. "
  echo -n "Do you want to use strong encryption ([N]o/[y]es): "
  read strongEncryption
  echo

  encryption="standard"
  if echo ${strongEncryption:0:1} | grep -iq y; then
    encryption="strong"
  fi

  PIA_AUTOCONNECT="openvpn_${protocol}_${encryption}"
fi
export PIA_AUTOCONNECT
echo PIA_AUTOCONNECT=$PIA_AUTOCONNECT"
"

# Check for the required presence of resolvconf for setting DNS on wireguard connections.
setDNS="yes"
if ! command -v resolvconf &>/dev/null && [ "$PIA_AUTOCONNECT" == wireguard ]; then
  echo The resolvconf package could not be found.
  echo This script can not set DNS for you and you will
  echo need to invoke DNS protection some other way.
  echo
  setDNS="no"
fi

if [ "$setDNS" != no ]; then
  echo Using third party DNS could allow DNS monitoring.
  echo -n "Do you want to force PIA DNS ([Y]es/[n]o): "
  read setDNS
  echo
fi

PIA_DNS="true"
if echo ${setDNS:0:1} | grep -iq n; then
  PIA_DNS="false"
fi
export PIA_DNS
echo PIA_DNS=$PIA_DNS"
"

echo "Having active IPv6 connections might compromise security by allowing"
echo "split tunnel connections that run outside the VPN tunnel."
echo -n "Do you want to disable IPv6? (Y/n): "
read disable_IPv6
echo

if echo ${disable_IPv6:0:1} | grep -iq n; then
  echo "IPv6 settings have not been altered.
  "
else
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1
  echo
  echo "IPv6 has been disabled, you can enable it again with: "
  echo "sysctl -w net.ipv6.conf.all.disable_ipv6=0"
  echo "sysctl -w net.ipv6.conf.default.disable_ipv6=0
  "
fi

./get_region.sh
