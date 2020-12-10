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

# This function allows you to check if the required tools have been installed.
function check_tool() {
  cmd=$1
  package=$2
  if ! command -v $cmd &>/dev/null
  then
    echo "$cmd could not be found"
    echo "Please install $package"
    exit 1
  fi
}
# Now we call the function to make sure we can use curl and jq.
check_tool curl curl
check_tool jq jq

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

mkdir -p /opt/piavpn-manual

if [[ ! $PIA_USER || ! $PIA_PASS ]]; then
  echo If you want this script to automatically get a token from the Meta
  echo service, please add the variables PIA_USER and PIA_PASS. Example:
  echo $ PIA_USER=p0123456 PIA_PASS=xxx ./get_token.sh
  exit 1
fi

tokenLocation=/opt/piavpn-manual/token
  
generateTokenResponse=$(curl -s -u "$PIA_USER:$PIA_PASS" \
  "https://privateinternetaccess.com/gtoken/generateToken")

if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
  echo
  echo
  echo -e ${RED}"Could not authenticate with the login credentials provided : "
  echo
  echo "Username : "$PIA_USER
  echo "Password : "$PIA_PASS
  exit 1
fi
  
echo -e ${GREEN}OK!
echo
token="$(echo "$generateTokenResponse" | jq -r '.token')"
echo -e PIA_TOKEN=$token${NC}
echo $token > /opt/piavpn-manual/token || exit 1
echo 
echo This token will expire in 24 hours.
echo
"

# Prompt the user to specify a server or auto-connect to the lowest latency
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
