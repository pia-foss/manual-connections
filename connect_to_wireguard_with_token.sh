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
# Now we call the function to make sure we can use wg-quick, curl and jq.
check_tool wg-quick wireguard-tools
check_tool curl curl
check_tool jq jq

# PIA currently does not support IPv6. In order to be sure your VPN
# connection does not leak, it is best to disabled IPv6 altogether.
if [ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -ne 1 ] ||
  [ $(sysctl -n net.ipv6.conf.default.disable_ipv6) -ne 1 ]
then
  echo 'You should consider disabling IPv6 by running:'
  echo 'sysctl -w net.ipv6.conf.all.disable_ipv6=1'
  echo 'sysctl -w net.ipv6.conf.default.disable_ipv6=1'
fi

# Check if the mandatory environment variables are set.
if [[ ! $WG_SERVER_IP || ! $WG_HOSTNAME || ! $PIA_TOKEN ]]; then
  echo This script requires 3 env vars:
  echo WG_SERVER_IP - IP that you want to connect to
  echo WG_HOSTNAME  - name of the server, required for ssl
  echo PIA_TOKEN    - your authentication token
  echo
  echo You can also specify optional env vars:
  echo "PIA_PF                - enable port forwarding"
  echo "PAYLOAD_AND_SIGNATURE - In case you already have a port."
  echo
  echo An easy solution is to just run get_region_and_token.sh
  echo as it will guide you through getting the best server and
  echo also a token. Detailed information can be found here:
  echo https://github.com/pia-foss/manual-connections
  exit 1
fi

# Create ephemeral wireguard keys, that we don't need to save to disk.
privKey="$(wg genkey)"
export privKey
pubKey="$( echo "$privKey" | wg pubkey)"
export pubKey

# Authenticate via the PIA WireGuard RESTful API.
# This will return a JSON with data required for authentication.
# The certificate is required to verify the identity of the VPN server.
# In case you didn't clone the entire repo, get the certificate from:
# https://github.com/pia-foss/manual-connections/blob/master/ca.rsa.4096.crt
# In case you want to troubleshoot the script, replace -s with -v.
echo Trying to connect to the PIA WireGuard API on $WG_SERVER_IP...
wireguard_json="$(curl -s -G \
  --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
  --cacert "ca.rsa.4096.crt" \
  --data-urlencode "pt=${PIA_TOKEN}" \
  --data-urlencode "pubkey=$pubKey" \
  "https://${WG_HOSTNAME}:1337/addKey" )"
export wireguard_json
echo "$wireguard_json"

# Check if the API returned OK and stop this script if it didn't.
if [ "$(echo "$wireguard_json" | jq -r '.status')" != "OK" ]; then
  >&2 echo "Server did not return OK. Stopping now."
  exit 1
fi

# Multi-hop is out of the scope of this repo, but you should be able to
# get multi-hop running with both WireGuard and OpenVPN by playing with
# these scripts. Feel free to fork the project and test it out.
echo
echo Trying to disable a PIA WG connection in case it exists...
wg-quick down pia && echo Disconnected!
echo

# Create the WireGuard config based on the JSON received from the API
# In case you want this section to also add the DNS setting, please
# start the script with PIA_DNS=true.
# This uses a PersistentKeepalive of 25 seconds to keep the NAT active
# on firewalls. You can remove that line if your network does not
# require it.
echo -n "Trying to write /etc/wireguard/pia.conf... "
mkdir -p /etc/wireguard
if [ "$PIA_DNS" == true ]; then
  dnsServer="$(echo "$wireguard_json" | jq -r '.dns_servers[0]')"
  echo Trying to set up DNS to $dnsServer. In case you do not have resolvconf,
  echo this operation will fail and you will not get a VPN. If you have issues,
  echo start this script without PIA_DNS.
  dnsSettingForVPN="DNS = $dnsServer"
fi
echo "
[Interface]
Address = $(echo "$wireguard_json" | jq -r '.peer_ip')
PrivateKey = $privKey
$dnsSettingForVPN
[Peer]
PersistentKeepalive = 25
PublicKey = $(echo "$wireguard_json" | jq -r '.server_key')
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:$(echo "$wireguard_json" | jq -r '.server_port')
" > /etc/wireguard/pia.conf || exit 1
echo OK!

# Start the WireGuard interface.
# If something failed, stop this script.
# If you get DNS errors because you miss some packages,
# just hardcode /etc/resolv.conf to "nameserver 10.0.0.242".
echo
echo Trying to create the wireguard interface...
wg-quick up pia || exit 1
echo "The WireGuard interface got created.
At this point, internet should work via VPN.

--> to disconnect the VPN, run:
$ wg-quick down pia"

# This section will stop the script if PIA_PF is not set to "true".
if [ "$PIA_PF" != true ]; then
  echo
  echo If you want to also enable port forwarding, please start the script
  echo with the env var PIA_PF=true. Example:
  echo $ WG_SERVER_IP=10.0.0.3 WG_HOSTNAME=piaserver401 \
    PIA_TOKEN=\"\$token\" PIA_PF=true \
    ./connect_to_wireguard_with_token.sh
  exit
fi

echo "
This script got started with PIA_PF=true.
Starting procedure to enable port forwarding by running the following command:
$ PIA_TOKEN=$PIA_TOKEN \\
  PF_GATEWAY=\"$(echo "$wireguard_json" | jq -r '.server_vip')\" \\
  PF_HOSTNAME=\"$WG_HOSTNAME\" \\
  ./port_forwarding.sh
"

PIA_TOKEN=$PIA_TOKEN \
  PF_GATEWAY="$(echo "$wireguard_json" | jq -r '.server_vip')" \
  PF_HOSTNAME="$WG_HOSTNAME" \
  ./port_forwarding.sh
