# Hướng dẫn cài đặt BoxProxy V1

## 1. Yêu cầu

BoxProxy V1 được xây dựng và kiểm thử trên:

- Ubuntu Server 22.04 LTS
- Tối thiểu 2 interface mạng
- Một interface làm WAN PPPoE
- Một interface làm LAN
- Modem/ONT của ISP phải hỗ trợ Bridge Mode nếu quay PPPoE trực tiếp từ BoxProxy

BoxProxy V1 hiện hỗ trợ WAN PPPoE.

WAN DHCP Client dự kiến được bổ sung trong BoxProxy V2.

---

## 2. Mô hình mạng mặc định

LAN của BoxProxy:

    Gateway:        10.10.10.1/24
    DHCP động:      10.10.10.2 - 10.10.10.100
    IP tĩnh client: 10.10.10.101 - 10.10.10.254

Các client trong LAN sử dụng:

    Gateway: 10.10.10.1

Web UI:

    http://10.10.10.1:8080/

---

## 3. Clone source

Clone repository bằng SSH:

    git clone git@github.com:dtthhoanglong/boxproxy.git

Sau đó:

    cd boxproxy

---

## 4. Chạy installer

Cho quyền execute nếu cần:

    chmod +x install.sh

Chạy:

    sudo ./install.sh

Installer sẽ hiển thị danh sách interface mạng.

Ví dụ:

    ens33
    ens34
    enp2s0
    enp3s0

Chọn:

- WAN interface: interface nối tới modem/ONT Bridge Mode.
- LAN interface: interface nối tới switch, Access Point hoặc client LAN.

WAN và LAN phải là hai interface khác nhau.

---

## 5. Những việc installer thực hiện

Installer sẽ:

- Cài PPP/PPPoE.
- Cài Dante SOCKS5.
- Cài Squid HTTP Proxy.
- Cài ISC DHCP Server.
- Cài Flask Web UI.
- Cài các script BoxProxy.
- Cài systemd service.
- Cài PPP ip-up/ip-down hooks.
- Bật IPv4 forwarding.
- Tắt IPv6 theo cấu hình BoxProxy V1.
- Tạo LAN 10.10.10.1/24.
- Tạo DHCP pool 10.10.10.2 - 10.10.10.100.
- Chuẩn bị vùng IP tĩnh 10.10.10.101 - 10.10.10.254.
- Sinh mật khẩu proxy ban đầu ngẫu nhiên.
- Backup cấu hình Netplan cũ trước khi thay đổi.
- Tạo Netplan mới theo WAN/LAN đã chọn.

Installer không áp dụng Netplan trực tiếp trong phiên SSH hiện tại để tránh làm mất kết nối trong lúc cài.

---

## 6. Reboot

Sau khi installer hoàn tất:

    sudo reboot

Sau khi máy khởi động lại, LAN BoxProxy sẽ sử dụng:

    10.10.10.1

Kết nối máy quản trị vào LAN BoxProxy.

Máy quản trị có thể nhận DHCP trong khoảng:

    10.10.10.2 - 10.10.10.100

---

## 7. Truy cập Web UI

Mở trình duyệt:

    http://10.10.10.1:8080/

Trang chính:

    /

Dùng để quản lý:

- WAN
- PPPoE session
- SOCKS5 proxy
- HTTP proxy
- Start/Stop session
- Change MAC
- Change proxy password
- Enable/Disable proxy

Trang định tuyến:

    /routing

Dùng để:

- Xem client LAN.
- Gán client vào PPPoE proxy/session.
- Chuyển client sang session khác.
- Xóa routing.
- Gán IP LAN tĩnh.
- Xóa IP LAN tĩnh.
- Kiểm tra IP tĩnh bị trùng.

---

## 8. Thêm WAN PPPoE

Trong Web UI chọn Add WAN.

Nhập:

- Physical interface
- PPPoE username
- PPPoE password

Credential PPPoE chỉ được lưu trên máy BoxProxy.

Không commit credential PPPoE vào Git repository.

---

## 9. Tạo Proxy

Sau khi WAN đã được thêm, tạo số lượng proxy/session cần thiết.

Mỗi instance có:

- MAC riêng.
- macvlan riêng.
- PPPoE session riêng.
- PPP interface riêng.
- SOCKS5 port riêng.
- HTTP port riêng.
- Proxy username/password riêng.

Port mặc định:

    Proxy #1:
      SOCKS5 3901
      HTTP   4901

    Proxy #2:
      SOCKS5 3902
      HTTP   4902

    Proxy #3:
      SOCKS5 3903
      HTTP   4903

Công thức:

    SOCKS5 = 3900 + Proxy ID
    HTTP   = 4900 + Proxy ID

---

## 10. Định tuyến client theo MAC

Trang:

    http://10.10.10.1:8080/routing

BoxProxy có thể gán một client LAN vào một PPPoE instance cụ thể.

Ví dụ:

    Client MAC
        |
        v
    BoxProxy LAN
        |
        v
    fwmark
        |
        v
    Policy Routing Table
        |
        v
    PPPoE Session
        |
        v
    Internet

Khi chuyển client từ Proxy #2 sang Proxy #3, public IP của client sẽ chuyển sang public IP của PPPoE session #3.

---

## 11. DHCP và IP tĩnh

DHCP động:

    10.10.10.2 - 10.10.10.100

IP dành cho reservation/static:

    10.10.10.101 - 10.10.10.254

Ví dụ:

    MAC 00:11:22:33:44:55
        ->
    10.10.10.101

BoxProxy kiểm tra trước khi lưu để tránh gán cùng một IP tĩnh cho hai thiết bị.

Khi không cần reservation nữa, có thể Remove để giải phóng IP cho thiết bị khác.

---

## 12. Kiểm tra CLI

Xem WAN:

    sudo boxproxy wan-json

Xem proxy:

    sudo boxproxy web-json

Xem client:

    sudo boxproxy client-json

Xem static LAN IP:

    sudo boxproxy client-ip-json

Kiểm tra policy routing:

    ip rule show

Kiểm tra packet marking:

    sudo iptables -t mangle -S PREROUTING

Kiểm tra NAT:

    sudo iptables -t nat -S POSTROUTING

---

## 13. Các thư mục quan trọng

BoxProxy config:

    /etc/boxproxy/

WAN:

    /etc/boxproxy/wans/

Proxy instances:

    /etc/boxproxy/instances/

Client routing:

    /etc/boxproxy/client-routes/

Generated Dante config:

    /etc/boxproxy/dante/

Generated Squid config:

    /etc/boxproxy/squid/

Web UI:

    /opt/boxproxy-web/

BoxProxy libraries:

    /usr/local/lib/boxproxy/

CLI:

    /usr/local/sbin/boxproxy

---

## 14. Bảo mật

Không đưa các file runtime chứa credential lên Git.

Đặc biệt không commit:

- PPPoE username/password.
- Proxy password thật.
- Runtime WAN config.
- Runtime instance config.
- Client MAC/IP mapping.
- SSH private key.

SSH private key của server cũng không được sao chép vào repository.

---

## 15. Phạm vi BoxProxy V1

BoxProxy V1 tập trung vào:

- Multi-WAN PPPoE.
- Multi-session PPPoE.
- SOCKS5.
- HTTP Proxy.
- Web UI.
- MAC-based routing.
- Static LAN IP reservation.
- DHCP LAN.

Các tính năng dự kiến cho V2 có thể bao gồm:

- WAN DHCP Client.
- Chuyển WAN giữa PPPoE và DHCP.
- Cải tiến phát hiện trạng thái online/offline của client.
