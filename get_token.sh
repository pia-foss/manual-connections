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

if [[ ! $PIA_USER || ! $PIA_PASS || ! $PIA_SERVER_META_IP || ! $PIA_SERVER_META_HOSTNAME ]]; then
  1>&2 echo If you want this script to automatically get a token from
  1>&2 echo the Meta service, please add the variables PIA_USER,
  1>&2 echo PIA_PASS, PIA_SERVER_META_IP, and PIA_SERVER_META_HOSTNAME.
  1>&2 echo Example:
  1>&2 echo $ PIA_USER=p0123456 PIA_PASS=xxx PIA_SERVER_META_IP=x.x.x.x 
  1>&2 echo PIA_SERVER_META_HOSTNAME=xxx ./get_token.sh
  exit 1
fi

1>&2 echo "The ./get_token.sh script got started with PIA_USER and PIA_PASS and PIA_SERVER_META_HOSTNAME and PIA_SERVER_META_IP,
 so we will also use a meta service to get a new VPN token."

1>&2 echo "Trying to get a new token by authenticating with the meta service..."
generateTokenResponse=$(curl -s -u "$PIA_USER:$PIA_PASS" \
  --connect-to "$PIA_SERVER_META_HOSTNAME::$PIA_SERVER_META_IP:" \
  --cacert "ca.rsa.4096.crt" \
  "https://$PIA_SERVER_META_HOSTNAME/authv3/generateToken")
1>&2 echo "$generateTokenResponse"

if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
  1>&2 echo "Could not get a token. Please check your account credentials."
  1>&2 echo
  1>&2 echo "You can also try debugging by manually running the curl command:"
  1>&2 echo $ curl -vs -u "$PIA_USER:$PIA_PASS" --cacert ca.rsa.4096.crt \
    --connect-to "$PIA_SERVER_META_HOSTNAME::$PIA_SERVER_META_IP:" \
    https://$PIA_SERVER_META_HOSTNAME/authv3/generateToken
  exit 1
fi

token="$(echo "$generateTokenResponse" | jq -r '.token')"
1>&2 echo "This token will expire in 24 hours.
"

echo $token
