# BoxProxy V1 – Hướng dẫn cài đặt

BoxProxy V1 chạy trên **Ubuntu Server 22.04 LTS** và cung cấp:

* Nhiều phiên PPPoE độc lập trên một WAN vật lý bằng `macvlan`.
* SOCKS5 proxy bằng **Dante**.
* HTTP proxy bằng **Squid**.
* Mỗi PPPoE session có public IPv4 riêng.
* Start / Stop / Restart từng PPPoE session.
* Change MAC để reconnect PPPoE và lấy IP mới.
* Change Password ngẫu nhiên cho từng proxy.
* Bật / tắt proxy độc lập với PPPoE.
* Quản lý nhiều WAN.
* Định tuyến máy LAN theo **MAC address** sang PPPoE session được chỉ định.
* WebUI quản lý tại cổng `8080`.

---

## 1. Yêu cầu hệ thống

Khuyến nghị:

* Ubuntu Server 22.04 LTS.
* Tối thiểu 2 interface mạng:

  * WAN: nối tới modem/ONT đang Bridge PPPoE.
  * LAN: mạng quản trị và mạng client.
* Tài khoản có quyền `sudo`.
* Có Internet trong quá trình cài đặt package.

Ví dụ hệ thống test:

```text
WAN: ens33
LAN: ens34
LAN IP: 10.10.10.1/24
WebUI: http://10.10.10.1:8080
```

Tên interface trên máy thật có thể khác.

Kiểm tra bằng:

```bash
ip -br link
```

---

## 2. Clone BoxProxy từ GitHub

```bash
cd ~
git clone git@github.com:dtthhoanglong/boxproxy.git
cd boxproxy
```

Hoặc nếu máy không sử dụng SSH key GitHub, clone bằng HTTPS.

---

## 3. Tắt cloud-init

BoxProxy tự quản lý cấu hình network. `cloud-init` có thể ghi lại Netplan sau reboot và làm thay đổi WAN/LAN đã cấu hình.

Tắt cloud-init:

```bash
sudo touch /etc/cloud/cloud-init.disabled
```

Disable các service:

```bash
sudo systemctl disable cloud-init-local.service
sudo systemctl disable cloud-init.service
sudo systemctl disable cloud-config.service
sudo systemctl disable cloud-final.service
```

Có thể kiểm tra:

```bash
systemctl is-enabled cloud-init-local.service
systemctl is-enabled cloud-init.service
systemctl is-enabled cloud-config.service
systemctl is-enabled cloud-final.service
```

Không được để `cloud-init` tự tạo lại cấu hình mạng của BoxProxy sau reboot.

---

## 4. Tắt network wait-online

Trong quá trình test đã phát hiện Ubuntu có thể chờ interface mạng quá lâu khi boot/shutdown nếu một interface không có carrier hoặc PPPoE chưa kết nối.

BoxProxy không cần chờ `systemd-networkd-wait-online`.

Disable bằng:

```bash
sudo systemctl mask systemd-networkd-wait-online.service
```

Kiểm tra:

```bash
systemctl is-enabled systemd-networkd-wait-online.service
```

Kết quả mong muốn:

```text
masked
```

`install.sh` của BoxProxy V1 cũng thực hiện bước này tự động.

---

## 5. Chạy installer

Trong thư mục repo:

```bash
cd ~/boxproxy
sudo bash install.sh
```

Installer sẽ cài và cấu hình các thành phần cần thiết, bao gồm:

* PPP / PPPoE
* Dante
* Squid
* DHCP server
* BoxProxy CLI
* BoxProxy WebUI
* systemd services
* PPP hooks
* routing scripts
* client MAC routing
* IPv4 forwarding
* network configuration cần thiết

Installer cũng kiểm tra syntax các script trước khi hoàn tất.

---

## 6. Squid shutdown chậm

Trong quá trình test thực tế, Squid có thể làm Ubuntu phải chờ khá lâu khi shutdown/reboot nếu sử dụng thời gian shutdown mặc định.

BoxProxy V1 sử dụng:

```text
shutdown_lifetime 1 second
```

trong cấu hình Squid được sinh cho từng proxy.

Điều này cho phép Squid kết thúc nhanh khi:

* Stop proxy.
* Restart PPPoE.
* Reboot máy.
* Shutdown máy.

Không nên bỏ dòng này khỏi `lib/squid-generate`.

Kiểm tra một Squid config đang chạy:

```bash
grep shutdown_lifetime /etc/boxproxy/squid/*.conf
```

Kết quả phải có:

```text
shutdown_lifetime 1 second
```

---

## 7. TCP MSS khi LAN routing qua PPPoE

PPPoE sử dụng MTU `1492`, trong khi LAN thông thường sử dụng MTU `1500`.

Trong quá trình test MAC-based client routing, client vẫn có Internet và ping bình thường nhưng:

* Firefox mở trang rất chậm.
* Download rất chậm.
* Fast.com không chạy đúng.
* Speedtest không chạy đúng.

Nguyên nhân là TCP MSS của traffic LAN đi ra PPPoE.

BoxProxy V1 xử lý bằng rule:

```bash
iptables -t mangle -A FORWARD \
    -i "$LAN_IF" \
    -o ppp+ \
    -p tcp \
    --tcp-flags SYN,RST SYN \
    -m comment \
    --comment BOXPROXY-MSS \
    -j TCPMSS \
    --set-mss 1452
```

Rule được quản lý bởi:

```text
/usr/local/lib/boxproxy/client-route-sync
```

và service:

```text
boxproxy-client-routing.service
```

Không cần thêm rule thủ công sau mỗi reboot.

Kiểm tra:

```bash
sudo iptables -t mangle -S FORWARD
```

Phải thấy rule tương tự:

```text
-A FORWARD -i <LAN_IF> -o ppp+ -p tcp \
-m tcp --tcp-flags SYN,RST SYN \
-m comment --comment BOXPROXY-MSS \
-j TCPMSS --set-mss 1452
```

Rule phải chỉ xuất hiện **một lần**.

---

## 8. Dante SOCKS5

Dante tạo SOCKS5 proxy cho từng PPPoE session.

Proxy được listen trên:

```text
LAN_IP:SOCKS_PORT
PUBLIC_PPP_IP:SOCKS_PORT
```

Ví dụ Proxy #1:

```text
10.10.10.1:3901
27.x.x.x:3901
```

Proxy #2:

```text
10.10.10.1:3902
116.x.x.x:3902
```

Dante sử dụng username/password authentication.

SOCKS5 UDP Associate cũng được hỗ trợ.

Trong quá trình test, SOCKS5 TCP authentication và UDP relay đã hoạt động thành công.

---

## 9. Squid HTTP Proxy

Squid của mỗi proxy listen trên cả:

```text
LAN_IP:HTTP_PORT
PUBLIC_PPP_IP:HTTP_PORT
```

Ví dụ:

```text
Proxy #1 HTTP: 10.10.10.1:4901
Proxy #2 HTTP: 10.10.10.1:4902
```

và đồng thời listen trên IPv4 public tương ứng.

HTTP proxy yêu cầu authentication.

Traffic outbound được bind vào đúng public IPv4 của PPPoE session:

```text
tcp_outgoing_address <PPP_PUBLIC_IP>
```

---

## 10. WebUI

Sau khi cài đặt:

```text
http://10.10.10.1:8080
```

WebUI hiện hỗ trợ:

* WAN Configuration
* Add WAN
* Delete WAN
* Đổi interface WAN
* PPPoE username/password
* Proxy Count
* Proxy ON/OFF
* Start PPPoE
* Stop PPPoE
* Restart PPPoE
* Change MAC
* Change Password
* Copy SOCKS5
* Copy HTTP
* Copy All SOCKS5
* LAN Routing theo MAC

---

## 11. Change Password

Password proxy được **sinh ngẫu nhiên tự động**.

Không cần nhập password thủ công.

Khi bấm:

```text
Change Password
```

BoxProxy sẽ:

1. Sinh password mới.
2. Cập nhật credential.
3. Cập nhật Dante/Squid.
4. Restart proxy service cần thiết.
5. WebUI hiển thị credential mới.

---

## 12. Change MAC

Mỗi PPPoE session chạy qua một `macvlan` riêng.

Ví dụ:

```text
mvppp01
mvppp02
mvppp03
```

Change MAC sẽ:

1. Stop PPPoE session tương ứng.
2. Đổi MAC của macvlan.
3. Start lại PPPoE.
4. Chờ public IPv4.
5. Khởi động lại proxy theo IPv4 mới.

ISP có thể tạm thời không trả PADO nếu reconnect PPPoE liên tục.

Log có thể xuất hiện:

```text
Timeout waiting for PADO packets
Unable to complete PPPoE Discovery
```

Đây không nhất thiết là lỗi BoxProxy.

`pppd` có thể tiếp tục retry và PPPoE sẽ kết nối lại khi ISP trả PADO.

---

## 13. LAN Routing theo MAC

BoxProxy có thể ép một client LAN đi ra một PPPoE session cụ thể dựa trên MAC address.

Ví dụ:

```text
Client MAC:
00:0c:29:53:26:2e

Client IP:
10.10.10.101

Proxy:
Proxy #1

PPP:
ppp01

Routing Table:
101

Mark:
10001
```

Client không cần cấu hình SOCKS5 hoặc HTTP proxy.

Toàn bộ traffic Internet thông thường sẽ được NAT qua PPPoE session được chỉ định.

Có thể đổi client sang PPPoE khác từ WebUI.

---

## 14. Kiểm tra PPPoE

```bash
ip -br addr
```

Ví dụ:

```text
mvppp01@ens33    UP
ppp01            UNKNOWN    27.x.x.x

mvppp02@ens33    UP
ppp02            UNKNOWN    116.x.x.x
```

Kiểm tra process:

```bash
ps aux | grep '[p]ppd'
```

---

## 15. Kiểm tra Dante và Squid

```bash
ps aux | grep -E 'danted|squid' | grep -v grep
```

Kiểm tra port:

```bash
sudo ss -lntup | grep -E 'danted|squid'
```

Ví dụ:

```text
10.10.10.1:3901   SOCKS5 #1
10.10.10.1:3902   SOCKS5 #2

10.10.10.1:4901   HTTP #1
10.10.10.1:4902   HTTP #2
```

Ngoài LAN IP, proxy đang bật còn listen trên public PPPoE IPv4 tương ứng.

---

## 16. Kiểm tra client routing

Kiểm tra policy routing:

```bash
ip rule show
```

Ví dụ:

```text
1001: from <PPP1_PUBLIC_IP> lookup 101
1002: from <PPP2_PUBLIC_IP> lookup 102
2001: from all fwmark 0x2711 lookup 101
2002: from all fwmark 0x2712 lookup 102
```

Kiểm tra routing table:

```bash
ip route show table 101
ip route show table 102
```

Ví dụ:

```text
default dev ppp01 scope link metric 10
```

và:

```text
default dev ppp02 scope link metric 10
```

---

## 17. Kiểm tra rp_filter

BoxProxy multi-WAN/policy routing sử dụng loose reverse path filtering.

Kiểm tra:

```bash
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.default.rp_filter
```

Giá trị mong muốn:

```text
2
```

Không nên dùng strict mode `1` cho mô hình nhiều PPPoE/policy routing này.

---

## 18. Reboot test sau khi cài

Sau khi hoàn tất cấu hình nên reboot:

```bash
sudo reboot
```

Sau khi máy lên lại kiểm tra:

```bash
ip -br addr
```

```bash
sudo systemctl status boxproxy-client-routing.service --no-pager
```

```bash
sudo iptables -t mangle -S FORWARD
```

```bash
ps aux | grep '[p]ppd'
```

```bash
sudo ss -lntup | grep -E 'danted|squid'
```

Cần xác nhận:

* PPPoE tự khởi động lại.
* Proxy tự khởi động lại.
* Public IPv4 xuất hiện.
* MAC client routing được khôi phục.
* `BOXPROXY-MSS` xuất hiện đúng một lần.
* Client LAN truy cập Internet bình thường.
* WebUI hoạt động.

---

## 19. Shutdown

Shutdown:

```bash
sudo poweroff
```

BoxProxy đã được cấu hình để tránh các nguyên nhân từng gây shutdown chậm:

* `systemd-networkd-wait-online` được mask.
* Squid sử dụng:

```text
shutdown_lifetime 1 second
```

Do đó shutdown/reboot không nên phải chờ Squid khoảng 30 giây như cấu hình mặc định trước đây.

---

## 20. Lưu ý khi test nhiều PPPoE

Số PPPoE session mà ISP cho phép phụ thuộc vào chính sách của ISP và gói cước.

Nếu PPPoE Discovery liên tục báo:

```text
Timeout waiting for PADO packets
```

không nên Change MAC/Restart liên tục.

Hãy để PPPoE chờ hoặc thử lại sau.

---

## 21. Cập nhật BoxProxy từ GitHub

Kiểm tra source:

```bash
cd ~/boxproxy
git status
```

Cập nhật:

```bash
git pull origin main
```

Lưu ý: `git pull` chỉ cập nhật source trong:

```text
~/boxproxy
```

Nó không tự động thay thế toàn bộ file đang được cài trong:

```text
/usr/local/lib/boxproxy
/usr/local/sbin
/opt/boxproxy-web
```

Nếu triển khai phiên bản mới trên máy sạch, nên chạy installer theo hướng dẫn của phiên bản đó.

---

## 22. Các vị trí quan trọng

```text
Repo:
~/boxproxy

CLI:
/usr/local/sbin/boxproxy

Libraries:
/usr/local/lib/boxproxy/

WebUI:
/opt/boxproxy-web/

BoxProxy config:
/etc/boxproxy/

PPPoE instances:
/etc/boxproxy/instances/

Dante config:
/etc/boxproxy/dante/

Squid config:
/etc/boxproxy/squid/

Client routing:
/etc/boxproxy/client-routes/

Systemd:
/etc/systemd/system/boxproxy-*.service
```

---

## Trạng thái BoxProxy V1 đã kiểm tra

Các chức năng đã được kiểm tra thực tế trong quá trình phát triển:

* PPPoE multi-session.
* Stop / Start PPPoE độc lập.
* Reconnect và đổi public IPv4.
* Change MAC.
* Change Password ngẫu nhiên.
* SOCKS5 authentication.
* SOCKS5 UDP relay.
* HTTP authenticated proxy.
* SOCKS5/HTTP trên public PPPoE IPv4.
* MAC-based LAN client routing.
* Policy routing từng PPPoE.
* MSS 1452 cho LAN → PPPoE.
* Client routing tự phục hồi sau reboot.
* MSS rule tự phục hồi sau reboot.
* WebUI.
