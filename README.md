# 🎛️ OpenWrt M3 Cockpit (`v2.3`)

Bảng điều Khiển quan trị sáng tạo & thiết bị siêu nhẹ theo phong cách **Material You (M3)** dụng cho router **Xiaomi Mi Router CR6608** (MediaTek MT7621AT) chạy **OpenWrt 25.12+ (`apk`)** ở chế độ **Wi-Fi Repeater**.

---

## ✨ Tính xưng oổi bật (v2.3)

### 1. 📱 Quản lý Thiết bị & Tıng lửa (`nftables`)
* **Theo dõi real-time:** Hiển thị danh sách thiết bị đang kết nối qua Wi-Fi (`2.4GHz` / `5GHz`) và dây LAN kèm IP, MAC, tên tuỳ chỉnh và cƷờng độ sóng (`dBm`).
* **Chặn / Mở khóa tức thì:** Cô lập hoẵc moở lại quyền truy cập Internet của từng thiết bị bằng rule `nftables` thời gian thực.
* **Wake-on-LAN (WOL);** Đánh thức PC/Laptop trong mạng LAN chỉ với 1 chạm qua `etherwake`.

### 2. 🚀 Auto-SQM Chống Lag (Tối ưu cho MT7621)
* **Đo tốc độ 4 luồng song song:** Tự động tạm dừng SQM trong 5 gi�ay, tải 4 luồng `curl` song song để lấy trọn băng thông thực tế, sau đó tính **85%** cài đặt tối ưu.
* **Gắn trực tiếp vào sòng phát 5GHz (`phy1-ap0`):** Sử dụng thuật toán `fq_codel` + `simple.qos`, giù nguyên tốc độ cao (~135-170 Mbps) m` vẫn triệt tiêu Bufferbloat.
* **Nhập tay Mbps linh hoạt:** Cho phép đặt nhanh mức giới hạn Download/Upload theo ý muốn.

### 3. 📡 Repeater Tự Cứu Mạng (Auto-Failover)
* **Quét & Chuyển Wi-Fi gốc ngay trên web:** Quét sóng xung quanh kèm chỉ số `dBm`, lưu lật khẩu vào danh sách dự phòng.
* **Tự động chuyển mạng khi mất kết nối:** Cronjob kiểm tra ping định kỳ mỗi 2 phút và tự động chuyển sang Wi-Fi dự phòng mạnh nhất.

### 4. 🞙 Tối ưu Hệ thống & Tự động cập nhật
* **Dọn sạch RAM & Cache (`/tmp`):** Ghải phóng pagecache Linux và file tạm chỉ với 1 nút bấm.
* **Auto-Reload thông minh:** Tự động nhận diện phiên bản lới và xóa cache trình duyệt.

---

## 📂 Cấu và kiến trúc thư mục

- `install.sh` — Script cài đặt tự động 1 dòng trên OpenWrt
-  www/devmgr.html` — Giao diện chính Material You (Single-file HTML/CSS/JS)
- `www/login.html` — Trang đang nhập xác thực ubus
-  www/cgi-bin/devmgr` — Kênh CGI quản lý thiết bị, MAC, WOL- `www/cgi-bin/devmgr-net` — Kênh CGI độc lập cho SQM, Speedtest, Repeater, RAM
-  www/cgi-bin/devmgr-login` — Kênh CGI cấp phát session cookie
- `etc/devmgr/api.sh` — Backend xử lý thiết bị & nftables
- `etc/devmgr/net_api.sh` — Backend xử lý Auto-SQM 4 luồng, Wi-Fi scan & dọn RAM
- `etc/devmgr/failover.sh` — Script cron tự động chuyển Wi-Fi dự phòng
- `etc/devmgr/init.sh` — Khởi tạo bảng nftables & rule khi router reboot

---

## ⚡ Cài đặt nhanh (1 dòng lệnh)

Kết nối SSH vào router OpenWrt (`192.168.2.1`) và chạy:

```bash
wget -qO- https://raw.githubusercontent.com/vudubai-2026/openwrt-m3-cockpit/main/install.sh | sh
```

### Cài đặt các gói phụ trợ cần thiết (OpenWrt 25.12+ dùng `apk`)

```bash
apk update && apk add curl sqm-scripts etherwake
```

Sau khi cài xong, truy cập giao diện quản lý tại: `http://192.168.2.1/devmgr.html`.
