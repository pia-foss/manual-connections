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
check_tool() {
  cmd=$1
  if ! command -v $cmd &>/dev/null; then
    echo "$cmd could not be found"
    echo "Please install $cmd"
    exit 1
  fi
}

# Now we call the function to make sure we can use curl and jq.
check_tool curl
check_tool jq

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

if [[ -z $PIA_TOKEN ]]; then
  echo "If you want this script to automatically retrieve dedicated IP location details"
  echo "from the Meta service, please add the variables PIA_TOKEN and DIP_TOKEN. Example:"
  echo "$ PIA_TOKEN DIP_TOKEN=DIP1a2b3c4d5e6f7g8h9i10j11k12l13 ./get_token.sh"
  exit 1
fi

dipSavedLocation=/opt/piavpn-manual/dipAddress

echo -n "Checking DIP token..."

generateDIPResponse=$(curl -s --location --request POST \
  'https://www.privateinternetaccess.com/api/client/v2/dedicated_ip' \
  --header 'Content-Type: application/json' \
  --header "Authorization: Token $PIA_TOKEN" \
  --data-raw '{
    "tokens":["'"$DIP_TOKEN"'"]
  }')

if [ "$(echo "$generateDIPResponse" | jq -r '.[0].status')" != "active" ]; then
  echo
  echo
  echo -e "${red}Could not validate the dedicated IP token provided!${nc}"
  echo
  exit
fi
  
echo -e ${green}OK!${nc}
echo
dipAddress=$(echo "$generateDIPResponse" | jq -r '.[0].ip')
dipHostname=$(echo "$generateDIPResponse" | jq -r '.[0].cn')
keyHostname=$(echo "dedicated_ip_$DIP_TOKEN")
dipExpiration=$(echo "$generateDIPResponse" | jq -r '.[0].dip_expire')
dipExpiration=$(date -d @$dipExpiration)
dipID=$(echo "$generateDIPResponse" | jq -r '.[0].id')
echo -e The hostname of your dedicated IP is ${green}$dipHostname${nc}
echo
echo -e The dedicated IP address is ${green}$dipAddress${nc}
echo 
echo This dedicated IP is valid until $dipExpiration.
echo
pfCapable="true"
if [[ $dipID == us_* ]]; then
  pfCapable="false"
  echo This location does not have port forwarding capability.
  echo
fi
echo $dipAddress > /opt/piavpn-manual/dipAddress || exit 1
echo $dipHostname >> /opt/piavpn-manual/dipAddress
echo $keyHostname >> /opt/piavpn-manual/dipAddress
echo $dipExpiration >> /opt/piavpn-manual/dipAddress
echo $pfCapable >> /opt/piavpn-manual/dipAddress
