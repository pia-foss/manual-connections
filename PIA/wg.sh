#!/bin/bash

region="fi"
netname="enp1s0"
vpnname="pia"
localnet="192.168.1.0/24"
certloc="/etc/ssl/certs/pia.rsa.4096.crt"
#services=("transmission-daemon" "jackett" "radarr" "sonarr")
services=()

vpnport="51820/udp"
tools=(wg-quick curl jq resolvconf ufw systemctl)
serverlist_url='https://serverlist.piaservers.net/vpninfo/servers/v4'

retry=5
usage="${0##*/} <start/stop/restart> [pia username] [pia password]"

function parse_args ()
{
    func=$1
    USER=$2
    PASS=$3
}

function check_tool ()
{
  local cmd=$1
  if ! command -v $cmd &>/dev/null
  then
    echo "$cmd could not be found"
    echo "Please install $cmd"
    exit 1
  fi
}

function check_default_tools ()
{
    for i in "${tools[@]}";
    do
        check_tool
    done
}

function get_token ()
{
    #echo "User: $USER"
    #echo "Pass: $PASS"
    local tries=0
    while [ $tries -lt $retry ]
    do
        generateTokenResponse=$(curl -s -u "$USER:$PASS" "https://privateinternetaccess.com/gtoken/generateToken")
        if [ "$(echo "$generateTokenResponse" | jq -r '.status')" == "OK" ]; then
            break
        fi
        ((tries=tries+1))
    done
    if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
        echo -e "Could not authenticate with the login credentials provided!"
        exit 1
    fi
    wg_token=$(echo "$generateTokenResponse" | jq -r '.token')
    #echo "Token: $wg_token"
}

function get_server_info ()
{
    local tries=0
    while [ $tries -lt $retry ]
    do
        all_region_data=$(curl -s "$serverlist_url" | head -1)
        regionData="$( echo $all_region_data | jq --arg REGION_ID "$region" -r '.regions[] | select(.id==$REGION_ID)')"
        if [[ $regionData ]]; then
            break
        fi
        ((tries=tries+1))
    done
    if [[ ! $regionData ]]; then
        echo -e "The REGION_ID $region is not valid."
        exit 1
    fi
    #echo $regionData
    wg_ip="$(echo $regionData | jq -r '.servers.wg[0].ip')"
    wg_cn="$(echo $regionData | jq -r '.servers.wg[0].cn')"
    #echo "WG_IP: $wg_ip"
    #echo "WG_CN: $wg_cn"
}

function fw_start ()
{
    sudo sysctl -p
    sudo ufw --force reset
    sudo ufw default deny outgoing
    sudo ufw default deny incoming
    sudo ufw allow in from $wg_ip to any
    sudo ufw allow in from $dnsServer
    sudo ufw allow out from any to $dnsServer
    sudo ufw allow out on $vpnname
    sudo ufw allow in on $vpnname
    sudo ufw allow in on $netname from $localnet
    sudo ufw allow out on $netname to $localnet
    
    sudo ufw disable
    sudo ufw --force enable
}

function fw_stop ()
{
    sudo sysctl -p
    sudo ufw --force reset
    sudo ufw disable
}

function wg_start ()
{
    get_token
    privKey="$(wg genkey)"
    pubKey="$( echo "$privKey" | wg pubkey)"
    #echo "$privKey :::: $pubKey"
    #echo "$wg_cn::$wg_ip:"
    local tries=0
    while [ $tries -lt $retry ]
    do
        wireguard_json=$(curl -s -G \
        --connect-to "${wg_cn}::${wg_ip}:" \
        --cacert "${certloc}" \
        --data-urlencode "pt=${wg_token}" \
        --data-urlencode "pubkey=${pubKey}" \
        "https://${wg_cn}:1337/addKey" )
        #echo $wireguard_json
        if [ "$(echo "$wireguard_json" | jq -r '.status')" == "OK" ]; then
            break
        fi
        ((tries=tries+1))
    done
    if [ "$(echo "$wireguard_json" | jq -r '.status')" != "OK" ]; then
        >&2 echo -e "Server did not return OK. Stopping now."
        exit 1
    fi
    dnsServer="$(echo "$wireguard_json" | jq -r '.dns_servers[0]')"
    wg_stop
    sudo mkdir -p /etc/wireguard
    echo "
    [Interface]
    Address = $(echo "$wireguard_json" | jq -r '.peer_ip')
    PrivateKey = $privKey
    DNS = $dnsServer
    [Peer]
    PersistentKeepalive = 25
    PublicKey = $(echo "$wireguard_json" | jq -r '.server_key')
    AllowedIPs = 0.0.0.0/0
    Endpoint = ${wg_ip}:$(echo "$wireguard_json" | jq -r '.server_port')
    " | sudo tee /etc/wireguard/$vpnname.conf || exit 1
    wg-quick up $vpnname || exit 1
}

function wg_stop ()
{
    sudo wg-quick down $vpnname
    sudo rm /etc/wireguard/$vpnname.conf
}

function services_start ()
{
    for i in "${services[@]}";
    do
        sudo systemctl start $i
    done
}

function services_stop ()
{
    for i in "${services[@]}";
    do
        sudo systemctl stop $i
    done
}

function start ()
{
    check_default_tools
    get_server_info
    wg_start
    fw_start
    services_start
}

function stop ()
{
    check_default_tools
    wg_stop
    fw_stop
    services_stop
}

function restart ()
{
    stop
    start
}

parse_args $1 $2 $3
case $func in
    start)
        start;;
    stop)
        stop;;
    restart)
        restart;;
    *)
        echo $usage
        exit 1
        ;;
esac
