# BoxProxy

BoxProxy V1 is an Ubuntu Server based multi-session PPPoE proxy gateway.

## Main Features

- Multiple physical WAN interfaces
- Multiple PPPoE sessions per WAN using macvlan
- Independent MAC address for each PPPoE session
- SOCKS5 proxy using Dante
- HTTP proxy using Squid
- Independent proxy username/password
- Start / Stop / Restart PPPoE sessions
- Change PPPoE MAC address
- Enable / Disable proxy per session
- Enable / Disable proxy per WAN
- Multi-WAN management
- Web management interface
- LAN DHCP server
- Static LAN IP reservation
- Duplicate static LAN IP detection
- MAC-based LAN client routing
- Assign each LAN client to a selected PPPoE session
- Fail-close policy routing
- Persistent routing after reboot

## Network Model

Default LAN:

    Gateway:        10.10.10.1
    Dynamic DHCP:   10.10.10.2 - 10.10.10.100
    Static clients: 10.10.10.101 - 10.10.10.254

## Proxy Ports

    SOCKS5 base port: 3900
    HTTP base port:   4900

For example:

    Proxy #1
    SOCKS5: 10.10.10.1:3901
    HTTP:   10.10.10.1:4901

    Proxy #2
    SOCKS5: 10.10.10.1:3902
    HTTP:   10.10.10.1:4902

## Web UI

Default address:

    http://10.10.10.1:8080/

Pages:

    /          Proxy Management
    /routing   LAN MAC Routing

## Supported Version

BoxProxy V1 currently supports PPPoE WAN mode.

DHCP Client WAN mode is planned for BoxProxy V2.

## Installation

Installation instructions and automated installer are being prepared.

## Security

PPPoE usernames and passwords are stored locally on the BoxProxy system and must never be committed to this repository.

Runtime WAN, proxy instance, DHCP reservation and client routing configuration should not be stored in Git.
