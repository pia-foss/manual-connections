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

log() {
    USE_LOGGER=${USE_LOGGER:-""}
    if [[ -n $USE_LOGGER ]]; then
        logger -t pia "$@"
    else
        echo "$@"
    fi
}

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

# Check if the mandatory environment variables are set.
if [[ -z $PF_GATEWAY || -z $PIA_TOKEN || -z $PF_HOSTNAME ]]; then
  echo "This script requires 3 env vars:"
  echo "PF_GATEWAY  - the IP of your gateway"
  echo "PF_HOSTNAME - name of the host used for SSL/TLS certificate verification"
  echo "PIA_TOKEN   - the token you use to connect to the vpn services"
  echo
  echo "An easy solution is to just run get_region_and_token.sh"
  echo "as it will guide you through getting the best server and"
  echo "also a token. Detailed information can be found here:"
  echo "https://github.com/pia-foss/manual-connections"
exit 1
fi

# Check if terminal allows output, if yes, define colors for output
red=''
green=''
nc='' # No Color
if [[ -t 1 ]]; then
  ncolors=$(tput colors)
  if [[ -n $ncolors && $ncolors -ge 8 ]]; then
    red=$(tput setaf 1) # ANSI red
    green=$(tput setaf 2) # ANSI green
    nc=$(tput sgr0) # No Color
  fi
fi

# The port forwarding system has required two variables:
# PAYLOAD: contains the token, the port and the expiration date
# SIGNATURE: certifies the payload originates from the PIA network.

# Basically PAYLOAD+SIGNATURE=PORT. You can use the same PORT on all servers.
# The system has been designed to be completely decentralized, so that your
# privacy is protected even if you want to host services on your systems.

# You can get your PAYLOAD+SIGNATURE with a simple curl request to any VPN
# gateway, no matter what protocol you are using. Considering WireGuard has
# already been automated in this repo, here is a command to help you get
# your gateway if you have an active OpenVPN connection:
# $ ip route | head -1 | grep tun | awk '{ print $3 }'
# This section will get updated as soon as we created the OpenVPN script.

# Get the payload and the signature from the PF API. This will grant you
# access to a random port, which you can activate on any server you connect to.
# If you already have a signature, and you would like to re-use that port,
# save the payload_and_signature received from your previous request
# in the env var PAYLOAD_AND_SIGNATURE, and that will be used instead.

PAYLOAD_AND_SIGNATURE=${PAYLOAD_AND_SIGNATURE:-""}

if [[ -f /opt/piavpn-manual/port_forward_token ]]; then
    saved_payload_and_signature=$(cat /opt/piavpn-manual/port_forward_token)
    payload=$(echo "$saved_payload_and_signature" | jq -r '.payload')
    expires_at=$(echo "$payload" | base64 -d | jq -r '.expires_at')
    TARGET_ISO="$expires_at"
    TARGET_SECONDS=$(date -d "$TARGET_ISO" +%s)
    CURRENT_SECONDS=$(date +%s)
    if [ "$CURRENT_SECONDS" -lt "$TARGET_SECONDS" ]; then
        log "Reusing token for port_forwarding"
        PAYLOAD_AND_SIGNATURE=$saved_payload_and_signature
    fi
fi

if [[ -z $PAYLOAD_AND_SIGNATURE ]]; then
  log "Requesting port forward token"
  echo
  echo -n "Getting new signature... "
  payload_and_signature="$(curl -s -m 5 \
    --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
    --cacert "ca.rsa.4096.crt" \
    -G --data-urlencode "token=${PIA_TOKEN}" \
    "https://${PF_HOSTNAME}:19999/getSignature" || true)"
else
  payload_and_signature=$PAYLOAD_AND_SIGNATURE
  echo -n "Checking the payload_and_signature from the env var... "
fi
export payload_and_signature

# Check if the payload and the signature are OK.
# If they are not OK, just stop the script.
if [[ $(echo "$payload_and_signature" | jq -r '.status') != "OK" ]]; then
  log "Invalid port forward token received"
  echo -e "${red}The payload_and_signature variable does not contain an OK status.${nc}"
  exit 1
fi
echo -e "${green}OK!${nc}"

echo "$payload_and_signature" > /opt/piavpn-manual/port_forward_token

# We need to get the signature out of the previous response.
# The signature will allow the us to bind the port on the server.
signature=$(echo "$payload_and_signature" | jq -r '.signature')

# The payload has a base64 format. We need to extract it from the
# previous response and also get the following information out:
# - port: This is the port you got access to
# - expires_at: this is the date+time when the port expires
payload=$(echo "$payload_and_signature" | jq -r '.payload')
port=$(echo "$payload" | base64 -d | jq -r '.port')

# The port normally expires after 2 months. If you consider
# 2 months is not enough for your setup, please open a ticket.
expires_at=$(echo "$payload" | base64 -d | jq -r '.expires_at')

echo -ne "
Signature ${green}$signature${nc}
Payload   ${green}$payload${nc}

--> The port is ${green}$port${nc} and it will expire on ${red}$expires_at${nc}. <--

Trying to bind the port... "

echo "$port" > /opt/piavpn-manual/forwarded_port

PORT_FORWARD_HOOK=${PORT_FORWARD_HOOK:-""}
if [[ -n $PORT_FORWARD_HOOK ]]; then
    log "Running port forward hook"
    $PORT_FORWARD_HOOK "$port"
fi

# Now we have all required data to create a request to bind the port.
# We will repeat this request every 15 minutes, in order to keep the port
# alive. The servers have no mechanism to track your activity, so they
# will just delete the port forwarding if you don't send keepalives.
log "Start polling port forward API"
PORT_FORWARD_MAX_POLL_NUM=${PORT_FORWARD_MAX_POLL_NUM:-0}
current_consecutive_failure_num=0
while [[ $PORT_FORWARD_MAX_POLL_NUM -eq 0 ]] || [[ $current_consecutive_failure_num -lt $PORT_FORWARD_MAX_POLL_NUM ]]; do
  # ignore invalid cert, not all servers are configured correctly.
  bind_port_response="$(curl -k -Gs -m 5 \
    --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
    --data-urlencode "payload=${payload}" \
    --data-urlencode "signature=${signature}" \
    "https://${PF_HOSTNAME}:19999/bindPort" || true)"
    echo -e "${green}OK!${nc}"

    # If port did not bind, just exit the script.
    # This script will exit in 2 months, since the port will expire.
    export bind_port_response
    if [[ $(echo "$bind_port_response" | jq -r '.status') != "OK" ]]; then
        echo -e "${red}The API did not return OK when trying to bind port... Exiting.${nc}"
        log "Port forwarding failed, retrying"
        current_consecutive_failure_num=$((current_consecutive_failure_num + 1))
        sleep 1
        continue
    fi
    current_consecutive_failure_num=0

    echo -e Forwarded port'\t'"${green}$port${nc}"
    echo -e Refreshed on'\t'"${green}$(date)${nc}"
    echo -e Expires on'\t'"${red}$(date --date="$expires_at")${nc}"
    echo -e "\n${green}This script will need to remain active to use port forwarding, and will refresh every 15 minutes.${nc}\n"

    # sleep 15 minutes
    sleep 900 &
    # For signal handler to kick in, make sleep go bg and wait
    wait $!
done

log "Failed to bind port for $PORT_FORWARD_MAX_POLL_NUM"
exit 1
