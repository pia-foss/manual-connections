#!/usr/bin/env bash

: "${PIA_CONF_PATH:=/etc/swanctl/conf.d/pia.conf}"
: "${PIA_CA_PATH:=/etc/swanctl/x509ca/}"
: "${DIP_TOKEN:=}"
: "${CONNECT_POST_HOOK:=}"
: "${CONNECT_PRE_HOOK:=}"

log() {
    USE_LOGGER=${USE_LOGGER:-""}
    if [[ -n $USE_LOGGER ]]; then
        logger -t pia "$@"
    else
        echo "$@"
    fi
}

check_tool() {
    cmd=$1
    pkg=$2
    if ! command -v "$cmd" >/dev/null; then
        log "$cmd could not be found"
        log "Please install $pkg"
        exit 1
    fi
}

check_tool swanctl strongswan
check_tool curl curl
check_tool jq jq

if [[ -f /proc/net/if_inet6 ]] && [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -ne 1 || $(sysctl -n net.ipv6.conf.default.disable_ipv6) -ne 1 ]]; then
    log "WARN: IPv6 traffic will go without VPN"
fi

if [[ -z $IKEV2_SERVER_IP || -z $IKEV2_HOSTNAME || -z $PIA_TOKEN ]]; then
    log "IKEV2_SERVER_IP, IKEV2_HOSTNAME and PIA_TOKEN must be defined"
    exit 1
fi

set_ikev2_creds_from_api () {
    log "Requesting IKEv2 VPN token"
    local result=$(curl --fail -X POST https://privateinternetaccess.com/api/client/v5/vpn_token -H Content-Type:application/json -H Accept:application/json -H "Authorization:Token $PIA_TOKEN")
    if [[ $? -ne 0 ]]; then
        log "Failed to fetch vpn token"
        exit 1
    fi
    log "Saving IKEv2 VPN token"
    echo "$result" > /opt/piavpn-manual/vpn_token
    IKEV2_USERNAME=$(log "$result" | jq -r .vpn_secret1)
    IKEV2_PASSWORD=$(log "$result" | jq -r .vpn_secret2)
}

recover_ikev2_creds () {
    if [[ -f /opt/piavpn-manual/vpn_token ]]; then
        target_iso=$(cat /opt/piavpn-manual/vpn_token | jq -r .expires_at)
        target=$(date -u -d "$target_iso" +%s)
        now=$(date -u +%s)
        if [ "$now" -lt "$target" ]; then
            log "Re-using the vpn token expires at $target_iso"
            IKEV2_USERNAME=$(cat /opt/piavpn-manual/vpn_token | jq -r .vpn_secret1)
            IKEV2_PASSWORD=$(cat /opt/piavpn-manual/vpn_token | jq -r .vpn_secret2)
            return 0
        fi
    fi
    return 1
}

if [[ -z $DIP_TOKEN ]]; then
    if ! recover_ikev2_creds; then
        set_ikev2_creds_from_api
    fi
else
    log "DIP is not yet support in the ikev2 script"
    exit 1
fi

log "Trying to write ${PIA_CONF_PATH}..."
log "MTU can be controlled from /etc/strongswan.d/charon/kernel-netlink.conf"
log "DNS can be controlled from /etc/strongswan.d/charon/resolve.conf"
echo "
connections {
  pia {
    local_addrs = 0.0.0.0
    vips = 0.0.0.0
    remote_addrs = $IKEV2_SERVER_IP
    proposals = aes128-sha1-modp2048
    dpd_delay = 30s
    dpd_timeout = 150s

    remote {
      id = $IKEV2_HOSTNAME
    }

    local {
      id = vpn_token_$IKEV2_USERNAME
      auth = eap-mschapv2
      eap_id = vpn_token_$IKEV2_USERNAME
    }

    children {
      default {
        remote_ts  = 0.0.0.0/0
        start_action = start
        dpd_action = restart
      }
    }
  }

  passthrough {
    children {
      local {
        local_ts = 0.0.0.0/0
        remote_ts = 192.168.0.0/16,172.16.0.0/12
        mode = pass
        start_action = trap
      }
    }
  }

}

secrets {
  eap_pia {
    id = vpn_token_$IKEV2_USERNAME
    secret = $IKEV2_PASSWORD
  }
}
" > "${PIA_CONF_PATH}" || (log "Failed to write strongswan config" && exit 1)

# Intermediate cert doesn't seem to be deployed on PIA server, it'll expire and fail
# For now deploy all known intermediate certs locally as well as the root ca.
log "Copying CA files to $PIA_CA_PATH"
if ! cp ikev2_x509ca/*.pem "$PIA_CA_PATH"; then
    log "Failed to copy ca certs"
    exit 1
fi

if [[ -n $CONNECT_PRE_HOOK ]]; then
    log "Running pre-connect hook"
    $CONNECT_PRE_HOOK "$IKEV2_SERVER_IP"
fi

if command -v "rc-service" >/dev/null; then
    rc-service strongswan start || (log "Failed to start strongswan" && exit 1)
else
    log "Only OpenRC is supported for IKEv2 script"
    exit 1
fi

while ! swanctl --list-sas --ike pia | grep -q "pia:.*ESTABLISHED"; do
    log "Waiting for SA to be up"
    sleep 0.5
done

log "IKEv2 is established"

if [[ -n $CONNECT_POST_HOOK ]]; then
    log "Running post-connect hook"
    $CONNECT_POST_HOOK
fi

if [[ $PIA_PF != "true" ]]; then
    log "No port forwarding. End of the script"
    exit 0
fi

export PIA_TOKEN=$PIA_TOKEN
export PF_GATEWAY=$IKEV2_SERVER_IP
export PF_HOSTNAME=$IKEV2_HOSTNAME
. ./port_forwarding.sh
