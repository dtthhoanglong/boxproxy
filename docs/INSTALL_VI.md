# BoxProxy V2 – Hướng dẫn cài đặt và nâng cấp từ V1

> Áp dụng cho nhánh `v2-dev`.

## 1. Install V1 có dùng được cho V2 không?

Nhánh `v2-dev` hiện có `install.sh` dành cho **BoxProxy V2**. Trên **máy mới**, dùng trực tiếp installer này. Installer hiện đã cài các thành phần cần thiết cho PPPoE, DHCP Ethernet WAN và WiFi WAN, bao gồm `networkd-dispatcher` và hook phục hồi WiFi WAN.

Với **máy V1 đang chạy**, không chạy lại `install.sh` vì installer có thể ghi lại `settings.conf`, DHCP và network config. Hãy dùng phần nâng cấp tại chỗ ở cuối tài liệu.

## 2. Cài mới BoxProxy V2

```bash
cd ~
git clone -b v2-dev --single-branch https://github.com/dtthhoanglong/boxproxy.git
cd ~/boxproxy
git branch --show-current
```

Kết quả phải là:

```text
v2-dev
```

Tắt cloud-init:

```bash
sudo touch /etc/cloud/cloud-init.disabled
sudo systemctl disable cloud-init-local.service
sudo systemctl disable cloud-init.service
sudo systemctl disable cloud-config.service
sudo systemctl disable cloud-final.service
```

Chạy installer nền:

```bash
cd ~/boxproxy
sudo bash install.sh
```

Chưa reboot ngay.

## 3. Kiểm tra sau khi chạy installer V2

Kiểm tra thư mục DDNS:

```bash
sudo test -d /etc/boxproxy/ddns && echo "DDNS directory: OK"
```

Kiểm tra helper:

```bash
for f in   instance-egress   instance-public-ip   ddns-config   ddns-update   ddns-sync-all   wan-restore; do
  sudo test -x "/usr/local/lib/boxproxy/$f" && echo "OK: $f" || echo "MISSING: $f"
done
```

Xem user WebUI:

```bash
systemctl cat boxproxy-web.service | grep '^User='
```

Mở sudoers:

```bash
sudo visudo -f /etc/sudoers.d/boxproxy-web
```

Ví dụ WebUI chạy bằng `ubuntu`, file cần có:

```text
ubuntu ALL=(root) NOPASSWD: /usr/local/sbin/boxproxy
ubuntu ALL=(root) NOPASSWD: /usr/local/lib/boxproxy/ddns-config
```

Kiểm tra:

```bash
sudo visudo -c
```

Kiểm tra các service V2 đã được enable:

```bash
sudo systemctl daemon-reload
systemctl is-enabled boxproxy-web.service
systemctl is-enabled boxproxy-client-routing.service
systemctl is-enabled boxproxy-wan-restore.service
systemctl is-enabled boxproxy-ddns.timer
systemctl is-enabled isc-dhcp-server.service
systemctl is-enabled networkd-dispatcher.service
```

Không cần enable `boxproxy-ddns.service` trực tiếp; timer sẽ gọi service này.

Validation:

```bash
cd ~/boxproxy
bash -n bin/boxproxy

for f in lib/*; do
  [ -f "$f" ] || continue
  bash -n "$f" || exit 1
done

python3 -m py_compile web/app.py
git diff --check
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
```

Sau đó:

```bash
sudo reboot
```

## 4. WebUI

Sau reboot:

```text
http://10.10.10.1:8080/
```

Kiểm tra:

```bash
systemctl is-active boxproxy-web.service
sudo ss -lntp | grep ':8080'
```

## 5. PPPoE WAN

PPPoE WAN giữ mô hình V1:

- nhiều Proxy Session trên một WAN;
- macvlan riêng cho từng session;
- Start / Stop / Restart;
- Change MAC;
- Change Password;
- Proxy ON/OFF;
- Proxy Count;
- SOCKS5/HTTP theo public IPv4 của từng PPPoE session.

## 6. DHCP WAN

V2 bổ sung DHCP WAN.

Quy tắc:

```text
1 DHCP WAN = đúng 1 Proxy Session
```

DHCP WAN không có Proxy Count.

Khi tạo DHCP WAN, BoxProxy sẽ:

1. tạo WAN config;
2. tạo đúng 1 proxy;
3. lấy DHCP IPv4;
4. dựng policy routing;
5. start DNS;
6. start Dante;
7. start Squid;
8. sync LAN routing.

Sau reboot, `boxproxy-wan-restore.service` tự phục hồi DHCP WAN.

Kiểm tra:

```bash
sudo boxproxy wan-json
sudo boxproxy web-json
```

## 7. WiFi WAN

V2 hỗ trợ dùng card WiFi Linux ở chế độ client/managed làm WAN. Mỗi WiFi WAN có đúng **1 Proxy Session**, tương tự DHCP WAN.

WebUI cần cho phép cấu hình WiFi WAN với interface, SSID và thông tin kết nối WiFi. Sau khi kết nối thành công, BoxProxy dùng IPv4/gateway/DNS mà WiFi nhận được để dựng policy routing, DNS, Dante và Squid.

Các helper hiện dùng cho WiFi WAN:

```text
wifi-wan-up
wifi-wan-down
instance-egress
instance-public-ip
wan-restore
```

Hook `networkd-dispatcher/routable.d/60-boxproxy-wifi` giúp đồng bộ lại routing khi interface WiFi trở thành routable. `install.sh` V2 cài `networkd-dispatcher` và hook này tự động.

Kiểm tra WiFi WAN:

```bash
sudo boxproxy wan-json
ip -4 -br addr show wlp1s0
ip route show table 102
ip rule
systemctl status boxproxy-wan-restore.service --no-pager -l
```

Trạng thái đã test trên J1900:

```text
WAN 1: DHCP Ethernet -> enp2s0
WAN 2: WiFi          -> wlp1s0
LAN:                    enp3s0 / 10.10.10.1
```

Cả DHCP Ethernet WAN và WiFi WAN đã được kiểm tra với SOCKS5/HTTP và LAN Routing theo MAC.

> Cellular/WWAN không thuộc phạm vi V2 hiện tại. Nếu cần WWAN, dự kiến dùng giải pháp riêng (ví dụ OpenWrt) thay vì tích hợp vào BoxProxy V2 này.

## 8. Routing DHCP/WiFi WAN

Ví dụ DHCP Ethernet WAN:

```text
IP: 192.168.2.18/24
Gateway: 192.168.2.1
```

Kiểm tra table:

```bash
ip route show table 101
```

Ví dụ:

```text
default via 192.168.2.1 dev ens33 metric 10
unreachable default metric 42760
192.168.2.0/24 dev ens33 scope link src 192.168.2.18
```

Kiểm tra rule:

```bash
ip rule
```

Ví dụ:

```text
1001: from 192.168.2.18 lookup 101
2001: from all fwmark 0x2711 lookup 101
```

## 9. LAN Routing và fail-close

Kiểm tra:

```bash
sudo boxproxy client-json
sudo iptables -S FORWARD
sudo iptables -t nat -S POSTROUTING
sudo iptables -t mangle -S PREROUTING
```

Client chưa map phải bị chặn bởi `BOXPROXY-FAILCLOSE`.

## 10. DDNS No-IP

Mỗi WAN có thể có một DDNS.

DDNS của WAN lấy public IPv4 của **Proxy có ID nhỏ nhất thuộc WAN đó**.

WebUI hỗ trợ:

```text
Enable DDNS
Provider: No-IP
Hostname
Username
Password
Check Interval (seconds)
```

Interval tối thiểu:

```text
30 giây
```

Password DDNS không được render ngược ra WebUI. Để trống ô Password khi Save sẽ giữ password cũ.

Timer:

```text
boxproxy-ddns.timer
```

gọi:

```text
boxproxy-ddns.service
 -> ddns-sync-all
 -> ddns-update <WAN_ID>
```

Kiểm tra:

```bash
systemctl status boxproxy-ddns.timer --no-pager
systemctl list-timers --all | grep boxproxy-ddns
journalctl -u boxproxy-ddns.service -n 50 --no-pager
```

Kiểm tra DDNS thủ công:

```bash
sudo /usr/local/lib/boxproxy/ddns-config get 1
sudo /usr/local/lib/boxproxy/instance-public-ip 1
sudo /usr/local/lib/boxproxy/ddns-update 1
```

No-IP thành công có thể trả:

```text
good <PUBLIC_IP>
```

hoặc:

```text
nochg <PUBLIC_IP>
```

## 11. DHCP WAN sau modem và port-forward

Ví dụ:

```text
BoxProxy WAN local IP: 192.168.2.18
Public IPv4:           116.x.x.x
```

DDNS trỏ tới public IPv4.

Muốn dùng proxy từ Internet, modem/router phía trước cần port-forward, ví dụ:

```text
TCP 3901 -> 192.168.2.18:3901
TCP 4901 -> 192.168.2.18:4901
```

Nên đặt DHCP reservation cho local WAN IP của BoxProxy.

## 12. Kiểm tra service V2

```bash
systemctl is-active boxproxy-web.service
systemctl is-active boxproxy-wan-restore.service
systemctl is-active boxproxy-ddns.timer
systemctl is-active boxproxy-client-routing.service
```

Proxy #1 đang bật:

```bash
systemctl is-active boxproxy-dante@1.service
systemctl is-active boxproxy-squid@1.service
systemctl is-active boxproxy-dns@1.service
```

## 13. Test SOCKS5/HTTP

Từ Windows LAN:

```powershell
curl.exe --socks5-hostname USER:PASS@10.10.10.1:3901 https://api.ipify.org
curl.exe -x http://USER:PASS@10.10.10.1:4901 https://api.ipify.org
```

## 14. Reboot test

```bash
sudo reboot
```

Sau reboot, không bấm Start WAN thủ công.

```bash
ip -br addr
ip rule
ip route show table 101

systemctl status boxproxy-wan-restore.service --no-pager -l
systemctl is-active boxproxy-dante@1.service
systemctl is-active boxproxy-squid@1.service
systemctl is-active boxproxy-dns@1.service
```

---

# Nâng cấp BoxProxy V1 đang chạy sang V2

## 15. Không chạy lại install.sh

Trên máy V1 production, **không chạy**:

```bash
sudo bash install.sh
```

Nâng cấp tại chỗ phải giữ nguyên `/etc/boxproxy` và network config.

## 16. Backup V1

```bash
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/boxproxy-v1-backup-$STAMP"

sudo mkdir -p "$BACKUP"

sudo cp -a /etc/boxproxy "$BACKUP/"
sudo cp -a /opt/boxproxy-web "$BACKUP/" 2>/dev/null || true
sudo cp -a /usr/local/lib/boxproxy "$BACKUP/" 2>/dev/null || true
sudo cp -a /usr/local/sbin/boxproxy "$BACKUP/" 2>/dev/null || true
sudo cp -a /etc/systemd/system/boxproxy-* "$BACKUP/" 2>/dev/null || true
sudo cp -a /etc/ppp/ip-up.d "$BACKUP/ppp-ip-up.d" 2>/dev/null || true
sudo cp -a /etc/ppp/ip-down.d "$BACKUP/ppp-ip-down.d" 2>/dev/null || true
sudo cp -a /etc/netplan "$BACKUP/" 2>/dev/null || true

echo "$BACKUP"
```

## 17. Chuyển source sang V2

```bash
cd ~/boxproxy

git status
git fetch origin
git checkout v2-dev
git pull origin v2-dev
```

Kiểm tra:

```bash
git branch --show-current
git log --oneline -5
```

## 18. Deploy V2 nhưng giữ config V1

CLI:

```bash
sudo install -m 755 bin/boxproxy /usr/local/sbin/boxproxy
```

Libraries:

```bash
for FILE in lib/*; do
  [ -f "$FILE" ] || continue
  sudo install -m 755 "$FILE" "/usr/local/lib/boxproxy/$(basename "$FILE")"
done
```

PPP hooks:

```bash
for FILE in ppp-hooks/ip-up.d/*; do
  [ -f "$FILE" ] || continue
  sudo install -m 755 "$FILE" "/etc/ppp/ip-up.d/$(basename "$FILE")"
done

for FILE in ppp-hooks/ip-down.d/*; do
  [ -f "$FILE" ] || continue
  sudo install -m 755 "$FILE" "/etc/ppp/ip-down.d/$(basename "$FILE")"
done
```

WebUI:

```bash
sudo install -d -m 755 /opt/boxproxy-web/templates
sudo install -m 644 web/app.py /opt/boxproxy-web/app.py
sudo install -m 644 web/templates/index.html /opt/boxproxy-web/templates/index.html
sudo install -m 644 web/templates/routing.html /opt/boxproxy-web/templates/routing.html
```

Systemd:

```bash
for SERVICE in systemd/*; do
  [ -f "$SERVICE" ] || continue
  sudo install -m 644 "$SERVICE" "/etc/systemd/system/$(basename "$SERVICE")"
done
```

DDNS directory:

```bash
sudo test -d /etc/boxproxy/ddns && echo "DDNS directory: OK"
```

Không xóa hoặc tạo lại:

```text
/etc/boxproxy/wans/
/etc/boxproxy/instances/
/etc/boxproxy/client-routes/
/etc/boxproxy/settings.conf
```

V1 config không có `WAN_TYPE` được V2 hiểu mặc định là PPPoE.

## 19. Update sudoers

```bash
systemctl cat boxproxy-web.service | grep '^User='
sudo visudo -f /etc/sudoers.d/boxproxy-web
```

Ví dụ:

```text
ubuntu ALL=(root) NOPASSWD: /usr/local/sbin/boxproxy
ubuntu ALL=(root) NOPASSWD: /usr/local/lib/boxproxy/ddns-config
```

Kiểm tra:

```bash
sudo visudo -c
```

## 20. Enable service V2

```bash
sudo systemctl daemon-reload
sudo systemctl enable boxproxy-wan-restore.service
sudo systemctl enable boxproxy-ddns.timer
sudo systemctl enable boxproxy-client-routing.service
sudo systemctl enable boxproxy-web.service
```

## 21. Validation trước reboot

```bash
cd ~/boxproxy

bash -n bin/boxproxy

for f in lib/*; do
  [ -f "$f" ] || continue
  bash -n "$f" || exit 1
done

python3 -m py_compile web/app.py
git diff --check

sudo /usr/local/lib/boxproxy/sync-pppoe-secrets
```

Restart WebUI:

```bash
sudo systemctl restart boxproxy-web.service
systemctl is-active boxproxy-web.service
```

## 22. Reboot sau nâng cấp

```bash
sudo reboot
```

Sau reboot:

```bash
sudo boxproxy wan-json
sudo boxproxy web-json

ip -br addr
ip rule

systemctl is-active boxproxy-web.service
systemctl is-active boxproxy-client-routing.service
systemctl is-active boxproxy-wan-restore.service
systemctl is-active boxproxy-ddns.timer
```

PPPoE cũ:

```bash
ps aux | grep '[p]ppd'
sudo ss -lntup | grep -E 'danted|squid'
```

Test từng proxy trước khi kết luận nâng cấp thành công.

## 23. Vị trí quan trọng

```text
Repo:                  ~/boxproxy
CLI:                   /usr/local/sbin/boxproxy
Libraries:             /usr/local/lib/boxproxy/
WebUI:                 /opt/boxproxy-web/
Main config:           /etc/boxproxy/settings.conf
WAN:                   /etc/boxproxy/wans/
Proxy instances:       /etc/boxproxy/instances/
Dante:                 /etc/boxproxy/dante/
Squid:                 /etc/boxproxy/squid/
DNS:                   /etc/boxproxy/dns/
LAN client routing:    /etc/boxproxy/client-routes/
DDNS:                  /etc/boxproxy/ddns/
DDNS runtime state:    /run/boxproxy/ddns/
Systemd:               /etc/systemd/system/boxproxy-*.service
                       /etc/systemd/system/boxproxy-*.timer
```

## 24. Trạng thái V2 đã test

Đã test trong quá trình phát triển:

- PPPoE multi-session V1.
- Start / Stop / Restart PPPoE.
- Change MAC PPPoE.
- Change Password proxy.
- SOCKS5 authentication.
- SOCKS5 UDP relay.
- HTTP authenticated proxy.
- LAN routing theo MAC.
- MSS 1452 cho LAN -> PPPoE.
- Fail-close client chưa map.
- DHCP WAN.
- DHCP WAN đúng 1 proxy.
- DHCP SOCKS5/HTTP.
- DHCP LAN Routing.
- DHCP Proxy ON/OFF.
- DHCP Change Password.
- DHCP tự restore sau reboot.
- No-IP DDNS.
- DDNS chỉ update khi public IP thay đổi.
- DDNS interval theo giây từ WebUI.
- WiFi WAN.
- WiFi SOCKS5/HTTP.
- WiFi LAN Routing theo MAC.
- WiFi tự restore/routing sync sau khi interface routable.
- Installer V2 cài `networkd-dispatcher` và WiFi hook.
- WebUI hỗ trợ PPPoE/DHCP/WiFi + DDNS.
- Cellular/WWAN không nằm trong BoxProxy V2 hiện tại.
