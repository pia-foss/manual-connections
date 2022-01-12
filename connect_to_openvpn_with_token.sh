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
parent_folder=$(dirname $(realpath $0))

# This function allows you to check if the required tools have been installed.
function check_tool() {
  cmd=$1
  if ! command -v $cmd &>/dev/null
  then
    echo "$cmd could not be found"
    echo "Please install $cmd"
    exit 1
  fi
}
# Now we call the function to make sure we can use wg-quick, curl and jq.
check_tool curl
check_tool jq
check_tool openvpn

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

# Check if manual PIA OpenVPN connection is already initialized.
# Multi-hop is out of the scope of this repo, but you should be able to
# get multi-hop running with both OpenVPN and WireGuard.
adapter_check="$( ip a s tun06 2>&1 )"
should_read="Device \"tun06\" does not exist"
pid_filepath="/opt/piavpn-manual/pia_pid"
if [[ "$adapter_check" != *"$should_read"* ]]; then
  echo -e ${RED}The tun06 adapter already exists, that interface is required
  echo -e for this configuration.${NC}
  if [ -f "$pid_filepath" ]; then
    old_pid="$( cat "$pid_filepath" )"
    old_pid_name="$( ps -p "$old_pid" -o comm= )"
    if [[ $old_pid_name == 'openvpn' ]]; then
      echo
      echo -e It seems likely that process ${RED}$old_pid${NC} is an OpenVPN connection
      echo that was established by using this script. Unless it is closed
      echo you would not be able to get a new connection.
      echo -ne "Do you want to run ${RED}$ kill $old_pid${NC} (Y/n): "
      read close_connection
    fi
    if echo ${close_connection:0:1} | grep -iq n ; then
      echo -e ${RED}Closing script. Resolve tun06 adapter conflict and run the script again.
      exit 1
    fi
    echo
    echo -e ${GREEN}Killing the existing OpenVPN process and waiting 5 seconds...${NC}
    kill $old_pid
    echo
    for i in {5..1}; do
      echo -n "$i..."
      sleep 1
      done
    echo
    echo
  fi
fi

# PIA currently does not support IPv6. In order to be sure your VPN
# connection does not leak, it is best to disabled IPv6 altogether.
# IPv6 can also be disabled via kernel commandline param, so we must
# first check if this is the case.
if [[ -f /proc/net/if_inet6 ]] &&
  [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -ne 1 ||
     $(sysctl -n net.ipv6.conf.default.disable_ipv6) -ne 1 ]]
then
  echo -e ${RED}'You should consider disabling IPv6 by running:'
  echo 'sysctl -w net.ipv6.conf.all.disable_ipv6=1'
  echo -e 'sysctl -w net.ipv6.conf.default.disable_ipv6=1'${NC}
fi

#  Check if the mandatory environment variables are set.
if [[ ! $OVPN_SERVER_IP ||
  ! $OVPN_HOSTNAME ||
  ! $PIA_TOKEN ||
  ! $CONNECTION_SETTINGS ]]; then
  echo -e ${RED}'This script requires 4 env vars:'
  echo 'PIA_TOKEN           - the token used for authentication'
  echo 'OVPN_SERVER_IP      - IP that you want to connect to'
  echo 'OVPN_HOSTNAME       - name of the server, required for ssl'
  echo 'CONNECTION_SETTINGS - the protocol and encryption specification'
  echo '                    - available options for CONNECTION_SETTINGS are:'
  echo '                        * openvpn_udp_standard'
  echo '                        * openvpn_udp_strong'
  echo '                        * openvpn_tcp_standard'
  echo '                        * openvpn_tcp_strong'
  echo
  echo You can also specify optional env vars:
  echo "PIA_PF                - enable port forwarding"
  echo "PAYLOAD_AND_SIGNATURE - In case you already have a port."
  echo
  echo An easy solution is to just run get_region_and_token.sh
  echo as it will guide you through getting the best server and
  echo also a token. Detailed information can be found here:
  echo -e https://github.com/pia-foss/manual-connections ${NC}
  exit 1
fi

# Create a credentials file with the login token
echo -n "Trying to write /opt/piavpn-manual/pia.ovpn..."
mkdir -p /opt/piavpn-manual
rm -f /opt/piavpn-manual/credentials /opt/piavpn-manual/route_info
echo ${PIA_TOKEN:0:62}"
"${PIA_TOKEN:62} > /opt/piavpn-manual/credentials || exit 1
chmod 600 /opt/piavpn-manual/credentials
echo -e "${GREEN}OK!${NC}"

# Translate connection settings variable
IFS='_'
read -ra connection_settings <<< "$CONNECTION_SETTINGS"
IFS=' '
protocol="${connection_settings[1]}"
encryption="${connection_settings[2]}"

open_vpn_config_path=$parent_folder/openvpn_config
prefix_filepath="$open_vpn_config_path/standard.ovpn"
if [[ $encryption == "strong" ]]; then
  prefix_filepath="$open_vpn_config_path/strong.ovpn"
fi

if [[ $protocol == "udp" ]]; then
  if [[ $encryption == "standard" ]]; then
    port=1198
  else
    port=1197
  fi
else
  if [[ $encryption == "standard" ]]; then
    port=502
  else
    port=501
  fi
fi

# Create the OpenVPN config based on the settings specified
cat $prefix_filepath > /opt/piavpn-manual/pia.ovpn || exit 1
echo remote $OVPN_SERVER_IP $port $protocol >> /opt/piavpn-manual/pia.ovpn

# Copy the up/down scripts to /opt/piavpn-manual/
# based upon use of PIA DNS
if [ "$PIA_DNS" != true ]; then
  cp $open_vpn_config_path/openvpn_up.sh /opt/piavpn-manual/
  cp $open_vpn_config_path/openvpn_down.sh /opt/piavpn-manual/
  echo -e ${RED}This configuration will not use PIA DNS.${NC}
  echo If you want to also enable PIA DNS, please start the script
  echo with the env var PIA_DNS=true. Example:
  echo $ OVPN_SERVER_IP=\"$OVPN_SERVER_IP\" OVPN_HOSTNAME=\"$OVPN_HOSTNAME\" \
    PIA_TOKEN=\"$PIA_TOKEN\" CONNECTION_SETTINGS=\"$CONNECTION_SETTINGS\" \
    PIA_PF=true PIA_DNS=true $parent_folder/connect_to_openvpn_with_token.sh
else
  cp $openvpn_config_path/openvpn_up_dnsoverwrite.sh /opt/piavpn-manual/openvpn_up.sh
  cp $openvpn_config_path/openvpn_down_dnsoverwrite.sh /opt/piavpn-manual/openvpn_down.sh
fi

# Start the OpenVPN interface.
# If something failed, stop this script.
# If you get DNS errors because you miss some packages,
# just hardcode /etc/resolv.conf to "nameserver 10.0.0.242".
#rm -f /opt/piavpn-manual/debug_info
echo "
Trying to start the OpenVPN connection..."
openvpn --daemon \
  --config "/opt/piavpn-manual/pia.ovpn" \
  --writepid "/opt/piavpn-manual/pia_pid" \
  --log "/opt/piavpn-manual/debug_info" || exit 1

echo -n "
The OpenVPN connect command was issued.

Confirming OpenVPN connection state..."

# Check if manual PIA OpenVPN connection is initialized.
# Manually adjust the connection_wait_time if needed
connection_wait_time=10
confirmation="Initialization Sequence Complete"
for (( timeout=0; timeout <=$connection_wait_time; timeout++ ))
do
  sleep 1
  if grep -q "$confirmation" /opt/piavpn-manual/debug_info; then
    connected=true
    break
  fi
done

ovpn_pid="$( cat /opt/piavpn-manual/pia_pid )"
gateway_ip="$( cat /opt/piavpn-manual/route_info )"

# Report and exit if connection was not initialized within 10 seconds.
if [ "$connected" != true ]; then
  echo -e "${RED}The VPN connection was not established within 10 seconds.${NC}"
  kill $ovpn_pid
  exit 1
fi

echo -e "${GREEN}Initialization Sequence Complete!${NC}

At this point, internet should work via VPN.
"

echo -e "OpenVPN Process ID: ${GREEN}$ovpn_pid${NC}
VPN route IP: ${GREEN}$gateway_ip${NC}

To disconnect the VPN, run:

--> ${GREEN}sudo kill $ovpn_pid${NC} <--
"

# This section will stop the script if PIA_PF is not set to "true".
if [ "$PIA_PF" != true ]; then
  echo If you want to also enable port forwarding, you can start the script:
  echo -e $ ${GREEN}PIA_TOKEN=$PIA_TOKEN \
    PF_GATEWAY=$gateway_ip \
    PF_HOSTNAME=$OVPN_HOSTNAME \
    $parent_folder/port_forwarding.sh${NC}
  echo
  echo The location used must be port forwarding enabled, or this will fail.
  echo Calling the $parent_folder/get_region script with PIA_PF=true will provide a filtered list.
  exit 1
fi

echo -ne "This script got started with ${GREEN}PIA_PF=true${NC}.

Starting port forwarding in "
for i in {5..1}; do
  echo -n "$i..."
  sleep 1
done
echo
echo

echo -e "Starting procedure to enable port forwarding by running the following command:
$ ${GREEN}PIA_TOKEN=$PIA_TOKEN \\
  PF_GATEWAY=$gateway_ip \\
  PF_HOSTNAME=$OVPN_HOSTNAME \\
  $parent_folder/port_forwarding.sh${NC}"

PIA_TOKEN=$PIA_TOKEN \
  PF_GATEWAY=$gateway_ip \
  PF_HOSTNAME=$OVPN_HOSTNAME \
  $parent_folder/port_forwarding.sh
