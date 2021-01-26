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

# Check if terminal allows output, if yes, define colors for output
if test -t 1; then
  ncolors=$(tput colors)
  if test -n "$ncolors" && test $ncolors -ge 8; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color
  else
    GREEN=''
    RED=''
    NC='' # No Color
  fi
fi

# Variables to use for validating input
intCheck='^[0-9]+$'
floatCheck='^[0-9]+([.][0-9]+)?$'

# Only allow script to run as
if [ "$(whoami)" != "root" ]; then
  echo -e "${RED}This script needs to be run as root. Try again with 'sudo $0'${NC}"
  exit 1
fi

# Erase previous authentication token if present
rm -f /opt/piavpn-manual/token /opt/piavpn-manual/latencyList

# Retry login if no token is generated
while :; do
    while :; do
      # Check for in-line definition of $PIA_USER
      if [[ ! $PIA_USER || $PIA_USER = "" ]]; then
        echo
        read -p "PIA username (p#######): " PIA_USER
      fi
      
      # Confirm format of PIA_USER input
      unPrefix=$( echo ${PIA_USER:0:1} )
      unSuffix=$( echo ${PIA_USER:1} )
      if [[ -z "$PIA_USER" ]]; then
        echo -e "\n${RED}You must provide input.${NC}"
      elif [[ ${#PIA_USER} != 8 ]]; then
        echo -e "\n${RED}A PIA username is always 8 characters long.${NC}"
      elif [[ $unPrefix != "P" ]] && [[ $unPrefix != "p" ]]; then
        echo -e "\n${RED}A PIA username must start with \"p\".${NC}"
      elif ! [[ $unSuffix =~ $intCheck ]]; then
        echo -e "\n${RED}Username formatting is always p#######!${NC}"
      else
        echo -e "\n${GREEN}PIA_USER=$PIA_USER${NC}"
        break
      fi
      PIA_USER=""
    done
  export PIA_USER
 
  while :; do
    # Check for in-line definition of $PIA_PASS
    if [[ ! $PIA_PASS || $PIA_PASS = "" ]]; then
      echo
      echo -n "PIA password: "
      read -rs PIA_PASS
      echo
    fi
  
    # Confirm format of PIA_PASS input
    if [[ -z "$PIA_PASS" ]]; then
      echo -e "\n${RED}You must provide input.${NC}"
    elif [[ ${#PIA_PASS} -lt 8 ]]; then
      echo -e "\n${RED}A PIA password is always a minimum of 8 characters long.${NC}"
    else
      echo -e "\n${GREEN}PIA_PASS input received.${NC}"
      echo
      break
    fi
    PIA_PASS=""
  done
  export PIA_PASS

  # Confirm credentials and generate token
  ./get_token.sh

  tokenLocation="/opt/piavpn-manual/token"
  # If the script failed to generate an authentication token, the script will exit early.
  if [ ! -f "$tokenLocation" ]; then
    read -p "Do you want to try again ([N]o/[y]es): " tryAgain
    if ! echo ${tryAgain:0:1} | grep -iq y; then
      exit 1
    fi
    PIA_USER=""
    PIA_PASS=""
  else
    PIA_TOKEN=$( awk 'NR == 1' /opt/piavpn-manual/token )
    export PIA_TOKEN
    rm -f /opt/piavpn-manual/token
    break
  fi
done

# Check for in-line definition of PIA_PF and prompt for input
if [[ ! $PIA_PF || $PIA_PF = "" ]]; then
  echo -n "Do you want a forwarding port assigned ([N]o/[y]es): "
  read portForwarding
  echo
  if echo ${portForwarding:0:1} | grep -iq y; then
    PIA_PF="true"
  fi
fi
if [[ $PIA_PF != "true" ]]; then
 PIA_PF="false"
fi
export PIA_PF
echo -e ${GREEN}PIA_PF=$PIA_PF${NC}
echo

# Check for in-line definition of DISABLE_IPV6 and prompt for input
if [[ ! $DISABLE_IPV6 || $DISABLE_IPV6 = "" ]]; then
  echo "Having active IPv6 connections might compromise security by allowing"
  echo "split tunnel connections that run outside the VPN tunnel."
  echo -n "Do you want to disable IPv6? (Y/n): "
  read DISABLE_IPV6
  echo
fi

if echo ${DISABLE_IPV6:0:1} | grep -iq n; then
  echo -e ${RED}"IPv6 settings have not been altered.
  "${NC}
else
  echo -e "The variable ${GREEN}DISABLE_IPV6=$DISABLE_IPV6${NC}, does not start with 'n' for 'no'.
${GREEN}Defaulting to yes.${NC}
"
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1
  echo
  echo -e "${RED}IPv6 has been disabled${NC}, you can ${GREEN}enable it again with: "
  echo "sysctl -w net.ipv6.conf.all.disable_ipv6=0"
  echo "sysctl -w net.ipv6.conf.default.disable_ipv6=0"
  echo -e ${NC}
fi

# Input validation and check for conflicting declartions of AUTOCONNECT and PREFERRED_REGION
# If both variables are set, AUTOCONNECT has superiority and PREFERRED_REGION is ignored
if [[ ! $AUTOCONNECT ]]; then
  echo AUTOCONNECT was not declared.
  echo
  selectServer="ask"
elif echo ${AUTOCONNECT:0:1} | grep -iq f; then
  if [[ $AUTOCONNECT != "false" ]]; then
    echo -e "The variable ${GREEN}AUTOCONNECT=$AUTOCONNECT${NC}, starts with 'f' for 'false'."
    AUTOCONNECT="false"
    echo -e "Updated ${GREEN}AUTOCONNECT=$AUTOCONNECT${NC}"
    echo
  fi
  selectServer="yes"
else
  if [[ $AUTOCONNECT != "true" ]]; then
    echo -e "The variable ${GREEN}AUTOCONNECT=$AUTOCONNECT${NC}, does not start with 'f' for 'false'."
    AUTOCONNECT="true"
    echo -e "Updated ${GREEN}AUTOCONNECT=$AUTOCONNECT${NC}"
    echo
  fi
  if [[ ! $PREFERRED_REGION ]]; then
    echo -e "${GREEN}AUTOCONNECT=true${NC}"
    echo
  else
    echo
    echo AUTOCONNECT supercedes in-line definitions of PREFERRED_REGION.
    echo -e "${RED}PREFERRED_REGION=$PREFERRED_REGION will be ignored.${NC}
    "
    PREFERRED_REGION=""
  fi
  selectServer="no"
fi

# Prompt the user to specify a server or auto-connect to the lowest latency
while :; do
  if [[ ! $PREFERRED_REGION || $PREFERRED_REGION = "" ]]; then
    # If autoconnect is not set, prompt the user to specify a server or auto-connect to the lowest latency
    if [[ $selectServer = "ask" ]]; then
      echo -n "Do you want to manually select a server, instead of auto-connecting to the
server with the lowest latency ([N]o/[y]es): "
      read selectServer
      echo
    fi

    # Call the region script with input to create an ordered list based upon latency
    # When $PREFERRED_REGION is set to none, get_region.sh will generate a list of servers
    # that meet the latency requirements speciied by $MAX_LATENCY.
    # When $VPN_PROTOCOL is set to no, get_region.sh will sort that list of servers
    # to allow for numeric selection, or an easy manual review of options.
    if echo ${selectServer:0:1} | grep -iq y; then
      # This sets the maximum allowed latency in seconds.
      # All servers that respond slower than this will be ignored.
      if [[ ! $MAX_LATENCY || $MAX_LATENCY = "" ]]; then
        echo -n "With no input, the maximum allowed latency will be set to 0.05s (50ms).
If your connection has high latency, you may need to increase this value.
For example, you can try 0.2 for 200ms allowed latency.
"
      else
        latencyInput=$MAX_LATENCY
      fi

      # Assure that input is numeric and properly formatted.
      MAX_LATENCY=0.05 # default
      while :; do
        if [[ ! $latencyInput || $latencyInput = "" ]]; then
          read -p "Custom latency (no input required for 50ms): " latencyInput
          echo
        fi
        customLatency=0
        customLatency+=$latencyInput
    
        if [[ -z "$latencyInput" ]]; then
          break
        elif [[ $latencyInput = 0 ]]; then
          echo -e "${RED}Latency input must not be zero.${NC}\n"
        elif ! [[ $customLatency =~ $floatCheck ]]; then
          echo -e "${RED}Latency input must be numeric.${NC}\n"
        elif [[ $latencyInput =~ $intCheck ]]; then
          MAX_LATENCY=$latencyInput
          break
        else
          MAX_LATENCY=$customLatency
          break
        fi
        latencyInput=""
      done
      export MAX_LATENCY
      echo -e "${GREEN}MAX_LATENCY=$MAX_LATENCY${NC}"
      
      PREFERRED_REGION="none"
      export PREFERRED_REGION
      VPN_PROTOCOL="no"
      export VPN_PROTOCOL
      VPN_PROTOCOL=no ./get_region.sh
      
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
              echo -e "\n${RED}You must provide input.${NC}\n"
            elif ! [[ $serverSelection =~ $intCheck ]]; then
              echo -e "\n${RED}You must enter a number.${NC}\n"
            elif [[ $serverSelection -lt 1 ]]; then
              echo -e "\n${RED}You must enter a number greater than 1.${NC}\n"
            elif [[ $serverSelection -gt $i ]]; then
              echo -e "\n${RED}You must enter a number between 1 and $i.${NC}\n"
            else
              PREFERRED_REGION=$( awk 'NR == '$serverSelection' {print $2}' /opt/piavpn-manual/latencyList )
              echo
              echo -e ${GREEN}PREFERRED_REGION=$PREFERRED_REGION${NC}
              break
            fi
        done
  
        # Write the serverID for use when connecting, and display the serverName for user confirmation
        export PREFERRED_REGION
        echo
        break
      else
        exit 1
      fi
    else
      echo -e ${GREEN}You will auto-connect to the server with the lowest latency.${NC}
      echo
      break
    fi
  else
    # Validate in-line declaration of PREFERRED_REGION; if invalid remove input to initiate prompts
    echo Region input is : $PREFERRED_REGION
    export PREFERRED_REGION
    VPN_PROTOCOL=no ./get_region.sh
    if [[ $? != 1 ]]; then
      break
    fi
    PREFERRED_REGION=""
  fi
done

if [[ ! $VPN_PROTOCOL ]]; then
  VPN_PROTOCOL="none"
fi
# This section asks for user connection preferences
case $VPN_PROTOCOL in
  openvpn)
    VPN_PROTOCOL="openvpn_udp_standard"
    ;;
  wireguard | openvpn_udp_standard | openvpn_udp_strong | openvpn_tcp_standard | openvpn_tcp_strong)
    ;;
  none | *)
    echo -n "Connection method ([W]ireguard/[o]penvpn): "
    read connection_method
    echo
  
    VPN_PROTOCOL="wireguard"
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

      VPN_PROTOCOL="openvpn_${protocol}_${encryption}"
    fi
    ;;
esac
export VPN_PROTOCOL
echo -e ${GREEN}VPN_PROTOCOL=$VPN_PROTOCOL"
${NC}"

# Check for the required presence of resolvconf for setting DNS on wireguard connections
setDNS="yes"
if ! command -v resolvconf &>/dev/null && [ "$VPN_PROTOCOL" == wireguard ]; then
  echo -e ${RED}The resolvconf package could not be found.
  echo This script can not set DNS for you and you will
  echo -e need to invoke DNS protection some other way.${NC}
  echo
  setDNS="no"
fi

# Check for in-line definition of PIA_DNS and prompt for input
if [[ $setDNS = "yes" ]]; then
  if [[ ! $PIA_DNS || $PIA_DNS = "" ]]; then
    echo Using third party DNS could allow DNS monitoring.
    echo -n "Do you want to force PIA DNS ([Y]es/[n]o): "
    read setDNS
    echo
    PIA_DNS="true"
    if echo ${setDNS:0:1} | grep -iq n; then
      PIA_DNS="false"
    fi
  fi
elif [[ $PIA_DNS != "true" || $setDNS = "no" ]];then
  PIA_DNS="false"
fi
export PIA_DNS
echo -e "${GREEN}PIA_DNS=$PIA_DNS${NC}"

CONNECTION_READY="true"
export CONNECTION_READY

./get_region.sh
