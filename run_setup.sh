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

# Variables to use for validating input
intCheck='^[0-9]+$'
floatCheck='^[0-9]+([.][0-9]+)?$'

# Only allow script to run as root
if (( EUID != 0 )); then
  echo -e "${red}This script needs to be run as root. Try again with 'sudo $0'${nc}"
  exit 1
fi

# Erase previous authentication token if present
rm -f /opt/piavpn-manual/token /opt/piavpn-manual/latencyList

# Retry login if no token is generated
while :; do
    while :; do
      # Check for in-line definition of $PIA_USER
      if [[ -z $PIA_USER ]]; then
        echo
        read -r -p "PIA username (p#######): " PIA_USER
      fi

      # Confirm format of PIA_USER input
      unPrefix=${PIA_USER:0:1}
      unSuffix=${PIA_USER:1}
      if [[ -z $PIA_USER ]]; then
        echo -e "\n${red}You must provide input.${nc}"
      elif [[ ${#PIA_USER} != 8 ]]; then
        echo -e "\n${red}A PIA username is always 8 characters long.${nc}"
      elif [[ $unPrefix != "P" ]] && [[ $unPrefix != "p" ]]; then
        echo -e "\n${red}A PIA username must start with \"p\".${nc}"
      elif ! [[ $unSuffix =~ $intCheck ]]; then
        echo -e "\n${red}Username formatting is always p#######!${nc}"
      else
        echo -e "\n${green}PIA_USER=$PIA_USER${nc}"
        break
      fi
      PIA_USER=""
    done
  export PIA_USER

  while :; do
    # Check for in-line definition of $PIA_PASS
    if [[ -z $PIA_PASS ]]; then
      echo
      echo -n "PIA password: "
      read -r -s PIA_PASS
      echo
    fi

    # Confirm format of PIA_PASS input
    if [[ -z $PIA_PASS ]]; then
      echo -e "\n${red}You must provide input.${nc}"
    elif [[ ${#PIA_PASS} -lt 8 ]]; then
      echo -e "\n${red}A PIA password is always a minimum of 8 characters long.${nc}"
    else
      echo -e "\n${green}PIA_PASS input received.${nc}"
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
  if [[ ! -f $tokenLocation ]]; then
    read -r -p "Do you want to try again ([N]o/[y]es): " tryAgain
    if ! echo "${tryAgain:0:1}" | grep -iq y; then
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

# Check for in-line definition of $DIP_TOKEN
if [[ -z $DIP_TOKEN ]]; then
    # Check for dedicated IP
    echo -n "Do you want to use a dedicated IP token ([N]o/[y]es): "
    read useDIP
    echo
    pfOption="true"
else
    if echo ${DIP_TOKEN:0:1} | grep -iq n; then
      useDIP="no"
      echo -e "${red}Not using a dedicated IP.${nc}"
      echo
      DIP_TOKEN=""
    else
      useDIP="yes"
    fi
fi

if echo ${useDIP:0:1} | grep -iq y; then
  useDIP="true"
  while :; do
    while :; do
      # Check for in-line definition of $DIP_TOKEN
      if [[ -z $DIP_TOKEN ]]; then
        read -p "Dedicated token (DIP#############################): " DIP_TOKEN
      fi
      # Confirm format of DIP_TOKEN input
      dipPrefix=$( echo ${DIP_TOKEN:0:3} )
      if [[ -z "$DIP_TOKEN" ]]; then
        echo -e "\n${red}You must provide input.${nc}"
      elif [[ ${#DIP_TOKEN} != 32 ]]; then
        echo -e "\n${red}A dedicated IP token is always 32 characters long.${nc}"
      elif [[ $dipPrefix != "DIP" ]]; then
        echo -e "\n${red}A dedicated IP token must start with \"DIP\".${nc}"
      else
        break
      fi
      echo
      DIP_TOKEN=""
    done
    export DIP_TOKEN
    # Confirm DIP_TOKEN and retrieve connection details
    ./get_dip.sh
    dipDetails="/opt/piavpn-manual/dipAddress"
    # If the script failed to generate retrieve dedicated IP information, the script will exit early.
      if [ ! -f "$dipDetails" ]; then
        read -p "Do you want to try again ([N]o/[y]es): " tryAgain
        echo
        if ! echo ${tryAgain:0:1} | grep -iq y; then
          exit 1
        fi
          DIP_TOKEN=""
      else
        dipAddress=$( awk 'NR == 1' /opt/piavpn-manual/dipAddress )
        dipHostname=$( awk 'NR == 2' /opt/piavpn-manual/dipAddress)
        dipKey=$( awk 'NR == 3' /opt/piavpn-manual/dipAddress )
        pfOption=$( awk 'NR == 5' /opt/piavpn-manual/dipAddress )
        rm -f /opt/piavpn-manual/dipAddress
        break
      fi
  done
fi

if [[ -z $DIP_TOKEN ]]; then
  echo "${green}DIP_TOKEN=none${nc}"
else
  echo "${green}DIP_TOKEN=$DIP_TOKEN${nc}"
fi
echo

# Erase previous connection details if present
rm -f /opt/piavpn-manual/token /opt/piavpn-manual/latencyList

# Prompt for port forwarding if no DIP or DIP allows it
if [[ $pfOption = "false" ]]; then
  PIA_PF="false"
fi
# Check for in-line definition of PIA_PF and prompt for input
if [[ -z $PIA_PF ]]; then
  echo -n "Do you want a forwarding port assigned ([N]o/[y]es): "
  read -r portForwarding
  echo
  if echo "${portForwarding:0:1}" | grep -iq y; then
    PIA_PF="true"
  fi
fi
if [[ $PIA_PF != "true" ]]; then
 PIA_PF="false"
fi
export PIA_PF
echo -e "${green}PIA_PF=$PIA_PF${nc}"
echo

# Check for in-line definition of DISABLE_IPV6 and prompt for input
if [[ -z $DISABLE_IPV6 ]]; then
  echo "Having active IPv6 connections might compromise security by allowing"
  echo "split tunnel connections that run outside the VPN tunnel."
  echo -n "Do you want to disable IPv6? (Y/n): "
  read -r DISABLE_IPV6
  echo
fi

if echo "${DISABLE_IPV6:0:1}" | grep -iq n; then
  echo -e "${red}IPv6 settings have not been altered.
  ${nc}"
else
  echo -e "The variable ${green}DISABLE_IPV6=$DISABLE_IPV6${nc}, does not start with 'n' for 'no'.
${green}Defaulting to yes.${nc}
"
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1
  echo
  echo -e "${red}IPv6 has been disabled${nc}, you can ${green}enable it again with: "
  echo "sysctl -w net.ipv6.conf.all.disable_ipv6=0"
  echo "sysctl -w net.ipv6.conf.default.disable_ipv6=0"
  echo -e "${nc}"
fi

# Only prompt for server selection if no DIP has been specified
if [[ -z $DIP_TOKEN ]]; then
  # Input validation and check for conflicting declarations of AUTOCONNECT and PREFERRED_REGION
  # If both variables are set, AUTOCONNECT has superiority and PREFERRED_REGION is ignored
  if [[ -z $AUTOCONNECT ]]; then
    echo "AUTOCONNECT was not declared."
    echo
    selectServer="ask"
  elif echo "${AUTOCONNECT:0:1}" | grep -iq f; then
    if [[ $AUTOCONNECT != "false" ]]; then
      echo -e "The variable ${green}AUTOCONNECT=$AUTOCONNECT${nc}, starts with 'f' for 'false'."
      AUTOCONNECT="false"
      echo -e "Updated ${green}AUTOCONNECT=$AUTOCONNECT${nc}"
      echo
    fi
    selectServer="yes"
  else
    if [[ $AUTOCONNECT != "true" ]]; then
      echo -e "The variable ${green}AUTOCONNECT=$AUTOCONNECT${nc}, does not start with 'f' for 'false'."
      AUTOCONNECT="true"
      echo -e "Updated ${green}AUTOCONNECT=$AUTOCONNECT${nc}"
      echo
    fi
    if [[ -z $PREFERRED_REGION ]]; then
      echo -e "${green}AUTOCONNECT=true${nc}"
      echo
    else
      echo
      echo "AUTOCONNECT supersedes in-line definitions of PREFERRED_REGION."
      echo -e "${red}PREFERRED_REGION=$PREFERRED_REGION will be ignored.${nc}
      "
      PREFERRED_REGION=""
    fi
    selectServer="no"
  fi

  # Prompt the user to specify a server or auto-connect to the lowest latency
  while :; do
    if [[ -z $PREFERRED_REGION ]]; then
      # If autoconnect is not set, prompt the user to specify a server or auto-connect to the lowest latency
      if [[ $selectServer == "ask" ]]; then
        echo -n "Do you want to manually select a server, instead of auto-connecting to the
  server with the lowest latency ([N]o/[y]es): "
        read -r selectServer
        echo
      fi

      # Call the region script with input to create an ordered list based upon latency
      # When $PREFERRED_REGION is set to none, get_region.sh will generate a list of servers
      # that meet the latency requirements specified by $MAX_LATENCY.
      # When $VPN_PROTOCOL is set to no, get_region.sh will sort that list of servers
      # to allow for numeric selection, or an easy manual review of options.
      if echo "${selectServer:0:1}" | grep -iq y; then
        # This sets the maximum allowed latency in seconds.
        # All servers that respond slower than this will be ignored.
        if [[ -z $MAX_LATENCY ]]; then
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
          if [[ -z $latencyInput ]]; then
            read -r -p "Custom latency (no input required for 50ms): " latencyInput
            echo
          fi
          customLatency=0
          customLatency+=$latencyInput

          if [[ -z $latencyInput ]]; then
            break
          elif [[ $latencyInput == 0 ]]; then
            echo -e "${red}Latency input must not be zero.${nc}\n"
          elif ! [[ $customLatency =~ $floatCheck ]]; then
            echo -e "${red}Latency input must be numeric.${nc}\n"
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
        echo -e "${green}MAX_LATENCY=$MAX_LATENCY${nc}"

        PREFERRED_REGION="none"
        export PREFERRED_REGION
        VPN_PROTOCOL="no"
        export VPN_PROTOCOL
        VPN_PROTOCOL=no ./get_region.sh

        if [[ -s /opt/piavpn-manual/latencyList ]]; then
          # Output the ordered list of servers that meet the latency specification $MAX_LATENCY
          echo -e "Ordered list of servers with latency less than ${green}$MAX_LATENCY${nc} seconds:"
          i=0
          while read -r line; do
            i=$((i+1))
            time=$( awk 'NR == '$i' {print $1}' /opt/piavpn-manual/latencyList )
            id=$( awk 'NR == '$i' {print $2}' /opt/piavpn-manual/latencyList )
            ip=$( awk 'NR == '$i' {print $3}' /opt/piavpn-manual/latencyList )
            location1=$( awk 'NR == '$i' {print $4}' /opt/piavpn-manual/latencyList )
            location2=$( awk 'NR == '$i' {print $5}' /opt/piavpn-manual/latencyList )
            location3=$( awk 'NR == '$i' {print $6}' /opt/piavpn-manual/latencyList )
            location4=$( awk 'NR == '$i' {print $7}' /opt/piavpn-manual/latencyList )
            location="$location1 $location2 $location3 $location4"
            printf "%3s : %-8s %-15s %23s" $i "$time" "$ip" "$id"
            echo " - $location"
          done < /opt/piavpn-manual/latencyList
          echo

          # Receive input to specify the server to connect to manually
          while :; do
            read -r -p "Input the number of the server you want to connect to ([1]-[$i]) : " serverSelection
              if [[ -z $serverSelection ]]; then
                echo -e "\n${red}You must provide input.${nc}\n"
              elif ! [[ $serverSelection =~ $intCheck ]]; then
                echo -e "\n${red}You must enter a number.${nc}\n"
              elif [[ $serverSelection -lt 1 ]]; then
                echo -e "\n${red}You must enter a number greater than 1.${nc}\n"
              elif [[ $serverSelection -gt $i ]]; then
                echo -e "\n${red}You must enter a number between 1 and $i.${nc}\n"
              else
                PREFERRED_REGION=$( awk 'NR == '"$serverSelection"' {print $2}' /opt/piavpn-manual/latencyList )
                echo
                echo -e "${green}PREFERRED_REGION=$PREFERRED_REGION${nc}"
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
        echo -e "${green}You will auto-connect to the server with the lowest latency.${nc}"
        echo
        break
      fi
    else
      # Validate in-line declaration of PREFERRED_REGION; if invalid remove input to initiate prompts
      echo "Region input is : $PREFERRED_REGION"
      export PREFERRED_REGION
      VPN_PROTOCOL=no ./get_region.sh
      if [[ $? != 1 ]]; then
        break
      fi
      PREFERRED_REGION=""
    fi
  done
fi

if [[ -z $VPN_PROTOCOL ]]; then
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
    read -r connection_method
    echo

    VPN_PROTOCOL="wireguard"
    if echo "${connection_method:0:1}" | grep -iq o; then
      echo -n "Connection method ([U]dp/[t]cp): "
      read -r protocolInput
      echo

      protocol="udp"
      if echo "${protocolInput:0:1}" | grep -iq t; then
        protocol="tcp"
      fi

      echo "Higher levels of encryption trade performance for security. "
      echo -n "Do you want to use strong encryption ([N]o/[y]es): "
      read -r strongEncryption
      echo

      encryption="standard"
      if echo "${strongEncryption:0:1}" | grep -iq y; then
        encryption="strong"
      fi

      VPN_PROTOCOL="openvpn_${protocol}_${encryption}"
    fi
    ;;
esac
export VPN_PROTOCOL
echo -e "${green}VPN_PROTOCOL=$VPN_PROTOCOL
${nc}"

# Check for the required presence of resolvconf for setting DNS on wireguard connections
setDNS="yes"
if ! command -v resolvconf &>/dev/null && [[ $VPN_PROTOCOL == "wireguard" ]]; then
  echo -e "${red}The resolvconf package could not be found."
  echo "This script can not set DNS for you and you will"
  echo -e "need to invoke DNS protection some other way.${nc}"
  echo
  setDNS="no"
fi

# Check for in-line definition of PIA_DNS and prompt for input
if [[ $setDNS == "yes" ]]; then
  if [[ -z $PIA_DNS ]]; then
    echo "Using third party DNS could allow DNS monitoring."
    echo -n "Do you want to force PIA DNS ([Y]es/[n]o): "
    read -r setDNS
    echo
    PIA_DNS="true"
    if echo "${setDNS:0:1}" | grep -iq n; then
      PIA_DNS="false"
    fi
  fi
elif [[ $PIA_DNS != "true" || $setDNS == "no" ]]; then
  PIA_DNS="false"
fi
export PIA_DNS
echo -e "${green}PIA_DNS=$PIA_DNS${nc}"

CONNECTION_READY="true"
export CONNECTION_READY

if [[ -z $DIP_TOKEN ]]; then
  ./get_region.sh
elif [[ $VPN_PROTOCOL == wireguard ]]; then
  echo
  echo -e "You will be connecting with ${green}WG_SERVER_IP=$dipAddress${nc} using"
  echo -e "${green}VPN_PROTOCOL=wireguard${nc}, so we will automatically connect to WireGuard,"
  echo "by running this command:"
  echo -e "$ ${green}PIA_PF=$PIA_PF PIA_TOKEN=$PIA_TOKEN" \\
  echo "DIP_TOKEN=$DIP_TOKEN" \\
  echo "WG_SERVER_IP=$dipAddress WG_HOSTNAME=$dipHostname" \\
  echo -e "./connect_to_wireguard_with_token.sh${nc}"
  echo
  PIA_PF=$PIA_PF PIA_TOKEN=$PIA_TOKEN DIP_TOKEN=$DIP_TOKEN \
    WG_SERVER_IP=$dipAddress WG_HOSTNAME=$dipHostname \
    ./connect_to_wireguard_with_token.sh
  rm -f /opt/piavpn-manual/latencyList
  exit 0
elif [[ $VPN_PROTOCOL == openvpn* ]]; then
  echo
  echo "The dedicated IP connection will be started with"
  echo -e "${green}VPN_PROTOCOL=$VPN_PROTOCOL${nc}, so we will automatically"
  echo "connect to OpenVPN, by running this command:"
  echo -e "$ ${green}PIA_PF=$PIA_PF PIA_TOKEN=$PIA_TOKEN" \\
  echo   "DIP_TOKEN=$DIP_TOKEN OVPN_SERVER_IP=$dipAddress" \\
  echo   "OVPN_HOSTNAME=$dipHostname" \\
  echo   "CONNECTION_SETTINGS=$VPN_PROTOCOL" \\
  echo -e "./connect_to_openvpn_with_token.sh${nc}"
  echo
  PIA_PF=$PIA_PF PIA_TOKEN=$PIA_TOKEN \
    DIP_TOKEN=$DIP_TOKEN OVPN_SERVER_IP=$dipAddress \
    OVPN_HOSTNAME=$dipHostname \
    CONNECTION_SETTINGS=$VPN_PROTOCOL \
    ./connect_to_openvpn_with_token.sh
  rm -f /opt/piavpn-manual/latencyList
  exit 0
fi
