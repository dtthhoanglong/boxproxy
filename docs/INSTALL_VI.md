# BoxProxy V3 -- Hướng dẫn cài đặt và kiểm tra

> Áp dụng cho nhánh `v2-dev` tại thời điểm BoxProxy V3 đang được phát
> triển/test.
>
> V3 kế thừa toàn bộ chức năng V2 và bổ sung IPv6 cho PPPoE, DHCPv6
> Prefix Delegation (PD), IPv6 proxy/session và LAN routing IPv6 theo
> MAC.

## 1. Phạm vi BoxProxy V3 hiện tại

V3 hiện giữ các chức năng đã có của V2:

-   PPPoE multi-session.
-   DHCP Ethernet WAN.
-   WiFi WAN.
-   SOCKS5 và HTTP proxy.
-   SOCKS5 UDP relay.
-   DDNS No-IP.
-   LAN Routing theo MAC.
-   Fail-close.
-   Change MAC / Change Password.
-   Proxy ON/OFF.
-   Tự restore WAN/routing sau reboot.

Phần mới của V3 đã triển khai/test:

-   PPPoE có `IP_MODE`: `ipv4`, `dual`, `ipv6`.
-   PPPoE nhận IPv6 global.
-   DHCPv6 Prefix Delegation riêng theo PPPoE session.
-   Mỗi PPPoE session có service `boxproxy-ipv6-pd@ID.service`.
-   IPv6 proxy/session.
-   LAN có ULA `fd00:10:10:10::/64`.
-   SLAAC/Router Advertisement bằng `radvd`.
-   IPv6 LAN routing theo MAC.
-   IPv6 NETMAP từ ULA LAN sang delegated /64 của PPPoE session.
-   Stop/Start và Change MAC có lifecycle IPv6-PD đi cùng PPPoE.

Ví dụ đã test:

``` text
PPPoE #1 PD: 2402:800:6318:4183::/64
PPPoE #2 PD: 2402:800:6318:3829::/64

LAN ULA:
fd00:10:10:10::/64
```

Ví dụ NETMAP:

``` text
fd00:10:10:10::/64 -> PPPoE #1 delegated /64
fd00:10:10:10::/64 -> PPPoE #2 delegated /64
```

## 2. Cài mới trên máy test

Khuyến nghị thử V3 trên máy mới hoặc máy ảo trước.

Clone repo:

``` bash
cd ~
git clone -b v2-dev --single-branch https://github.com/dtthhoanglong/boxproxy.git
cd ~/boxproxy

git branch --show-current
git log -3 --oneline
```

Branch phải là:

``` text
v2-dev
```

Commit V3 đã push trong quá trình phát triển:

``` text
7aa22f3 Add V3 IPv6 PD and MAC routing support
```

Nếu repo đã clone từ trước:

``` bash
cd ~/boxproxy
git fetch origin
git checkout v2-dev
git pull --ff-only origin v2-dev
```

## 3. Tắt cloud-init

Trên Ubuntu Server mới:

``` bash
sudo touch /etc/cloud/cloud-init.disabled
sudo systemctl disable cloud-init-local.service
sudo systemctl disable cloud-init.service
sudo systemctl disable cloud-config.service
sudo systemctl disable cloud-final.service
```

## 4. Chạy installer V3

``` bash
cd ~/boxproxy
sudo bash install.sh
```

Installer V3 hiện cài thêm các thành phần IPv6 cần thiết, gồm:

``` text
dhcpcd5
radvd
```

Installer cũng cài:

``` text
/etc/ppp/ipv6-up.d/
/lib/dhcpcd/dhcpcd-hooks/
/etc/radvd.conf
/etc/sysctl.d/99-boxproxy-ipv6.conf
/etc/sysctl.d/99-boxproxy-ipv6-no-temp.conf
/etc/sysctl.d/90-boxproxy-ipv6-router.conf
```

Không dùng lại cấu hình V2:

``` text
99-boxproxy-disable-ipv6.conf
```

vì V3 cần IPv6 hoạt động.

## 5. LAN của V3

IPv4 LAN mặc định:

``` text
10.10.10.1/24
```

IPv6 ULA LAN:

``` text
fd00:10:10:10::1/64
```

Kiểm tra:

``` bash
ip -4 addr
ip -6 addr
```

Kiểm tra forwarding:

``` bash
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
```

## 6. Router Advertisement

V3 sử dụng `radvd` để client LAN tự nhận IPv6 bằng SLAAC.

Kiểm tra:

``` bash
sudo radvd --configtest -C /etc/radvd.conf
systemctl is-enabled radvd.service
systemctl is-active radvd.service
```

Xem config:

``` bash
cat /etc/radvd.conf
```

Client LAN phải nhận địa chỉ thuộc:

``` text
fd00:10:10:10::/64
```

## 7. PPPoE IPv6

Mỗi PPPoE instance có thể có `IP_MODE`:

``` text
ipv4
dual
ipv6
```

Kiểm tra instance:

``` bash
sudo cat /etc/boxproxy/instances/1.conf
```

Ví dụ:

``` text
WAN_TYPE="pppoe"
IP_MODE="dual"
PPP_IF="ppp01"
```

Kiểm tra PPP:

``` bash
systemctl is-active boxproxy-pppoe@1.service
ip -4 addr show dev ppp01
ip -6 addr show dev ppp01
```

Một PPPoE dual-stack hoạt động có thể có IPv6 global dạng:

``` text
2402:800:631a:xxxx:....../64
```

và IPv6 link-local:

``` text
fe80::....
```

## 8. DHCPv6 Prefix Delegation

Mỗi PPPoE session dùng service riêng:

``` text
boxproxy-ipv6-pd@1.service
boxproxy-ipv6-pd@2.service
...
```

Kiểm tra:

``` bash
systemctl is-active boxproxy-ipv6-pd@1.service
systemctl is-active boxproxy-ipv6-pd@2.service
```

Xem delegated prefix:

``` bash
sudo /usr/local/lib/boxproxy/ipv6-pd-prefix 1
sudo /usr/local/lib/boxproxy/ipv6-pd-prefix 2
```

Ví dụ:

``` text
2402:800:6318:4183::/64
2402:800:6318:3829::/64
```

Xem log:

``` bash
sudo journalctl -u boxproxy-ipv6-pd@1.service -n 50 --no-pager
```

Khi thành công sẽ thấy nội dung tương tự:

``` text
REPLY6 received
delegated prefix 2402:800:....::/64
```

## 9. Lifecycle PPPoE và IPv6-PD

V3 đã gắn lifecycle PD vào PPPoE.

Stop:

``` bash
sudo boxproxy stop 1
```

Sau đó:

``` bash
systemctl is-active boxproxy-pppoe@1.service
systemctl is-active boxproxy-ipv6-pd@1.service
```

cả hai phải dừng.

Start:

``` bash
sudo boxproxy start 1
```

Chờ PPPoE kết nối rồi kiểm tra:

``` bash
systemctl is-active boxproxy-pppoe@1.service
systemctl is-active boxproxy-ipv6-pd@1.service
sudo /usr/local/lib/boxproxy/ipv6-pd-prefix 1
```

Lưu ý ISP có thể mất một khoảng thời gian mới trả lời PPPoE Discovery
sau khi reconnect.

## 10. Change MAC

``` bash
sudo boxproxy change-mac 1
```

V3 sẽ:

1.  stop proxy/session;
2.  thay MAC macvlan;
3.  start lại PPPoE;
4.  start lại IPv6-PD;
5.  nhận lại IPv6/PD mới khi ISP cấp.

Kiểm tra:

``` bash
sudo grep '^MAC=' /etc/boxproxy/instances/1.conf

systemctl is-active boxproxy-pppoe@1.service
systemctl is-active boxproxy-ipv6-pd@1.service

ip -6 addr show dev ppp01
sudo /usr/local/lib/boxproxy/ipv6-pd-prefix 1
```

## 11. IPv6 LAN Routing theo MAC

Mục tiêu của V3 là giữ cách sử dụng giống IPv4:

``` text
Client MAC -> Proxy/PPPoE Session
```

Khi client được gán cho PPPoE session nào, IPv4 và IPv6 của client sẽ đi
theo session đó theo cấu hình routing tương ứng.

IPv6 sử dụng ULA LAN:

``` text
fd00:10:10:10::/64
```

và NETMAP sang delegated /64 của PPPoE session.

Kiểm tra:

``` bash
sudo ip6tables -t nat -L POSTROUTING -nv --line-numbers
```

Ví dụ:

``` text
NETMAP ... out ppp01 source fd00:10:10:10::/64 to:2402:800:6318:4183::/64
NETMAP ... out ppp02 source fd00:10:10:10::/64 to:2402:800:6318:3829::/64
```

Đây là phần routing IPv6 tương ứng với cách V2 định tuyến IPv4 theo MAC.

## 12. Client routing service

Kiểm tra:

``` bash
systemctl is-active boxproxy-client-routing.service
```

Các helper V3 liên quan gồm:

``` text
client-route-sync
client-route-sync-wait
client-route-up
ipv6-pd-prefix
ipv6-pd-run
ipv6-slots-apply
```

Service bổ sung:

``` text
boxproxy-client-routing-refresh.service
boxproxy-ipv6-pd@.service
```

## 13. PPP IPv6 hook

V3 cài hook:

``` text
/etc/ppp/ipv6-up.d/98-boxproxy-ipv6
```

Kiểm tra:

``` bash
ls -l /etc/ppp/ipv6-up.d/98-boxproxy-ipv6
```

DHCPv6-PD hook:

``` text
/lib/dhcpcd/dhcpcd-hooks/99-boxproxy-pd
```

Kiểm tra:

``` bash
ls -l /lib/dhcpcd/dhcpcd-hooks/99-boxproxy-pd
```

## 14. Kiểm tra nhanh V3

Ví dụ với hai PPPoE:

``` bash
echo "===== PPP ====="
systemctl is-active boxproxy-pppoe@1.service
systemctl is-active boxproxy-pppoe@2.service

echo
echo "===== IPV6 PD ====="
systemctl is-active boxproxy-ipv6-pd@1.service
systemctl is-active boxproxy-ipv6-pd@2.service

echo
echo "===== PREFIX ====="
sudo /usr/local/lib/boxproxy/ipv6-pd-prefix 1
sudo /usr/local/lib/boxproxy/ipv6-pd-prefix 2

echo
echo "===== PPP IPV6 ====="
ip -6 -br addr show dev ppp01
ip -6 -br addr show dev ppp02

echo
echo "===== CLIENT ROUTING ====="
systemctl is-active boxproxy-client-routing.service

echo
echo "===== NETMAP ====="
sudo ip6tables -t nat -L POSTROUTING -nv --line-numbers
```

## 15. Test IPv4 proxy

SOCKS5:

``` powershell
curl.exe --socks5-hostname USER:PASS@10.10.10.1:3901 https://api.ipify.org
```

HTTP:

``` powershell
curl.exe -x http://USER:PASS@10.10.10.1:4901 https://api.ipify.org
```

## 16. Test IPv6 từ LAN client

Trước tiên kiểm tra client có ULA:

Windows:

``` powershell
ipconfig
```

Linux:

``` bash
ip -6 addr
```

Sau đó:

``` powershell
curl.exe -6 https://api64.ipify.org
```

hoặc Linux:

``` bash
curl -6 https://api64.ipify.org
```

Khi đổi MAC routing của client sang PPPoE session khác, IPv6 public phải
chuyển sang prefix/session tương ứng.

## 17. Test sau reboot

``` bash
sudo reboot
```

Sau khi máy lên, không vội thao tác Start thủ công.

Kiểm tra:

``` bash
systemctl is-active boxproxy-web.service
systemctl is-active boxproxy-client-routing.service
systemctl is-active radvd.service

systemctl is-active boxproxy-pppoe@1.service
systemctl is-active boxproxy-ipv6-pd@1.service

ip -6 addr show dev ppp01
sudo /usr/local/lib/boxproxy/ipv6-pd-prefix 1

sudo ip6tables -t nat -L POSTROUTING -nv --line-numbers
```

## 18. DHCP và WiFi WAN

Các chức năng DHCP Ethernet WAN và WiFi WAN của V2 vẫn được giữ lại.

Quy tắc hiện tại:

``` text
1 DHCP WAN = 1 Proxy Session
1 WiFi WAN = 1 Proxy Session
```

Các WAN này vẫn dùng cơ chế V2 cho IPv4.

Phần IPv6-PD V3 được phát triển/test chủ yếu cho PPPoE multi-session.
Không nên coi DHCP/WiFi IPv6 là đã hoàn tất nếu chưa test riêng.

## 19. DDNS

DDNS No-IP của V2 vẫn được giữ.

Kiểm tra:

``` bash
systemctl is-active boxproxy-ddns.timer
systemctl list-timers --all | grep boxproxy-ddns
```

DDNS hiện vẫn chủ yếu phục vụ public IPv4 theo thiết kế V2.

## 20. Validation source

Trước khi commit/deploy:

``` bash
cd ~/boxproxy

bash -n install.sh
bash -n bin/boxproxy

for f in lib/*; do
    [ -f "$f" ] || continue
    bash -n "$f" || exit 1
done

for f in \
    ppp-hooks/ip-up.d/* \
    ppp-hooks/ip-down.d/* \
    ppp-hooks/ipv6-up.d/*; do
    [ -f "$f" ] || continue
    bash -n "$f" || exit 1
done

python3 -m py_compile web/app.py

git diff --check
git status -sb
```

## 21. Các vị trí quan trọng

``` text
Repo:                   ~/boxproxy
CLI:                    /usr/local/sbin/boxproxy
Libraries:              /usr/local/lib/boxproxy/
WebUI:                  /opt/boxproxy-web/

Main config:            /etc/boxproxy/settings.conf
WAN:                    /etc/boxproxy/wans/
Proxy instances:        /etc/boxproxy/instances/

Dante:                  /etc/boxproxy/dante/
Squid:                  /etc/boxproxy/squid/
DNS:                    /etc/boxproxy/dns/

LAN routing:            /etc/boxproxy/client-routes/
DDNS:                   /etc/boxproxy/ddns/

IPv6 PD UUID/state:     /etc/boxproxy/ipv6-pd-uuid/
IPv6 slots:             /etc/boxproxy/ipv6-slots/

PPP IPv6 hook:          /etc/ppp/ipv6-up.d/98-boxproxy-ipv6
dhcpcd PD hook:         /lib/dhcpcd/dhcpcd-hooks/99-boxproxy-pd

radvd:                  /etc/radvd.conf
Systemd:                /etc/systemd/system/boxproxy-*
```

## 22. Trạng thái V3 đã test trên máy J1900

Đã xác nhận trong quá trình phát triển:

-   Hai PPPoE session chạy đồng thời.
-   Hai PPPoE có IPv6 global.
-   Mỗi PPPoE nhận delegated `/64` riêng.
-   `boxproxy-ipv6-pd@1` và `@2` hoạt động.
-   Stop PPPoE dừng PD tương ứng.
-   Start PPPoE khởi động lại PD.
-   Change MAC reconnect PPPoE và PD.
-   Prefix có thể thay đổi sau reconnect.
-   IPv6 NETMAP được tạo theo từng PPPoE session.
-   `boxproxy-client-routing.service` hoạt động cùng IPv6 routing.
-   Source V3 đã commit và push lên `v2-dev`.

Ví dụ trạng thái đã test:

``` text
PPP #1: active
PPP #2: active

IPv6 PD #1: active
IPv6 PD #2: active

PD #1: 2402:800:6318:4183::/64
PD #2: 2402:800:6318:3829::/64
```

## 23. Lưu ý khi test trên VMware

Có thể dùng VMware để kiểm tra:

-   installer;
-   WebUI;
-   service lifecycle;
-   cấu hình PPPoE nếu mạng test cho phép;
-   IPv4;
-   syntax và reboot restore.

Tuy nhiên việc xác nhận **IPv6 DHCPv6-PD thực tế** phụ thuộc ISP/router
và cách card mạng VMware được bridge. Kết quả IPv6-PD trên VMware không
thay thế hoàn toàn bài test trên máy vật lý J1900.

## 24. Nâng cấp máy đang chạy

Không nên dùng quy trình nâng cấp V2 cũ một cách máy móc cho máy
production V3.

V3 thay đổi:

-   sysctl IPv6;
-   netplan LAN IPv6;
-   `radvd`;
-   PPP IPv6 hooks;
-   dhcpcd hooks;
-   systemd PD services;
-   routing IPv6.

Với máy đang chạy ổn định, phải backup `/etc/boxproxy`, netplan, PPP
hooks và systemd trước khi nâng cấp.

Trong giai đoạn V3 đang test, ưu tiên **fresh install trên máy
test/VMware** trước khi xây dựng quy trình nâng cấp production chính
thức.
