# Retrontology's Wireguard Killswitch script

## Description
A fork of [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections) that I've retooled to use UFW as a VPN kill switch. That is, when the VPN is running, UFW channels traffic only through the VPN interface to prevent information leaks.

## Requirements
- wg-quick
- curl
- jq
- resolvconf
- ufw
- systemctl

## Setup
Change the following variables at the beginning of the `wg.sh` script to suit your needs:
- `region`: The PIA region you want to use
- `netname`: The physical interface you will connect to the VPN with
- `vpnname`: The name you want to use for the virtual Wireguard device
- `localnet`: The netmask of the local network you want to allow through the firewall
- `certloc`: The location of the PIA certificate file
- `services`: An array of the systemd services you want to run through the VPN

## Usage
```
./wg.sh <start/stop/restart> [pia username] [pia password]
```

## License
This project is licensed under the [MIT (Expat) license](https://choosealicense.com/licenses/mit/), which can be found [here](/LICENSE).