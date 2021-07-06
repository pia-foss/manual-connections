#!/bin/bash

#init global variables
owrt_pf=$(realpath $0)
owrt_pf_dir=$(dirname $owrt_pf)
owrt_ov_filename=$(basename -- "$config")
owrt_ov_filename="${owrt_ov_filename%.*}"
owrt_ov_filename="/var/run/${owrt_ov_filename//-/.}"

cd "$owrt_pf_dir"

function log() {
  logger -s -p daemon.info -t pia "$1"  
}

function warn() {
  logger -s -p daemon.warning -t pia "$1"  
}

function err() {
  logger -s -p daemon.err -t pia "$1"  
}

function StoreOpenVPNVariables() {
  # Write gateway IP and common name of the current OpenVPN connection 
  echo $route_vpn_gateway >"$owrt_ov_filename.route_info"
  echo $common_name >"$owrt_ov_filename.common_name"
}

function StorePayloadAndSignature() {
  # this saves payload and signature in various files

  echo "$payload_and_signature" >"$owrt_ov_filename.pia_bindport_pns"
    
  payload="$(echo "$payload_and_signature" | jq -r '.payload')"
  decoded_payload="$(echo "$payload" | base64 -d)"
  
  echo "$decoded_payload" >"$owrt_ov_filename.pia_bindport_decoded_payload"
}

function UpdateFirewallRule() {
  previous_port="$(uci get firewall.pia_port_forward.src_dport 2>/dev/null)"

  if [ "$previous_port" == "$PIA_PORT" ]; then
    return 0 
  fi

  uci -q delete firewall.pia_port_forward

  uci batch <<EOT
  set firewall.pia_port_forward=redirect
  set firewall.pia_port_forward.name="PIA Port Forward"
  set firewall.pia_port_forward.src=vpn  
  set firewall.pia_port_forward.src_dport=$PIA_PORT
  set firewall.pia_port_forward.dest=lan
  set firewall.pia_port_forward.dest_ip="192.168.0.13" 
  set firewall.pia_port_forward.dest_port=$PIA_PORT
EOT

  uci commit

  /etc/init.d/firewall reload &>/dev/null
}

#script start code
if [[ $script_type && $config ]]; then
  # we are inside OpenVPN script
  
  StoreOpenVPNVariables

  exit 0
fi

if [[ $OWRT_PF_INTERNAL_RUN ]]; then
  # we are called from the port_forwarding.sh script

  StorePayloadAndSignature

  exit 0 
fi

#first try to fetch current token and payload_and_signature

pia_cached_token=$(cat "$owrt_ov_filename.pia_token" 2>/dev/null) 
pia_payload_and_signature=$(cat "$owrt_ov_filename.pia_bindport_pns" 2>/dev/null)

if [[ ! $pia_cached_token || ! "$pia_payload_and_signature" ]]; then
  #if one of them is not available, generate new ones
  log "Token or payload and signature are not cached. Generating new ones... "

  #avoid in case of errors to run another time
  export OWRT_PF_SECOND_RUN=1

  declare $( ./get_token.sh | grep PIA_TOKEN=)
  export PIA_TOKEN=$PIA_TOKEN

  echo "$PIA_TOKEN" >"$owrt_ov_filename.pia_token"

  log "Generated token: $PIA_TOKEN"
else
  log "Token, payload and signature found in the cache."

  export PIA_TOKEN=$pia_cached_token
  export PAYLOAD_AND_SIGNATURE="$pia_payload_and_signature"
fi

# fetch information about the current openvpn connection

export PF_GATEWAY=$(cat "$owrt_ov_filename.route_info")
export PF_HOSTNAME=$(cat "$owrt_ov_filename.common_name")
export PF_SUCCESS_EXTERNAL_SCRIPT="$owrt_pf"
export PF_KEEPALIVE=0
export OWRT_PF_INTERNAL_RUN=1

./port_forwarding.sh >/dev/null

if [[ $? -ne 0 && ! $OWRT_PF_SECOND_RUN ]]; then
  warn "An unexpected error occurred while forwarding the port from PIA. Regenerating token, payload and signature..."
 
  unset OWRT_PF_INTERNAL_RUN
  
  rm "$owrt_ov_filename.pia_token"
  rm "$owrt_ov_filename.pia_bindport_pns"

  export OWRT_PF_SECOND_RUN=1
 
  "$owrt_pf"

  if [[ $? -ne 0 ]]; then
    err "An unexpected error occurred while forwarding the port from PIA. Please check your connection."

    exit 1
  fi
fi

#if we arrive here the port_forwarding.sh has been successfull

decoded_payload="$(cat "$owrt_ov_filename.pia_bindport_decoded_payload")"
if [[ $OWRT_PF_SECOND_RUN -eq 1 ]]; then    
  log "Generated payload: $decoded_payload"
fi
  
echo "$decoded_payload" >/www/pia_pf.json

port="$(echo "$decoded_payload" | jq -r '.port')"
expires_at="$(echo "$decoded_payload" | jq -r '.expires_at')"

export PIA_PORT=$port

UpdateFirewallRule

log "Port is $port and expires at $expires_at"

exit 0

