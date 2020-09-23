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



# Set this to the maximum allowed latency in seconds.
# All servers that repond slower than this will be ignore.
# The value is currently set to 50 milliseconds.
maximum_allowed_latency=0.05
export maximum_allowed_latency

serverlist_url='https://serverlist.piaservers.net/vpninfo/servers/v4'

# This function checks the latency you have to a specific region.
# It will print a human-readable message to stderr,
# and it will print the variables to stdout
printServerLatency() {
  serverIP="$1"
  regionID="$2"
  regionName="$(echo ${@:3} |
    sed 's/ false//' | sed 's/true/(geo)/')"
  time=$(curl -o /dev/null -s \
    --connect-timeout $maximum_allowed_latency \
    --write-out "%{time_connect}" \
    http://$serverIP:443)
  if [ $? -eq 0 ]; then
    >&2 echo Got latency ${time}s for region: $regionName
    echo $time $regionID $serverIP
  fi
}
export -f printServerLatency

echo -n "Getting the server list... "
# Get all region data since we will need this on multiple ocasions
all_region_data=$(curl -s "$serverlist_url" | head -1)

# If the server list has less than 1000 characters, it means curl failed.
if [[ ${#all_region_data} < 1000 ]]; then
  echo "Could not get correct region data. To debug this, run:"
  echo "$ curl -v $serverlist_url"
  echo "If it works, you will get a huge JSON as a response."
  exit 1
fi
# Notify the user that we got the server list.
echo "OK!"

# Test one server from each region to get the closest region:
summarized_region_data="$( echo $all_region_data |
  jq -r '.regions[] | .servers.meta[0].ip+" "+.id+" "+.name+" "+(.geo|tostring)' )"
echo Testing regions that respond \
  faster than $maximum_allowed_latency seconds:
bestRegion="$(echo "$summarized_region_data" |
  xargs -i bash -c 'printServerLatency {}' |
  sort | head -1 | awk '{ print $2 }')"

# Get all data for the best region
regionData="$( echo $all_region_data |
  jq --arg REGION_ID "$bestRegion" -r \
  '.regions[] | select(.id==$REGION_ID)')"

echo -n The closest region is "$(echo $regionData | jq -r '.name')"
if echo $regionData | jq -r '.geo' | grep true > /dev/null; then 
  echo " (geolocated region)."
else 
  echo "."
fi
echo
bestServer_meta_IP="$(echo $regionData | jq -r '.servers.meta[0].ip')"
bestServer_meta_hostname="$(echo $regionData | jq -r '.servers.meta[0].cn')"
bestServer_WG_IP="$(echo $regionData | jq -r '.servers.wg[0].ip')"
bestServer_WG_hostname="$(echo $regionData | jq -r '.servers.wg[0].cn')"
bestServer_OT_IP="$(echo $regionData | jq -r '.servers.ovpntcp[0].ip')"
bestServer_OT_hostname="$(echo $regionData | jq -r '.servers.ovpntcp[0].cn')"
bestServer_OU_IP="$(echo $regionData | jq -r '.servers.ovpnudp[0].ip')"
bestServer_OU_hostname="$(echo $regionData | jq -r '.servers.ovpnudp[0].cn')"

echo "The script found the best servers from the region closest to you.
When connecting to an IP (no matter which protocol), please verify
the SSL/TLS certificate actually contains the hostname so that you
are sure you are connecting to a secure server, validated by the
PIA authority. Please find bellow the list of best IPs and matching
hostnames for each protocol:
Meta Services: $bestServer_meta_IP // $bestServer_meta_hostname
WireGuard: $bestServer_WG_IP // $bestServer_WG_hostname
OpenVPN TCP: $bestServer_OT_IP // $bestServer_OT_hostname
OpenVPN UDP: $bestServer_OU_IP // $bestServer_OU_hostname
"

if [ -z "$PIA_USER" ]; then
  echo If you want this script to automatically get a token from the Meta
  echo service, please add the variable PIA_USER. Example:
  echo $ PIA_USER=p0123456 ./get_region_and_token.sh
  echo "You may optionally also supply PIA_PASS, however it may be visible"
  echo "  in plaintext to other users on this system."
  echo "If you do not supply PIA_PASS, you will be prompted to enter it"
  echo "  and it won't be visible to other users on this system"
  exit 1
fi

# prepend a colon to the password so curl can use it
# if PIA_PASS is empty, curl will only see a username and thus prompt for a
#   password by itself - avoiding ever leaking the password via /proc/*/env
#   or `ps ax`
# Users can still provide PIA_PASS if they accept this risk
PIA_PASS="${PIA_PASS:+:$PIA_PASS}"

echo "Trying to get a new token by authenticating with the meta service..."

if [ -z "$PIA_PASS" ]; then
  echo "* Your password will not be stored, nor be visible to other users on this system"
fi

generateTokenResponse=$(curl -s -S -u "$PIA_USER$PIA_PASS" \
  --connect-to "$bestServer_meta_hostname::$bestServer_meta_IP:" \
  --cacert "ca.rsa.4096.crt" \
  "https://$bestServer_meta_hostname/authv3/generateToken")
echo "$generateTokenResponse"

if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
  echo "Could not get a token. Please check your account credentials."
  echo "You can also try debugging by manually running the curl command:"
  echo $ curl -vs -u "username:password" --cacert ca.rsa.4096.crt \
    --connect-to "$bestServer_meta_hostname::$bestServer_meta_IP:" \
    https://$bestServer_meta_hostname/authv3/generateToken
  exit 1
fi

token="$(echo "$generateTokenResponse" | jq -r '.token')"
echo "This token will expire in 24 hours.
"

if [ "$PIA_AUTOCONNECT" != wireguard ]; then
  echo If you wish to automatically connect to WireGuard after detecting the best
  echo region, please run the script with the env var PIA_AUTOCONNECT=wireguard. You can
  echo also specify the env var PIA_PF=true to get port forwarding. Example:
  echo $ PIA_USER=p0123456 PIA_PASS=xxx \
    PIA_AUTOCONNECT=true PIA_PF=true ./sort_regions_by_latency.sh
  echo
  echo You can also connect now by running this command:
  echo $ WG_TOKEN=\"$token\" WG_SERVER_IP=$bestServer_WG_IP \
    WG_HOSTNAME=$bestServer_WG_hostname ./connect_to_wireguard_with_token.sh
  exit
fi

if [ "$PIA_PF" != true ]; then
  PIA_PF="false"
fi

echo "The ./get_region_and_token.sh script got started with PIA_AUTOCONNECT=wireguard,
so we will automatically connect to WireGuard, by running this command:
$ WG_TOKEN=\"$token\" \\
  WG_SERVER_IP=$bestServer_WG_IP WG_HOSTNAME=$bestServer_WG_hostname \\
  PIA_PF=$PIA_PF ./connect_to_wireguard_with_token.sh
"

PIA_PF=$PIA_PF WG_TOKEN="$token" WG_SERVER_IP=$bestServer_WG_IP \
  WG_HOSTNAME=$bestServer_WG_hostname ./connect_to_wireguard_with_token.sh
