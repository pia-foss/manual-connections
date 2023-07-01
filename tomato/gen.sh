#!/bin/sh

VPNNAME="retrohome"
CLIENTNUM=5
WGCONF="wg0"
WGPORT=51820
SERVERENDPOINT='home.retrontology.com'

wg genkey > "$VPNNAME"
wg pubkey < "$VPNNAME" > "$VPNNAME".pub
SERVERIP="10.42.2.1"
VPN_SUBNET="10.42.0.0/22"

echo "[Interface]" > "$WGCONF".conf
#echo "Address = $SERVERIP/24" >> "$WGCONF".conf
echo "ListenPort = $WGPORT" >> "$WGCONF".conf
echo "PrivateKey = $(cat $VPNNAME)" >> "$WGCONF".conf


for i in $(seq 1 $CLIENTNUM)
do
    wg genkey > "$VPNNAME".client"$i"
    wg pubkey < "$VPNNAME".client"$i" > "$VPNNAME".client"$i".pub
    CLIENTIP=$(printf "10.42.2.$(expr $i + 1)")

    echo "" >> "$WGCONF".conf
    echo "[Peer]" >> "$WGCONF".conf
    echo "PublicKey = $(cat $VPNNAME.client$i.pub)" >> "$WGCONF".conf
    echo "AllowedIPs = $CLIENTIP"/32 >> "$WGCONF".conf

    echo "[Interface]" > "$VPNNAME".client"$i".conf
    echo "Address = $CLIENTIP/24" >> "$VPNNAME".client"$i".conf
    echo "ListenPort = $WGPORT" >> "$VPNNAME".client"$i".conf
    echo "PrivateKey = $(cat $VPNNAME.client$i)" >> "$VPNNAME".client"$i".conf
    echo "" >> "$VPNNAME".client"$i".conf
    echo "[Peer]" >> "$VPNNAME".client"$i".conf
    echo "PublicKey = $(cat $VPNNAME.pub)" >> "$VPNNAME".client"$i".conf
    echo "AllowedIPs = $SERVERIP/32, $VPN_SUBNET" >> "$VPNNAME".client"$i".conf
    echo "Endpoint = $SERVERENDPOINT:$WGPORT" >> "$VPNNAME".client"$i".conf
done
