#!/usr/bin/env bash
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
check_tool() {
  cmd=$1
  if ! command -v "$cmd" >/dev/null; then
    echo "$cmd could not be found"
    echo "Please install $cmd"
    exit 1
  fi
}
# Now we call the function to make sure we can use curl and jq.
check_tool curl
check_tool jq

# If the server list has less than 1000 characters, it means curl failed.
check_all_region_data() {
  echo
  echo -n "Getting the server list..."

  if [[ ${#all_region_data} -lt 1000 ]]; then
    echo -e "${red}Could not get correct region data. To debug this, run:"
    echo "$ curl -v $serverlist_url"
    echo -e "If it works, you will get a huge JSON as a response.${nc}"
    exit 1
  fi

  # Notify the user that we got the server list.
  echo -e "${green}OK!${nc}
  "
}

# Get all data for the selected region
# Exit with code 1 if the REGION_ID provided is invalid
get_selected_region_data() {
  regionData="$( echo "$all_region_data" |
  jq --arg REGION_ID "$selectedRegion" -r \
  '.regions[] | select(.id==$REGION_ID)')"
  if [[ -z $regionData ]]; then
    echo -e "${red}The REGION_ID $selectedRegion is not valid.${nc}
    "
    exit 1
  fi
}

# Check if terminal allows output, if yes, define colors for output
if [[ -t 1 ]]; then
  ncolors=$(tput colors)
  if [[ -n $ncolors && $ncolors -ge 8 ]]; then
    red=$(tput setaf 1) # ANSI red
    green=$(tput setaf 2) # ANSI green
    nc=$(tput sgr0) # No Color
  else
    red=''
    green=''
    nc='' # No Color
  fi
fi

# Only allow script to run as root
if (( EUID != 0 )); then
  echo -e "${red}This script needs to be run as root. Try again with 'sudo $0'${nc}"
  exit 1
fi

mkdir -p /opt/piavpn-manual
# Erase old latencyList file
rm -f /opt/piavpn-manual/latencyList
touch /opt/piavpn-manual/latencyList

# This allows you to set the maximum allowed latency in seconds.
# All servers that respond slower than this will be ignored.
# You can inject this with the environment variable MAX_LATENCY.
# The default value is 50 milliseconds.
MAX_LATENCY=${MAX_LATENCY:-0.05}
export MAX_LATENCY

serverlist_url='https://serverlist.piaservers.net/vpninfo/servers/v6'

# This function checks the latency you have to a specific region.
# It will print a human-readable message to stderr,
# and it will print the variables to stdout
printServerLatency() {
  serverIP=$1
  regionID=$2
  regionName="$(echo "${@:3}" |
    sed 's/ false//' | sed 's/true/(geo)/')"
  time=$(LC_NUMERIC=en_US.utf8 curl -o /dev/null -s \
    --connect-timeout "$MAX_LATENCY" \
    --write-out "%{time_connect}" \
    "http://$serverIP:443")
  if [[ $? -eq 0 ]]; then
    >&2 echo "Got latency ${time}s for region: $regionName"
    echo "$time $regionID $serverIP"
    # Write a list of servers with acceptable latency
    # to /opt/piavpn-manual/latencyList
    echo -e "$time" "$regionID"'\t'"$serverIP"'\t'"$regionName" >> /opt/piavpn-manual/latencyList
  fi
  # Sort the latencyList, ordered by latency
  sort -no /opt/piavpn-manual/latencyList /opt/piavpn-manual/latencyList
}
export -f printServerLatency

# If a server location or autoconnect isn't specified, set the variable to false/no.
if [[ -z $PREFERRED_REGION ]]; then
  PREFERRED_REGION=none
fi
if [[ -z $VPN_PROTOCOL ]]; then
  VPN_PROTOCOL=no
fi

# Get all region data
all_region_data=$(curl -s "$serverlist_url" | head -1)

# Set the region the user has specified
selectedRegion=$PREFERRED_REGION

# If a server isn't being specified, auto-select the server with the lowest latency
if [[ $selectedRegion == "none" ]]; then
  selectedOrLowestLatency="lowest latency"
  check_all_region_data

  # Making sure this variable doesn't contain some strange string
  if [[ $PIA_PF != "true" ]]; then
    PIA_PF="false"
  fi

  # Test one server from each region to get the closest region.
  # If port forwarding is enabled, filter out regions that don't support it.
  if [[ $PIA_PF == "true" ]]; then
    echo "Port Forwarding is enabled, non-PF servers excluded."
    echo
    summarized_region_data="$( echo "$all_region_data" |
      jq -r '.regions[] | select(.port_forward==true) |
      .servers.meta[0].ip+" "+.id+" "+.name+" "+(.geo|tostring)' )"
  else
    summarized_region_data="$( echo "$all_region_data" |
    jq -r '.regions[] |
    .servers.meta[0].ip+" "+.id+" "+.name+" "+(.geo|tostring)' )"
  fi
  echo -e Testing regions that respond \
    faster than "${green}$MAX_LATENCY${nc}" seconds:
  selectedRegion="$(echo "$summarized_region_data" |
    xargs -I{} bash -c 'printServerLatency {}' |
    sort | head -1 | awk '{ print $2 }')"
  echo

  if [[ -z $selectedRegion ]]; then
    echo -e "${red}No region responded within ${MAX_LATENCY}s, consider using a higher timeout."
    echo "For example, to wait 1 second for each region, inject MAX_LATENCY=1 like this:"
    echo -e "$ MAX_LATENCY=1 ./get_region.sh${nc}"
    exit 1
  else
    echo -e "A list of servers and connection details, ordered by latency can be
found in at : ${green}/opt/piavpn-manual/latencyList${nc}
"
  fi
else
  selectedOrLowestLatency="selected"
  check_all_region_data
fi

get_selected_region_data

bestServer_meta_IP=$(echo "$regionData" | jq -r '.servers.meta[0].ip')
bestServer_meta_hostname=$(echo "$regionData" | jq -r '.servers.meta[0].cn')
bestServer_WG_IP=$(echo "$regionData" | jq -r '.servers.wg[0].ip')
bestServer_WG_hostname=$(echo "$regionData" | jq -r '.servers.wg[0].cn')
bestServer_OT_IP=$(echo "$regionData" | jq -r '.servers.ovpntcp[0].ip')
bestServer_OT_hostname=$(echo "$regionData" | jq -r '.servers.ovpntcp[0].cn')
bestServer_OU_IP=$(echo "$regionData" | jq -r '.servers.ovpnudp[0].ip')
bestServer_OU_hostname=$(echo "$regionData" | jq -r '.servers.ovpnudp[0].cn')


if [[ $VPN_PROTOCOL == "no" ]]; then
  echo -ne "The $selectedOrLowestLatency region is ${green}$(echo "$regionData" | jq -r '.name')${nc}"
  if echo "$regionData" | jq -r '.geo' | grep true > /dev/null; then
    echo " (geolocated region)."
  else
    echo "."
  fi
  echo -e "
The script found the best servers from the region you selected.
When connecting to an IP (no matter which protocol), please verify
the SSL/TLS certificate actually contains the hostname so that you
are sure you are connecting to a secure server, validated by the
PIA authority. Please find below the list of best IPs and matching
hostnames for each protocol:
${green}Meta Services $bestServer_meta_IP\t-     $bestServer_meta_hostname
WireGuard     $bestServer_WG_IP\t-     $bestServer_WG_hostname
OpenVPN TCP   $bestServer_OT_IP\t-     $bestServer_OT_hostname
OpenVPN UDP   $bestServer_OU_IP\t-     $bestServer_OU_hostname
${nc}"
fi

# The script will check for an authentication token, and use it if present
# If no token exists, the script will check for login credentials to generate one
if [[ -z $PIA_TOKEN ]]; then
  if [[ -z $PIA_USER || -z $PIA_PASS ]]; then
    echo -e "${red}If you want this script to automatically get an authentication"
    echo "token, please add the variables PIA_USER and PIA_PASS. Example:"
    echo -e "$ PIA_USER=p0123456 PIA_PASS=xxx ./get_region.sh${nc}"
    exit 0
  fi
  ./get_token.sh
  PIA_TOKEN=$( awk 'NR == 1' /opt/piavpn-manual/token )
  export PIA_TOKEN
  rm -f /opt/piavpn-manual/token
else
  echo -e "Using existing token ${green}$PIA_TOKEN${nc}."
  echo
fi

# Connect with WireGuard and clear authentication token file and latencyList
if [[ $VPN_PROTOCOL == "wireguard" ]]; then
  echo "The ./get_region.sh script got started with"
  echo -e "${green}VPN_PROTOCOL=wireguard${nc}, so we will automatically connect to WireGuard,"
  echo "by running this command:"
  echo -e "$ ${green}PIA_TOKEN=$PIA_TOKEN \\"
  echo "WG_SERVER_IP=$bestServer_WG_IP WG_HOSTNAME=$bestServer_WG_hostname \\"
  echo -e "PIA_PF=$PIA_PF ./connect_to_wireguard_with_token.sh${nc}"
  echo
  PIA_PF=$PIA_PF PIA_TOKEN=$PIA_TOKEN WG_SERVER_IP=$bestServer_WG_IP \
    WG_HOSTNAME=$bestServer_WG_hostname ./connect_to_wireguard_with_token.sh
  rm -f /opt/piavpn-manual/latencyList
  exit 0
fi

# Connect with OpenVPN and clear authentication token file and latencyList
if [[ $VPN_PROTOCOL == openvpn* ]]; then
  serverIP=$bestServer_OU_IP
  serverHostname=$bestServer_OU_hostname
  if [[ $VPN_PROTOCOL == *tcp* ]]; then
    serverIP=$bestServer_OT_IP
    serverHostname=$bestServer_OT_hostname
  fi
  echo "The ./get_region.sh script got started with"
  echo -e "${green}VPN_PROTOCOL=$VPN_PROTOCOL${nc}, so we will automatically"
  echo "connect to OpenVPN, by running this command:"
  echo -e "$ ${green}PIA_PF=$PIA_PF PIA_TOKEN=$PIA_TOKEN \\"
  echo "  OVPN_SERVER_IP=$serverIP \\"
  echo "  OVPN_HOSTNAME=$serverHostname \\"
  echo "  CONNECTION_SETTINGS=$VPN_PROTOCOL \\"
  echo -e "  ./connect_to_openvpn_with_token.sh${nc}"
  echo
  PIA_PF=$PIA_PF PIA_TOKEN=$PIA_TOKEN \
    OVPN_SERVER_IP=$serverIP \
    OVPN_HOSTNAME=$serverHostname \
    CONNECTION_SETTINGS=$VPN_PROTOCOL \
    ./connect_to_openvpn_with_token.sh
  rm -f /opt/piavpn-manual/latencyList
  exit 0
fi
