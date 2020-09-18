#!/bin/bash

# PIA currently does not support IPv6. In order to be sure your VPN
# connection does not leak, it is best to disabled IPv6 altogether.
echo 'You should consider disabling IPv6 by running:
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
'

# check if the wireguard tools have been installed
if ! command -v wg-quick &> /dev/null
then
    echo "wg-quick could not be found."
    echo "Please install wireguard-tools"
    exit 1
fi

# Check if the mandatory environment variables are set.
if [[ ! $WG_SERVER_IP || ! $WG_HOSTNAME || ! $WG_TOKEN ]]; then
  echo This script requires 3 env vars:
  echo WG_SERVER_IP - IP that you want to connect to
  echo WG_HOSTNAME  - name of the server, required for ssl
  echo WG_TOKEN     - your authentication token
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
  --data-urlencode "pt=${WG_TOKEN}" \
  --data-urlencode "pubkey=$pubKey" \
  "https://${WG_HOSTNAME}:1337/addKey" )"
export wireguard_json
echo "$wireguard_json"

# Check if the API returned OK and stop this script if it didn't.
if [ "$(echo "$wireguard_json" | jq -r '.status')" != "OK" ]; then
  >&2 echo "Server did not return OK. Stopping now."
  exit 1
fi

# Create the WireGuard config based on the JSON received from the API
# The config does not contain a DNS entry, since some servers do not
# have resolvconf, which will result in the script failing.
# We will enforce the DNS after the connection gets established.
echo -n "Trying to write /etc/wireguard/pia.conf... "
echo "
[Interface]
Address = $(echo "$wireguard_json" | jq -r '.peer_ip')
PrivateKey = $privKey
## If you want wg-quick to also set up your DNS, uncomment the line below.
# DNS = $(echo "$json" | jq -r '.dns_servers[0]')

[Peer]
PublicKey = $(echo "$wireguard_json" | jq -r '.server_key')
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:$(echo "$wireguard_json" | jq -r '.server_port')
" > /etc/wireguard/pia.conf || exit 1
echo OK!

# Start the WireGuard interface.
# If something failed, stop this script.
# If you get DNS errors because you miss some packages,
# just can hardcode /etc/resolv.conf to "nameserver 10.0.0.242".
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
  echo $ WG_SERVER=10.0.0.3 WG_HOSTNAME=piaserver401 \
    WG_TOKEN=\"\$token\" PIA_PF=true \
    ./sort_regions_by_latency.sh
  exit
fi

echo "
This script got started with PIA_PF=true.
Starting procedure to enable port forwarding."

# The port forwarding system has required two variables:
# PAYLOAD: contains the token, the port and the expiration date
# SIGNATURE: certifies the payload originates from the PIA network.

# Basically PAYLOAD+SIGNATURE=PORT. You can use the same PORT on all servers.
# The system has been designed to be completely decentralized, so that your
# privacy is protected even if you want to host services on your systems.

# You can get your PAYLOAD+SIGNATURE with a simple curl request to any VPN
# gateway, no matter what protocol you are using.
# Since this is the script for wireguard, you can just get the gateway
# from the JSON response you got at the previous step from the Wireguard API.
gateway="$(echo "$wireguard_json" | jq -r '.server_vip')"

# Get the payload and the signature from the PF API. This will grant you
# access to a random port, which you can activate on any server you connect to.
# If you already have a signature, and you would like to re-use that port,
# save the payload_and_signature received from your previous request
# in the env var PAYLOAD_AND_SIGNATURE, and that will be used instead.
if [[ ! $PAYLOAD_AND_SIGNATURE ]]; then
  echo "Getting new signature..."
  payload_and_signature="$(curl -s -m 5 \
    --connect-to "$WG_HOSTNAME::$gateway:" \
    --cacert "ca.rsa.4096.crt" \
    -G --data-urlencode "token=${WG_TOKEN}" \
    "https://${WG_HOSTNAME}:19999/getSignature")"
else
  payload_and_signature="$PAYLOAD_AND_SIGNATURE"
  echo "Using the following payload_and_signature from the env var:"
fi
echo "$payload_and_signature"
export payload_and_signature

# Check if the payload and the signature are OK.
# If they are not OK, just stop the script.
if [ "$(echo "$payload_and_signature" | jq -r '.status')" != "OK" ]; then
  echo "The payload_and_signature variable does not contain an OK status."
  exit 1
fi

# We need to get the signature out of the previous response.
# The signature will allow the us to bind the port on the server.
signature="$(echo "$payload_and_signature" | jq -r '.signature')"

# The payload has a base64 format. We need to extract it from the
# previous reponse and also get the following information out:
# - port: This is the port you got access to
# - expires_at: this is the date+time when the port expires
payload="$(echo "$payload_and_signature" | jq -r '.payload')"
port="$(echo "$payload" | base64 -d | jq -r '.port')"

# The port normally expires after 2 months. If you consider
# 2 months is not enough for your setup, please open a ticket.
expires_at="$(echo "$payload" | base64 -d | jq -r '.expires_at')"

# Display some information on the screen for the user.
echo "The signature is OK.

--> The port is $port and it will expire on $expires_at. <--

Trying to bind the port..."

# Now we have all required data to create a request to bind the port.
# We will repeat this request every 15 minutes, in order to keep the port
# alive. The servers have no mechanism to track your activity, so they
# will just delete the port forwarding if you don't send keepalives.
while true; do
  bind_port_response="$(curl -Gs -m 5 \
    --connect-to "$WG_HOSTNAME::$gateway:" \
    --cacert "ca.rsa.4096.crt" \
    --data-urlencode "payload=${payload}" \
    --data-urlencode "signature=${signature}" \
    "https://${WG_HOSTNAME}:19999/bindPort")"
    echo "$bind_port_response"

    # If port did not bind, just exit the script.
    # This script will exit in 2 months, since the port will expire.
    export bind_port_response
    if [ "$(echo "$bind_port_response" | jq -r '.status')" != "OK" ]; then
      echo "The API did not return OK when trying to bind port. Exiting."
      exit 1
    fi
    echo Port $port refreshed on $(date). \
      This port will expire on $(date --date="$expires_at")

    # sleep 15 minutes
    sleep 900
done
