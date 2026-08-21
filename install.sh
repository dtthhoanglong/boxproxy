#!/bin/bash
set -euo pipefail

# ============================================================
# BoxProxy V3 Installer
# Target: Ubuntu Server 22.04 LTS
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "sudo ./install.sh"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_USER="${SUDO_USER:-ubuntu}"

if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    echo "Admin user not found: $ADMIN_USER"
    exit 1
fi

echo
echo "============================================================"
echo "                 BoxProxy V3 Installer"
echo "============================================================"
echo
echo "BoxProxy V3 uses:"
echo
echo "  LAN Gateway       : 10.10.10.1/24"
echo "  Dynamic DHCP      : 10.10.10.2 - 10.10.10.100"
echo "  Static LAN IP     : 10.10.10.101 - 10.10.10.254"
echo "  SOCKS5 base port  : 3900"
echo "  HTTP base port    : 4900"
echo
echo "Available network interfaces:"
echo

ip -br link | awk '$1 != "lo" {print "  " $1 "  " $2 "  " $3}'

echo
read -rp "Enter WAN interface: " WAN_IF
read -rp "Enter LAN interface: " LAN_IF

WAN_IF="${WAN_IF%%@*}"
LAN_IF="${LAN_IF%%@*}"

if [ -z "$WAN_IF" ] || [ -z "$LAN_IF" ]; then
    echo "WAN/LAN interface cannot be empty."
    exit 1
fi

if [ "$WAN_IF" = "$LAN_IF" ]; then
    echo "WAN and LAN interfaces must be different."
    exit 1
fi

if [ ! -d "/sys/class/net/$WAN_IF" ]; then
    echo "WAN interface not found: $WAN_IF"
    exit 1
fi

if [ ! -d "/sys/class/net/$LAN_IF" ]; then
    echo "LAN interface not found: $LAN_IF"
    exit 1
fi

echo
echo "Selected configuration:"
echo
echo "  WAN : $WAN_IF"
echo "  LAN : $LAN_IF"
echo
read -rp "Continue installation? [y/N]: " CONFIRM

case "$CONFIRM" in
    y|Y|yes|YES)
        ;;
    *)
        echo "Installation cancelled."
        exit 0
        ;;
esac

echo
echo "============================================================"
echo "1. Installing packages"
echo "============================================================"

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    ppp \
    pppoe \
    dante-server \
    squid \
    dnsmasq-base \
    apache2-utils \
    isc-dhcp-server \
    python3 \
    python3-flask \
    iproute2 \
    iptables \
    openssl \
    curl \
    networkd-dispatcher \
    dhcpcd5 \
    radvd     util-linux

# BoxProxy uses per-instance dhcpcd processes for DHCPv6-PD.
# The global daemon must not configure PPPoE macvlan/WAN interfaces.
systemctl disable --now dhcpcd.service >/dev/null 2>&1 || true

echo
echo "============================================================"
echo "2. Creating BoxProxy directories"
echo "============================================================"

install -d -m 700 /etc/boxproxy
install -d -m 700 /etc/boxproxy/wans
install -d -m 700 /etc/boxproxy/instances
install -d -m 700 /etc/boxproxy/dante
install -d -m 700 /etc/boxproxy/dns
install -d -m 700 /etc/boxproxy/squid
install -d -m 700 /etc/boxproxy/client-routes
install -d -m 700 /etc/boxproxy/ddns
install -d -m 700 /etc/boxproxy/ipv6-pd-uuid
install -d -m 700 /etc/boxproxy/ipv6-slots

install -d -m 755 /usr/local/lib/boxproxy
install -d -m 755 /opt/boxproxy-web
install -d -m 755 /opt/boxproxy-web/templates

echo
echo "============================================================"
echo "3. Installing BoxProxy CLI and libraries"
echo "============================================================"

install -m 755 "$REPO_DIR/bin/boxproxy" \
    /usr/local/sbin/boxproxy

for FILE in "$REPO_DIR"/lib/*; do
    [ -f "$FILE" ] || continue

    install -m 755 "$FILE" \
        "/usr/local/lib/boxproxy/$(basename "$FILE")"
done

echo
echo "============================================================"
echo "4. Creating BoxProxy settings"
echo "============================================================"

DEFAULT_PROXY_PASSWORD="$(openssl rand -hex 8)"

cat > /etc/boxproxy/settings.conf <<EOF
PROXY_PASSWORD="$DEFAULT_PROXY_PASSWORD"
MAC_PREFIX="e0:f5:16"
SOCKS_BASE_PORT="3900"
HTTP_BASE_PORT="4900"

LAN_IF="$LAN_IF"
LAN_IP="10.10.10.1"
EOF

chmod 600 /etc/boxproxy/settings.conf

echo
echo "Generated initial proxy password:"
echo
echo "  $DEFAULT_PROXY_PASSWORD"
echo
echo "This password is used as the initial password for newly created"
echo "proxy accounts. It can later be changed from the Web UI."

echo
echo "============================================================"
echo "5. Installing Web UI"
echo "============================================================"

install -m 644 "$REPO_DIR/web/app.py" \
    /opt/boxproxy-web/app.py

install -m 644 "$REPO_DIR/web/templates/index.html" \
    /opt/boxproxy-web/templates/index.html

install -m 644 "$REPO_DIR/web/templates/routing.html" \
    /opt/boxproxy-web/templates/routing.html
install -m 644 "$REPO_DIR/web/templates/ddns.html" /opt/boxproxy-web/templates/ddns.html

chown -R "$ADMIN_USER:$ADMIN_USER" /opt/boxproxy-web

echo
echo "============================================================"
echo "6. Configuring sudo permissions for Web UI"
echo "============================================================"

install -m 440 "$REPO_DIR/config/system/boxproxy-web" \
    /etc/sudoers.d/boxproxy-web

# Replace legacy/default Ubuntu username if present.
sed -i -E \
    "s/^ubuntu([[:space:]])/${ADMIN_USER}\1/" \
    /etc/sudoers.d/boxproxy-web

if ! visudo -cf /etc/sudoers.d/boxproxy-web >/dev/null; then
    echo "Invalid sudoers configuration."
    rm -f /etc/sudoers.d/boxproxy-web
    exit 1
fi

echo
echo "============================================================"
echo "7. Installing PPP hooks"
echo "============================================================"

for FILE in "$REPO_DIR"/ppp-hooks/ip-up.d/*; do
    [ -f "$FILE" ] || continue

    install -m 755 "$FILE" \
        "/etc/ppp/ip-up.d/$(basename "$FILE")"
done

for FILE in "$REPO_DIR"/ppp-hooks/ip-down.d/*; do
    [ -f "$FILE" ] || continue

    install -m 755 "$FILE" \
        "/etc/ppp/ip-down.d/$(basename "$FILE")"
done

if [ -d "$REPO_DIR/ppp-hooks/ipv6-up.d" ]; then
    install -d -m 755 /etc/ppp/ipv6-up.d
    for FILE in "$REPO_DIR"/ppp-hooks/ipv6-up.d/*; do
        [ -f "$FILE" ] || continue
        install -m 755 "$FILE" \
            "/etc/ppp/ipv6-up.d/$(basename "$FILE")"
    done
fi

if [ -d "$REPO_DIR/dhcpcd-hooks" ]; then
    install -d -m 755 /lib/dhcpcd/dhcpcd-hooks
    for FILE in "$REPO_DIR"/dhcpcd-hooks/*; do
        [ -f "$FILE" ] || continue
        install -m 644 "$FILE" \
            "/lib/dhcpcd/dhcpcd-hooks/$(basename "$FILE")"
    done
fi

# Install networkd-dispatcher hooks used by DHCP/WiFi WAN.
if [ -d "$REPO_DIR/networkd-dispatcher/routable.d" ]; then
    install -d -m 755 /etc/networkd-dispatcher/routable.d

    for FILE in "$REPO_DIR"/networkd-dispatcher/routable.d/*; do
        [ -f "$FILE" ] || continue

        install -m 755 "$FILE" \
            "/etc/networkd-dispatcher/routable.d/$(basename "$FILE")"
    done
fi

echo
echo "============================================================"
echo "8. Preparing PPP authentication files"
echo "============================================================"

touch /etc/ppp/pap-secrets
touch /etc/ppp/chap-secrets

chmod 600 /etc/ppp/pap-secrets
chmod 600 /etc/ppp/chap-secrets

/usr/local/lib/boxproxy/sync-pppoe-secrets

echo
echo "============================================================"
echo "9. Preparing Squid authentication"
echo "============================================================"

touch /etc/squid/passwd

if getent group proxy >/dev/null 2>&1; then
    chown root:proxy /etc/squid/passwd
    chmod 640 /etc/squid/passwd
else
    chown root:root /etc/squid/passwd
    chmod 600 /etc/squid/passwd
fi

echo
echo "============================================================"
echo "10. Configuring DHCP server"
echo "============================================================"

install -m 644 "$REPO_DIR/config/dhcp/dhcpd.conf" \
    /etc/dhcp/dhcpd.conf

touch /etc/dhcp/boxproxy-reservations.conf
chmod 600 /etc/dhcp/boxproxy-reservations.conf

cp "$REPO_DIR/config/dhcp/isc-dhcp-server.example" \
    /etc/default/isc-dhcp-server

sed -i \
    "s/LAN_INTERFACE/$LAN_IF/g" \
    /etc/default/isc-dhcp-server

dhcpd -t -cf /etc/dhcp/dhcpd.conf

# isc-dhcp-server may start before the LAN static IPv4 is ready
# because BoxProxy intentionally masks systemd-networkd-wait-online.
# Wait only for the BoxProxy LAN address instead of waiting for all NICs.
install -d -m 755 /etc/systemd/system/isc-dhcp-server.service.d

cat > /etc/systemd/system/isc-dhcp-server.service.d/boxproxy.conf <<'EOF'
[Unit]
After=systemd-networkd.service

[Service]
ExecStartPre=/usr/local/lib/boxproxy/wait-lan-ready
EOF

echo
echo "============================================================"
echo "11. Configuring network"
echo "============================================================"

NETPLAN_BACKUP="/root/boxproxy-netplan-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$NETPLAN_BACKUP"

if compgen -G "/etc/netplan/*.yaml" >/dev/null; then
    cp -a /etc/netplan/*.yaml "$NETPLAN_BACKUP"/
fi

if compgen -G "/etc/netplan/*.yml" >/dev/null; then
    cp -a /etc/netplan/*.yml "$NETPLAN_BACKUP"/
fi

# Prevent cloud-init from rewriting network configuration.
if [ -d /etc/cloud/cloud.cfg.d ]; then
    cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<EOF
network: {config: disabled}
EOF
fi

touch /etc/cloud/cloud-init.disabled

systemctl disable cloud-init-local.service >/dev/null 2>&1 || true
systemctl disable cloud-init.service >/dev/null 2>&1 || true
systemctl disable cloud-config.service >/dev/null 2>&1 || true
systemctl disable cloud-final.service >/dev/null 2>&1 || true

rm -f /etc/netplan/*.yaml
rm -f /etc/netplan/*.yml

cp "$REPO_DIR/config/system/01-boxproxy.yaml.example" \
    /etc/netplan/01-boxproxy.yaml

sed -i \
    -e "s/WAN_INTERFACE/$WAN_IF/g" \
    -e "s/LAN_INTERFACE/$LAN_IF/g" \
    /etc/netplan/01-boxproxy.yaml

chmod 600 /etc/netplan/01-boxproxy.yaml

netplan generate

echo
echo "Old Netplan files were backed up to:"
echo "  $NETPLAN_BACKUP"

echo
echo "============================================================"
echo "12. Installing sysctl configuration"
echo "============================================================"

install -m 644 \
    "$REPO_DIR/config/system/99-boxproxy-forward.conf" \
    /etc/sysctl.d/99-boxproxy-forward.conf

rm -f /etc/sysctl.d/99-boxproxy-disable-ipv6.conf

install -m 644 \
    "$REPO_DIR/config/system/99-boxproxy-ipv6.conf" \
    /etc/sysctl.d/99-boxproxy-ipv6.conf

install -m 644 \
    "$REPO_DIR/config/system/99-boxproxy-ipv6-no-temp.conf" \
    /etc/sysctl.d/99-boxproxy-ipv6-no-temp.conf

cp "$REPO_DIR/config/system/90-boxproxy-ipv6-router.conf.example" \
    /etc/sysctl.d/90-boxproxy-ipv6-router.conf

sed -i "s/LAN_INTERFACE/$LAN_IF/g" \
    /etc/sysctl.d/90-boxproxy-ipv6-router.conf

sysctl --system >/dev/null

echo
echo "============================================================"
echo "13. Configuring IPv6 Router Advertisement"
echo "============================================================"

cp "$REPO_DIR/config/radvd/radvd.conf.example" /etc/radvd.conf
sed -i "s/LAN_INTERFACE/$LAN_IF/g" /etc/radvd.conf
chmod 644 /etc/radvd.conf
radvd --configtest -C /etc/radvd.conf

echo
echo "============================================================"
echo "14. Installing systemd services"
echo "============================================================"

for UNIT in \
    "$REPO_DIR"/systemd/*.service \
    "$REPO_DIR"/systemd/*.timer; do

    [ -f "$UNIT" ] || continue

    install -m 644 "$UNIT" \
        "/etc/systemd/system/$(basename "$UNIT")"
done

# Make Web UI service use the user who launched sudo if it contains User=ubuntu.
if grep -q '^User=' /etc/systemd/system/boxproxy-web.service; then
    sed -i \
        "s/^User=.*/User=$ADMIN_USER/" \
        /etc/systemd/system/boxproxy-web.service
fi

if grep -q '^Group=' /etc/systemd/system/boxproxy-web.service; then
    sed -i \
        "s/^Group=.*/Group=$ADMIN_USER/" \
        /etc/systemd/system/boxproxy-web.service
fi

systemctl daemon-reload

systemctl enable boxproxy-web.service
systemctl enable boxproxy-client-routing.service
systemctl enable boxproxy-wan-restore.service
systemctl enable boxproxy-ddns.timer
systemctl enable isc-dhcp-server.service
systemctl unmask radvd.service >/dev/null 2>&1 || true
systemctl enable radvd.service

systemctl enable networkd-dispatcher.service >/dev/null 2>&1 || true

# Disable package default services that BoxProxy V2 does not use.
# Dante is managed by boxproxy-dante@.service per proxy instance.
systemctl disable danted.service >/dev/null 2>&1 || true
systemctl mask danted.service >/dev/null 2>&1 || true

# Disable package default Squid service.
# BoxProxy manages Squid with its per-instance service template.
systemctl disable squid.service >/dev/null 2>&1 || true
systemctl mask squid.service >/dev/null 2>&1 || true

# LAN IPv6 uses SLAAC/radvd, not isc-dhcp-server6.
# Keep DHCPv4 and disable the separate DHCPv6 server service.
systemctl disable isc-dhcp-server6.service >/dev/null 2>&1 || true
systemctl mask isc-dhcp-server6.service >/dev/null 2>&1 || true


# Template PPPoE/macvlan/proxy services are enabled later
# when WAN/proxy instances are created from BoxProxy.

echo
echo "============================================================"
echo "15. Disabling unnecessary network wait"
echo "============================================================"

systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true

echo
echo "============================================================"
echo "16. Final validation"
echo "============================================================"

bash -n /usr/local/sbin/boxproxy

for FILE in /usr/local/lib/boxproxy/*; do
    [ -f "$FILE" ] || continue
    bash -n "$FILE"
done

python3 -m py_compile /opt/boxproxy-web/app.py

dhcpd -t -cf /etc/dhcp/dhcpd.conf

echo
echo "============================================================"
echo "               BoxProxy V3 installation complete"
echo "============================================================"
echo
echo "WAN interface : $WAN_IF"
echo "LAN interface : $LAN_IF"
echo
echo "LAN Gateway:"
echo "  IPv4: 10.10.10.1"
echo "  IPv6: fd00:10:10:10::1/64"
echo
echo "Web UI after reboot:"
echo "  http://10.10.10.1:8080/"
echo
echo "Dynamic DHCP:"
echo "  10.10.10.2 - 10.10.10.100"
echo
echo "Static LAN IP range:"
echo "  10.10.10.101 - 10.10.10.254"
echo
echo "Initial proxy password:"
echo "  $DEFAULT_PROXY_PASSWORD"
echo
echo "IMPORTANT:"
echo "Network configuration has been prepared but NOT applied live."
echo "This avoids unexpectedly disconnecting an SSH installation session."
echo
echo "Please reboot the server:"
echo
echo "  sudo reboot"
echo
