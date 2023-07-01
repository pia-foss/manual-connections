#!/bin/bash

ip link add dev wg0 type wireguard
ip addr add 10.42.2.1/24 dev wg0
wg setconf wg0 /mnt/sda1/wg/wg0.conf
ip link set wg0 up
iptables -nvL INPUT | grep -q ".*ACCEPT.*udp.dpt.51820$" || iptables -A INPUT -p udp --dport 51820 -j ACCEPT
iptables -nvL INPUT | grep -q ".*ACCEPT.*all.*wg0" || iptables -A INPUT -i wg0 -j ACCEPT
iptables -nvL FORWARD | grep -q ".*ACCEPT.*all.*wg0" || iptables -A FORWARD -i wg0 -j ACCEPT
