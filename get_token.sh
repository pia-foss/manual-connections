if [[ ! $PIA_USER || ! $PIA_PASS ]]; then
  echo If you want this script to automatically get a token from the Meta
  echo service, please add the variables PIA_USER and PIA_PASS. Example:
  echo $ PIA_USER=p0123456 PIA_PASS=xxx ./get_region_and_token.sh
  exit 1
fi

echo "The ./get_region_and_token.sh script got started with PIA_USER and PIA_PASS,
so we will also use a meta service to get a new VPN token."

echo "Trying to get a new token by authenticating with the meta service..."
generateTokenResponse=$(curl -s -u "$PIA_USER:$PIA_PASS" \
  --connect-to "$bestServer_meta_hostname::$bestServer_meta_IP:" \
  --cacert "ca.rsa.4096.crt" \
  "https://$bestServer_meta_hostname/authv3/generateToken")
echo "$generateTokenResponse"

if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
  echo "Could not get a token. Please check your account credentials."
  echo
  echo "You can also try debugging by manually running the curl command:"
  echo $ curl -vs -u "$PIA_USER:$PIA_PASS" --cacert ca.rsa.4096.crt \
    --connect-to "$bestServer_meta_hostname::$bestServer_meta_IP:" \
    https://$bestServer_meta_hostname/authv3/generateToken
  exit 1
fi

token="$(echo "$generateTokenResponse" | jq -r '.token')"
echo "This token will expire in 24 hours.
"
