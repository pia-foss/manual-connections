#!/bin/bash

ip link delete wg0
iptables -nvL INPUT | grep -q ".*ACCEPT.*udp.dpt.51820$" && iptables -D INPUT -p udp --dport 51820 -j ACCEPT
iptables -nvL INPUT | grep -q ".*ACCEPT.*all.*wg0" && iptables -D INPUT -i wg0 -j ACCEPT
iptables -nvL FORWARD | grep -q ".*ACCEPT.*all.*wg0" && iptables -D FORWARD -i wg0 -j ACCEPT
