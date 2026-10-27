# Fan Control

App menu bar tự chỉnh tốc độ quạt MacBook (Apple Silicon M1/M2) theo nhiệt độ CPU/GPU.

Popover còn hiện nhanh CPU %, RAM (kèm áp lực bộ nhớ), dung lượng ổ đĩa trống và tốc độ mạng (Wi-Fi/Ethernet).

## Cài đặt (cho người dùng)

1. Mở `FanControl-<phiên bản>.dmg`, kéo **FanControl** vào thư mục **Applications**.
2. **Thoát Macs Fan Control** (hoặc app chỉnh quạt khác) nếu đang chạy, để hai app không tranh nhau điều khiển quạt.
3. Mở **FanControl** (⌘ + Space → gõ "FanControl"). App không có cửa sổ hay icon Dock: nó hiện icon quạt kèm nhiệt độ ở **góc phải thanh menu**. Nếu không thấy, có thể icon bị tai thỏ che, hãy bớt icon khác trên thanh menu.
4. Click icon quạt → **Cài đặt helper** → nhập mật khẩu máy. Helper chạy nền để chỉnh tốc độ quạt; chỉ cần cài một lần.
5. Chọn chế độ trong popover. Muốn tự chỉnh đường cong: **Cài đặt… → Đường cong → Nhân bản**.

Bật "Mở khi đăng nhập" trong **Cài đặt… → Chung**. Kể cả khi không mở app, helper vẫn điều khiển quạt theo chế độ đã chọn.

## Chế độ

| Chế độ | Hành vi |
|---|---|
| Apple tự động | macOS tự lo |
| Êm | 65°C→0%, 75°C→30%, 85°C→60%, 92°C→100% |
| Cân bằng | 55°C→0%, 65°C→35%, 75°C→65%, 85°C→100% |
| Hiệu năng | 45°C→20%, 60°C→50%, 70°C→80%, 78°C→100% |
| Tối đa | luôn 100% |

Dưới điểm đầu tiên của đường cong, quạt được trả về cho Apple. Ở mọi chế độ, khi nhiệt độ ≥ 95°C quạt luôn chạy tối đa.

## Gỡ cài đặt

**Cài đặt… → Chung → Gỡ helper** (quạt trở về chế độ của Apple), rồi xóa `/Applications/FanControl.app`.

## Build (cho người phát triển)

Yêu cầu: macOS 14+, Xcode có Swift 6, chứng chỉ "Developer ID Application" của team `99G56BJA4B` trong keychain.

```bash
make test        # unit test
make install     # build, ký, copy vào /Applications
make icon        # vẽ lại Resources/AppIcon.icns từ scripts/make-icon.swift
make dmg         # build/FanControl-<phiên bản>.dmg (đã ký, chưa notarize)
make notarize    # dmg + notarize + staple (cần keychain profile, xem dưới)
```

Tạo keychain profile cho notarize một lần:

```bash
xcrun notarytool store-credentials fancontrol-notary --apple-id <email> --team-id 99G56BJA4B
```

Helper chỉ nhận kết nối từ app ký bằng Developer ID của team `99G56BJA4B`. Bản ký ad-hoc sẽ không điều khiển được quạt.

## Gỡ lỗi

```bash
.build/release/fanctld --probe                                   # xem quạt + nhiệt độ (không cần root)
.build/release/fanctld --dry-run --config /tmp/fanctl.json       # chạy thử, chỉ log
tail -f /var/log/fanctld.log                                     # log helper
sudo launchctl print system/local.fancontrol.daemon | grep state # trạng thái helper
FANCTL_HW=1 swift test --filter readsRealSMC                     # test đọc SMC thật
```
