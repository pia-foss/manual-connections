# Manual PIA VPN Connections

This repository contains documentation on how to create native WireGuard and OpenVPN connections, and also on how to enable Port Forwarding in case you require this feature. You will find a lot of information below. However if you prefer quick test, here is the __TL/DR__:

```
git clone https://github.com/pia-foss/manual-connections.git
cd manual-connections
sudo ./run_setup.sh
```

The scripts were written so that they are easy to read and to modify. The code also has a lot of comments, so that you find all the information you might need. We hope you will enjoy forking the repo and customizing the scripts for your setup!

## Table of Contents

- [Dependencies](#dependencies)
- [Disclaimers](#disclaimers)
- [Confirmed distributions](#confirmed-distributions)
- [3rd Party Repositories](#3rd-party-repositories)
- [PIA Port Forwarding](#pia-port-forwarding)
- [Automated setup](#automated-setup)
- [Manual PF testing](#manual-pf-testing)
- [Thanks](#thanks)
- [License](#license)

## Dependencies

In order for the scripts to work (probably even if you do a manual setup), you will need the following packages:
 * `curl`
 * `jq`
 * (only for WireGuard) `wg-quick` and `wireguard` kernel module
 * (only for OpenVPN) `openvpn`

## Disclaimers

 * Port Forwarding is disabled on server-side in the United States.
 * These scripts do not enforce IPv6 or DNS settings, so that you have the freedom to configure your setup the way you desire it to work. This means you should have good understanding of VPN and cybersecurity in order to properly configure your setup.
 * For battle-tested security, please use the official PIA App, as it was designed to protect you in all scenarios.
 * This repo is really fresh at this moment, so please take into consideration the fact that you will probably be one of the first users that use the scripts.
 * Though we support research of open source technologies, we can not provide official support for all FOSS platforms, as there are simply too many platforms (which is a good thing). That is why we link 3rd Party repos in this README. We can not guarantee the quality of the code in the 3rd Party Repos, so use them only if you understand the risks.

## Confirmed Distributions

The functionality of the scripts within this repository has been tested and confirmed on the following operating systems and GNU/Linux distributions:
 * Arch
 * Artix
 * Fedora 32, 33
 * FreeBSD 12.1 (tweaks are required)
 * Manjaro
 * PureOS amber
 * Raspberry Pi OS 2020-08-20
 * Ubuntu 18.04, 20.04

## 3rd Party Repositories

Some users have created their own repositories for manual connections, based on the information they found within this repository. We can not guarantee the quality of the code found within these 3rd party repos, but we can create a centralized list so it's easy for you to find repos contain scripts to enable PIA services for your system.

| System | Fork | Language | Scope | Repository |
|:-:|:-:|:-:|:-:|-|
| FreeBSD | Yes | Bash | Compatibility | [glorious1/manual-connections](https://github.com/glorious1/manual-connections) |
| Linux | No | Bash | NetworkManager <br> GUI integration | [ThePowerTool/PIA-NetworkManager-GUI-Support](https://github.com/ThePowerTool/PIA-NetworkManager-GUI-Support) |
| Linux | No | Python | WireGuard, PF | [milahu/python-piavpn](https://github.com/milahu/python-piavpn) |
| Linux | No | Bash | WireGuard, PF,<br/>router and android config | [triffid/pia-wg](https://github.com/triffid/pia-wg) |
| Linux/FreeBSD/Win | No | Go | WireGuard,<br />config generation | [ddb_db/piawgcli](https://gitlab.com/ddb_db/piawgcli) |
| OPNsense | No | Python | WireGuard, PF, DIP | [FingerlessGlov3s/OPNsensePIAWireguard](https://github.com/FingerlessGlov3s/OPNsensePIAWireguard) |
| pfSense | No | Sh | OpenVPN, PF | [fm407/PIA-NextGen-PortForwarding](https://github.com/fm407/PIA-NextGen-PortForwarding) |
| pfSense | No | Java/PHP | WireGuard, PF | [ddb_db/pfpiamgr](https://gitlab.com/ddb_db/pfpiamgr) |
| Synology | Yes | Bash | Compatibility | [steff2632/manual-connections](https://github.com/steff2632/manual-connections) |
| Synology | No | Python | PF | [stmty9/synology](https://github.com/stmty9/synology) |
| TrueNAS | No | Bash | PF | [dak180/TrueNAS-Scripts](https://github.com/dak180/TrueNAS-Scripts/blob/master/pia-port-forward.sh) |
| UFW | Yes | Bash | Firewall Rules | [iPherian/manual-connections](https://github.com/iPherian/manual-connections) |
| Windows | No | PowerShell | Windows comptaibility | [ImjuzCY/pia-posh](https://github.com/ImjuzCY/pia-posh) |
| Windows | No | Powershell | OpenVPN, PF | [dougbenham/PIA-OpenVPN-Script](https://github.com/dougbenham/PIA-OpenVPN-Script) |

## PIA Port Forwarding

The PIA Port Forwarding service (a.k.a. PF) allows you run services on your own devices, and expose them to the internet by using the PIA VPN Network. The easiest way to set this up is by using a native PIA application. In case you require port forwarding on native clients, please follow this documentation in order to enable port forwarding for your VPN connection.

This service can be used only AFTER establishing a VPN connection.

## Automated Setup

In order to help you use VPN services and PF on any device, we have prepared a few bash scripts that should help you through the process of setting everything up. The scripts also contain a lot of comments, just in case you require detailed information regarding how the technology works. The functionality is controlled via environment variables, so that you have an easy time automating your setup.

The easiest way to trigger a fully automated connection is by running this oneliner:
```
sudo VPN_PROTOCOL=wireguard DISABLE_IPV6="no" AUTOCONNECT=true PIA_PF=false PIA_USER=p0123456 PIA_PASS=xxxxxxxx ./run_setup.sh
```

Here is a list of scripts you could find useful:
 * [Prompt based connection](run_setup.sh): This script allows connections with a one-line call, or will prompt for any missing or invalid variables. Variables available for one-line calls include:
   * `PIA_USER` - your PIA username
   * `PIA_PASS` - your PIA password
   * `PIA_DNS` - true/false
   * `PIA_PF` - true/false
   * `MAX_LATENCY` - numeric value, in seconds
   * `AUTOCONNECT` - true/false; this will test for and select the server with the lowest latency, it will override PREFERRED_REGION
   * `PREFERRED_REGION` - the region ID for a PIA server
   * `VPN_PROTOCOL` - wireguard or openvpn; openvpn will default to openvpn_udp_standard, but can also specify openvpn_tcp/udp_standad/strong
   * `DISABLE_IPV6` - yes/no
 * [Get region details](get_region.sh): This script will provide server details, validate `PREFERRED_REGION` input, and can determine the lowest latency location. The script can also trigger VPN connections, if you specify `VPN_PROTOCOL=wireguard` or `VPN_PROTOCOL=openvpn`; doing so requires a token. This script can reference `get_token.sh` with use of `PIA_USER` and `PIA_PASS`. If called without specifying `PREFERRED_REGION` this script writes a list of servers within lower than `MAX_LATENCY` to a `/opt/piavpn-manual/latencyList` for reference.
 * [Get a token](get_token.sh): This script allows you to get an authentication token with a valid 'PIA_USER' and 'PIA_PASS'. It will write the token and its expiration date to `/opt/piavpn-manual/token` for reference.
 * [Connect to WireGuard](connect_to_wireguard_with_token.sh): This script allows you to connect to the VPN server via WireGuard.
 * [Connect to OpenVPN](connect_to_openvpn_with_token.sh): This script allows you to connect to the VPN server via OpenVPN.
 * [Enable Port Forwarding](port_forwarding.sh): Enables you to add Port Forwarding to an existing VPN connection. Adding the environment variable `PIA_PF=true` to any of the previous scripts will also trigger this script.

## Manual PF Testing

To use port forwarding on the NextGen network, first of all establish a connection with your favorite protocol. After this, you will need to find the private IP of the gateway you are connected to. In case you are WireGuard, the gateway will be part of the JSON response you get from the server, as you can see in the [bash script](https://github.com/pia-foss/manual-connections/blob/master/wireguard_and_pf.sh#L119). In case you are using OpenVPN, you can find the gateway by checking the routing table with `ip route s t all`.

After connecting and finding out what the gateway is, get your payload and your signature by calling `getSignature` via HTTPS on port 19999. You will have to add your token as a GET var to prove you actually have an active account.

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

### Testing Your New PF

To test that it works, you can tcpdump on the port you received:

```
bash-5.0# tcpdump -ni any port 47047
```

After that, use curl __from another machine__ on the IP of the traffic server and the port specified in the payload which in our case is `47047`:
```bash
$ curl "http://178.162.208.237:47047"
```

You should see the traffic in your tcpdump:
```
bash-5.0# tcpdump -ni any port 47047
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on any, link-type LINUX_SLL (Linux cooked v1), capture size 262144 bytes
22:44:01.510804 IP 81.180.227.170.33884 > 10.4.143.34.47047: Flags [S], seq 906854496, win 64860, options [mss 1380,sackOK,TS val 2608022390 ecr 0,nop,wscale 7], length 0
22:44:01.510895 IP 10.4.143.34.47047 > 81.180.227.170.33884: Flags [R.], seq 0, ack 906854497, win 0, length 0
```

If you run curl on the same machine (the one that is connected to the VPN), you will see the traffic in tcpdump anyway and the test won't prove anything. At the same time, the request will get firewall so you will not be able to access the port from the same machine. This can only be tested properly by running curl on another system.

## Thanks

A big special thanks to [faireOwl](https://github.com/faireOwl) for his contributions to this repo.

## License
This project is licensed under the [MIT (Expat) license](https://choosealicense.com/licenses/mit/), which can be found [here](/LICENSE).
