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
  if ! command -v $cmd &>/dev/null
  then
    echo "$cmd could not be found"
    echo "Please install $cmd"
    exit 1
  fi
}

# This function creates a timestamp, to use for setting $TOKEN_EXPIRATION
function timeout_timestamp() {
  date +"%c" --date='1 day' # Timestamp 24 hours
}

# Now we call the function to make sure we can use curl and jq.
check_tool curl
check_tool jq

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

# Only allow script to run as
if [ "$(whoami)" != "root" ]; then
  echo -e "${RED}This script needs to be run as root. Try again with 'sudo $0'${NC}"
  exit 1
fi

mkdir -p /opt/piavpn-manual

if [[ ! $PIA_USER || ! $PIA_PASS ]]; then
  echo If you want this script to automatically get a token from the Meta
  echo service, please add the variables PIA_USER and PIA_PASS. Example:
  echo $ PIA_USER=p0123456 PIA_PASS=xxx ./get_token.sh
  exit 1
fi

tokenLocation=/opt/piavpn-manual/token

echo -n "Checking login credentials..."

generateTokenResponse=$(curl -s -u "$PIA_USER:$PIA_PASS" \
  "https://privateinternetaccess.com/gtoken/generateToken")

if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
  echo
  echo
  echo -e "${RED}Could not authenticate with the login credentials provided!${NC}"
  echo
  exit
fi
  
echo -e ${GREEN}OK!
echo
token=$(echo "$generateTokenResponse" | jq -r '.token')
tokenExpiration=$(timeout_timestamp)
echo -e PIA_TOKEN=$token${NC}
echo $token > /opt/piavpn-manual/token || exit 1
echo $tokenExpiration >> /opt/piavpn-manual/token
echo 
echo This token will expire in 24 hours, on $tokenExpiration.
echo
