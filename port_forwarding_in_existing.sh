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

if [[ ! $PIA_USER || ! $PIA_PASS || ! $PIA_HOSTNAME || ! $PIA_GATEWAY ]]; then
  echo 'This script requires 4 env vars:'
  echo 'PIA_USER            - PIA username'
  echo 'PIA_PASS            - PIA password'
  echo 'PIA_HOSTNAME        - name of the server, required for ssl'
  echo 'PIA_GATEWAY         - the vpn gateway you are connected to.'
  exit 1
fi

token="$(PIA_SERVER_META_HOSTNAME=$PIA_HOSTNAME \
  PIA_SERVER_META_IP=10.0.0.1 \
  PIA_USER=$PIA_USER \
  PIA_PASS=$PIA_PASS \
  ./get_token.sh)"

if [[ -z "$token" ]]; then
  echo "Error: Could not get token."
  exit 1
fi

PIA_TOKEN="$token" \
  PF_GATEWAY="$PIA_GATEWAY" \
  PF_HOSTNAME="$PIA_HOSTNAME" \
  ./port_forwarding.sh
