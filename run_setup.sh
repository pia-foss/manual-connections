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

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Variables to use for validating input
intCheck='^[0-9]+$'
floatCheck='^[0-9]+([.][0-9]+)?$'

# Only allow script to run as
if [ "$(whoami)" != "root" ]; then
  echo -e "${RED}This script needs to be run as root. Try again with 'sudo $0'"
  exit 1
fi

# Erase previous authentication token if present
rm -f /opt/piavpn-manual/token /opt/piavpn-manual/latencyList

# Retry login if no token is generated
while :; do
  # Confirm PIA_USER input
  echo
  while :; do
    read -p "PIA username (p#######): " PIA_USER
    unPrefix=$( echo ${PIA_USER:0:1} )
    unSuffix=$( echo ${PIA_USER:1} )
  
    if [[ -z "$PIA_USER" ]]; then
      echo -e "${RED}You must provide input.${NC}"
    elif [[ ${#PIA_USER} != 8 ]]; then
      echo -e "${RED}A PIA username is always 8 characters long.${NC}"
    elif [[ $unPrefix != "P" ]] && [[ $unPrefix != "p" ]]; then
      echo -e "${RED}A PIA username must start with \"p\".${NC}"
    elif ! [[ $unSuffix =~ $intCheck ]]; then
      echo -e "${RED}Username formatting is always p#######!${NC}"
    else
      echo
      echo -e ${GREEN}PIA_USER=$PIA_USER${NC}
      echo
      break
    fi
  done
  export PIA_USER

  # Confirm PIA_PASS input
  while :; do
    read -sp "PIA password: " PIA_PASS
  
    if [[ -z "$PIA_PASS" ]]; then
      echo -e "\n${RED}You must provide input.${NC}"
    elif [[ ${#PIA_PASS} -lt 8 ]]; then
      echo -e "\n${RED}A PIA password is always a minimum of 8 characters long.${NC}"
    else
      echo
      echo
      break
    fi
  done
  export PIA_PASS

  echo -n "Checking login credentials..."
  # Confirm MAX_LATENCY allowance, then confirm credentials and generate token
  ./get_token.sh

  # If the script failed to generate an authentication token, the script will exit early.
  tokenLocation=/opt/piavpn-manual/token
  if [ ! -f "$tokenLocation" ]; then
    echo
    read -p "Do you want to try again ([N]o/[y]es): " tryAgain
    if ! echo ${tryAgain:0:1} | grep -iq y; then
      exit 1
    fi
  else
    break
  fi
done

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
echo -e ${GREEN}PIA_PF=$PIA_PF${NC}
echo

# Check for the required presence of resolvconf for setting DNS on wireguard connections.
setDNS="yes"
if ! command -v resolvconf &>/dev/null && [ "$PIA_AUTOCONNECT" == wireguard ]; then
  echo -e ${RED}The resolvconf package could not be found.
  echo This script can not set DNS for you and you will
  echo -e need to invoke DNS protection some other way.${NC}
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
echo -e ${GREEN}PIA_DNS=$PIA_DNS"
${NC}"

echo "Having active IPv6 connections might compromise security by allowing"
echo "split tunnel connections that run outside the VPN tunnel."
echo -n "Do you want to disable IPv6? (Y/n): "
read disable_IPv6
echo

if echo ${disable_IPv6:0:1} | grep -iq n; then
  echo -e ${RED}"IPv6 settings have not been altered.
  "${NC}
else
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1
  echo
  echo -e "${RED}IPv6 has been disabled${NC}, you can ${GREEN}enable it again with: "
  echo "sysctl -w net.ipv6.conf.all.disable_ipv6=0"
  echo "sysctl -w net.ipv6.conf.default.disable_ipv6=0"
  echo -e ${NC}
fi

# Set this to the maximum allowed latency in seconds.
# All servers that respond slower than this will be ignored.
echo -n "With no input, the maximum allowed latency will be set to 0.05s (50ms).
If your connection has high latency, you may need to increase this value.
For example, you can try 0.2 for 200ms allowed latency.
"

# Assure that input is numeric and properly formatted.
MAX_LATENCY=0.05 # default
while :; do
  customLatency=0
  read -p "Custom latency (no input required for 50ms): " latencyInput
  customLatency+=$latencyInput
  
  if [[ -z "$latencyInput" ]]; then
    break
  elif ! [[ $customLatency =~ $floatCheck ]]; then
    echo -e ${RED}Latency input must be numeric.${NC}
  elif [[ $latencyInput =~ $intCheck ]]; then
    MAX_LATENCY=$latencyInput
    break
  else
    MAX_LATENCY=$customLatency
    break
  fi
done
export MAX_LATENCY
echo -e "
${GREEN}MAX_LATENCY=$MAX_LATENCY${NC}
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
  
  if [ -s /opt/piavpn-manual/latencyList ]; then
    # Output the ordered list of servers that meet the latency specification $MAX_LATENCY
    echo -e "Orderd list of servers with latency less than ${GREEN}$MAX_LATENCY${NC} seconds:"
    i=0
    while read line; do
      i=$((i+1))
      time=$( awk 'NR == '$i' {print $1}' /opt/piavpn-manual/latencyList )
      id=$( awk 'NR == '$i' {print $2}' /opt/piavpn-manual/latencyList )
      ip=$( awk 'NR == '$i' {print $3}' /opt/piavpn-manual/latencyList )
      location1=$( awk 'NR == '$i' {print $4}' /opt/piavpn-manual/latencyList )
      location2=$( awk 'NR == '$i' {print $5}' /opt/piavpn-manual/latencyList )
      location3=$( awk 'NR == '$i' {print $6}' /opt/piavpn-manual/latencyList )
      location4=$( awk 'NR == '$i' {print $7}' /opt/piavpn-manual/latencyList )
      location=$location1" "$location2" "$location3" "$location4
      printf "%3s : %-8s %-15s %17s" $i $time $ip $id
      echo " - "$location
    done < /opt/piavpn-manual/latencyList
    echo
  
    # Receive input to specify the server to connect to manually
    while :; do 
      read -p "Input the number of the server you want to connect to ([1]-[$i]) : "  serverSelection
        if [[ -z "$serverSelection" ]]; then
          echo -e "${RED}You must provide input.${NC}"
        elif ! [[ $serverSelection =~ $intCheck ]]; then
          echo -e "${RED}You must enter a number.${NC}"
        elif [[ $serverSelection > $i ]] || [[ $serverSelection -eq 0 ]]; then
          echo -e "${RED}You must enter a number between 1 and $i!${NC}"
        else
          CONNECT_TO=$( awk 'NR == '$serverSelection' {print $2}' /opt/piavpn-manual/latencyList )
          echo
          echo -e ${GREEN}CONNECT_TO=$CONNECT_TO${NC}
          break
        fi
    done
  
    # Write the serverID for use when connecting, and display the serverName for user confirmation
    export CONNECT_TO
    echo
  else
    exit 1
  fi
else
  echo -e ${GREEN}You will auto-connect to the server with the lowest latency.${NC}
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
echo -e ${GREEN}PIA_AUTOCONNECT=$PIA_AUTOCONNECT"
${NC}"

./get_region.sh
