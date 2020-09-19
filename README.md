# Manual PIA VPN Connections
 __This project is "Work in Progress"__

This repository contains documentation on how to create native WireGuard connections to our __NextGen network__, and also on how to enable Port Forwarding in case you require this feature. Documentation on OpenVPN will follow soon enough.

You will find a lot of information bellow. However if you prefer a hands-on approach, here is the __TL/DR__:
 * clone this repo: `git clone https://github.com/pia-foss/manual-connections.git`
 * use `get_region_and_token.sh` to get the best region and a token
 * use `connect_to_wireguard_with_token.sh` to create a WireGuard connection with/without PF

Here is a oneliner example:
```
sudo PIA_AUTOCONNECT=wireguard PIA_USER=p0123456 PIA_PASS=xxxxxxxxxx ./get_region_and_token.sh
```

### Dependencies

In order for the scripts to work (probably even if you do a manual setup), you will need the following packages:
 * `curl`
 * `jq`
 * (only for WireGuard) `wireguard-tools` and wireguard kernel module
 * (only for OpenVPN) `openvpn` (however the script is not available yet)

### Confirmed systems and distributions

The functionality of the scripts within this repository has been tested and confirmed on the following operating systems and GNU/Linux distributions:
 * Arch
 * Artix
 * Fedora 32
 * FreeBSD 12.1
 * Ubuntu 20.04

### Disclaimers

 * Port Forwarding is disabled on server-side in the United States.
 * These scripts do not touch IPv6 or DNS, so that you have the freedom to configure your setup the way you desire it to work. This means you should have good understanding of VPN and cybersecurity in order to properly configure your setup.
 * For battle-tested security, please use the official PIA App, as it was designed to protect you in all scenarios.
 * This repo is really fresh at this moment, so please take into consideration the fact that you will probably be one of the first users that use the scripts.

## PIA Port Forwarding

The PIA Port Forwarding service (a.k.a. PF) allows you run services on your own devices, and expose them to the internet by using the PIA VPN Network. The easiest way to set this up is by using a native PIA aplications. In case you require port forwarding on native clients, please follow this documentation in order to enable port forwarding for your VPN connection.

This service can be used only AFTER establishing a VPN connection.

## Automated setup of VPN and/or PF

In order to help you use VPN services and PF on any device, we have prepare a few bash scripts that should help you through the process of setting everything up. The scripts also contain a lot of comments, just in case you require detailed information regarding how the technology works.

Here is a list of scripts you could find useful:
 * [Get the best region and a token](get_region_and_token.sh): This script helps you to get the best region and also to get a token for VPN authentication. The script will extend it's functionality if you add extra environment variables. Adding your PIA credentials will allow the script to also get a VPN token. The script can also trigger the WireGuard script to create a connection, if you specify `PIA_AUTOCONNECT=wireguard`.
 * [Connect to WireGuard](connect_to_wireguard_with_token.sh): This script allow you to connect to the VPN server via WireGuard. You can specify `PIA_PF=true` if you also wish to get Port Forwarding for your connection.
 * Connect to OpenVPN: We are still working on this script.
 * [Enable Port Forwarding](port_forwarding.sh): Enables you to add Port Forwarding to an existing VPN connection.

## Manual setup of PF

To use port forwarding on the NextGen network, first of all establish a connection with your favorite protocol. After this, you will need to find the private IP of the gateway you are connected to. In case you are WireGuard, the gateway will be part of the JSON response you get from the server, as you can see in the [bash script](https://github.com/pia-foss/manual-connections/blob/master/wireguard_and_pf.sh#L119). In case you are using OpenVPN, you can find the gateway by checking the routing table with `ip route s t all`.

After connecting and finding out what the gateway is, get your payload and your signature by calling `getSignature` via HTTPS on port 19999. You will have to add your token as a GET var to proove you actually have an active account.

Example:
```bash
bash-5.0# curl -k "https://10.4.128.1:19999/getSignature?token=$TOKEN"
{
    "status": "OK",
    "payload": "eyJ0b2tlbiI6Inh4eHh4eHh4eCIsInBvcnQiOjQ3MDQ3LCJjcmVhdGVkX2F0IjoiMjAyMC0wNC0zMFQyMjozMzo0NC4xMTQzNjk5MDZaIn0=",
    "signature": "a40Tf4OrVECzEpi5kkr1x5vR0DEimjCYJU9QwREDpLM+cdaJMBUcwFoemSuJlxjksncsrvIgRdZc0te4BUL6BA=="
}
```

The payload can be decoded with base64 to see your information:
```bash
$ echo eyJ0b2tlbiI6Inh4eHh4eHh4eCIsInBvcnQiOjQ3MDQ3LCJjcmVhdGVkX2F0IjoiMjAyMC0wNC0zMFQyMjozMzo0NC4xMTQzNjk5MDZaIn0= | base64 -d | jq 
{
  "token": "xxxxxxxxx",
  "port": 47047,
  "expires_at": "2020-06-30T22:33:44.114369906Z"
}
```
This is where you can also see the port you received. Please consider `expires_at` as your request will fail if the token is too old. All ports currently expire after 2 months.

Use the payload and the signature to bind the port on any server you desire. This is also done by curling the gateway of the VPN server you are connected to.
```bash
bash-5.0# curl -sGk --data-urlencode "payload=${payload}" --data-urlencode "signature=${signature}" https://10.4.128.1:19999/bindPort
{
    "status": "OK",
    "message": "port scheduled for add"
}
bash-5.0# 
```

Call __/bindPort__ every 15 minutes, or the port will be deleted!

### Testing your new PF

To test that it works, you can tcpdump on the port you received:

```
bash-5.0# tcpdump -ni any port 47047
```

After that, use curl on the IP of the traffic server and the port specified in the payload which in our case is `47047`:
```bash
$ curl "http://178.162.208.237:47047"
```

and you should see the traffic in your tcpdump:
```
bash-5.0# tcpdump -ni any port 47047
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on any, link-type LINUX_SLL (Linux cooked v1), capture size 262144 bytes
22:44:01.510804 IP 81.180.227.170.33884 > 10.4.143.34.47047: Flags [S], seq 906854496, win 64860, options [mss 1380,sackOK,TS val 2608022390 ecr 0,nop,wscale 7], length 0
22:44:01.510895 IP 10.4.143.34.47047 > 81.180.227.170.33884: Flags [R.], seq 0, ack 906854497, win 0, length 0
```

## License
This project is licensed under the [MIT (Expat) license](https://choosealicense.com/licenses/mit/), which can be found [here](/LICENSE).
