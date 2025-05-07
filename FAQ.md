# Frequently Asked Questions (FAQ)

## General

### What is this repository for?
This repository contains documentation and scripts for creating native WireGuard and OpenVPN connections, as well as enabling Port Forwarding for Private Internet Access (PIA) VPN.

### What are the dependencies for the scripts?
The scripts require the following packages:
- `curl`
- `jq`
- (only for WireGuard) `wireguard-tools` (`wg-quick` and `wireguard` kernel module)
- (only for OpenVPN) `openvpn`

## Installation and Setup

### How do I install and use the scripts?
To install and use the scripts, follow these steps:
1. Clone the repository: `git clone https://github.com/pia-foss/manual-connections.git`
2. Change to the repository directory: `cd manual-connections`
3. Run the setup script: `sudo ./run_setup.sh`

### How do I disable IPv6?
To disable IPv6, run the following commands:
```
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
```

## Integrating IPFS with Ethereum

### How do I install and use IPFS with Ethereum?
Follow these steps to install and use IPFS with Ethereum:
1. **Install IPFS**: Follow the instructions on the IPFS installation page.
2. **Initialize IPFS**: Run `ipfs init` to initialize the IPFS repository.
3. **Start the IPFS daemon**: Run `ipfs daemon` to start the IPFS daemon.
4. **Add files to IPFS**: Use the command `ipfs add <file>` to add files to IPFS. This will return a CID (Content Identifier).
5. **Store CID on Ethereum**: Use a smart contract to store the CID on the Ethereum blockchain. You can use Solidity to create a contract that stores the CID as a string.
6. **Retrieve files from IPFS**: Use the command `ipfs cat <CID>` to retrieve files from IPFS using the CID.
7. **Pinning files on IPFS**: Use the command `ipfs pin add <CID>` to pin files on IPFS, ensuring they are not garbage collected.

### What should I do if I encounter issues while integrating IPFS with Ethereum?
Refer to the troubleshooting section in the README.md file for common issues and their solutions.

## Port Forwarding

### How do I enable port forwarding?
To enable port forwarding, follow these steps:
1. Establish a VPN connection using your preferred protocol (WireGuard or OpenVPN).
2. Find the private IP of the gateway you are connected to.
3. Get your payload and signature by calling `getSignature` via HTTPS on port 19999.
4. Use the payload and signature to bind the port on any server you desire by calling `/bindPort` every 15 minutes.

### How do I test if port forwarding is working?
To test if port forwarding is working, use `tcpdump` to monitor the port you received and use `curl` from another machine to send a request to the IP of the traffic server and the specified port.

## Troubleshooting

### What should I do if the IPFS daemon is not starting?
Ensure that you have installed IPFS correctly and that there are no conflicting processes using the same ports.

### What should I do if I am unable to add files to IPFS?
Check if the file path is correct and that you have the necessary permissions to access the file.

### What should I do if I encounter smart contract deployment issues?
Verify that your Solidity code is correct and that you have sufficient gas to deploy the contract on the Ethereum network.

### What should I do if I have file retrieval issues with IPFS?
Ensure that the CID is correct and that the IPFS daemon is running. If the file is not pinned, it may have been garbage collected.
