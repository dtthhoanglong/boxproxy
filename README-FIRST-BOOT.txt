BOXPROXY V3 - FIRST BOOT AFTER CLONING

1. Boot the cloned SSD and login locally.

2. Run:
   sudo boxproxy-setup-network

3. Select the physical WAN interface.

4. Select the physical LAN interface.

The setup tool will configure:
- LAN 10.10.10.1/24
- IPv6 LAN fd00:10:10:10::1/64
- DHCP Server
- Router Advertisement
- BoxProxy WebUI
- SSH host keys and SSH service

After setup:

WebUI:
http://10.10.10.1:8080

SSH:
ssh ubuntu@10.10.10.1
