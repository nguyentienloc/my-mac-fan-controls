# Thông tin hệ thống trong popover + icon app — Thiết kế

Ngày: 2026-10-27

## Mục tiêu

1. Popover hiện thêm **CPU %, RAM, ổ đĩa, tốc độ mạng** cạnh nhiệt độ và quạt. Bố cục 2 khối: trên là thông tin hệ thống, dưới là chọn nhanh chế độ quạt (bố cục "A" đã chọn qua mockup).
2. App có **icon riêng** thay cho icon mặc định.

**Giữ nguyên:** thanh menu vẫn chỉ hiện icon quạt và nhiệt độ. Daemon `fanctld`, protocol XPC và cấu hình không đổi; không cần cài lại helper.

**Ngoài phạm vi:** biểu đồ lịch sử, tốc độ đọc/ghi đĩa, % GPU, nhiều ổ đĩa, tùy chọn ẩn/hiện từng chỉ số.

## Kiến trúc

Số liệu hệ thống được đọc **trong app** (quyền user, API công khai), không qua daemon.

Thêm library target **`SystemStats`** (không phụ thuộc target khác). `FanControlApp` phụ thuộc thêm `SystemStats`. Test ở `Tests/SystemStatsTests`.

| Thành phần | Nguồn | Cách tính |
|---|---|---|
| `CPUUsage` | `host_statistics(HOST_CPU_LOAD_INFO)` | Đọc tick `user`, `system`, `idle`, `nice`. Hàm thuần `usage(from:to:) -> Double?`: % = (Δuser + Δsystem + Δnice) ÷ Δtổng × 100; trả `nil` khi Δtổng = 0 |
| `MemoryStats` | `host_statistics64(HOST_VM_INFO64)`, `vm_kernel_page_size`, `ProcessInfo.physicalMemory`, sysctl `kern.memorystatus_vm_pressure_level` | Đã dùng = (internal − purgeable + wired + compressor) × page size, khớp "Memory Used" của Activity Monitor. Áp lực: 1 → `.normal` ("bình thường"), 2 → `.warning` ("cao"), 4 → `.critical` ("nguy hiểm"), giá trị khác → `.normal` |
| `DiskStats` | `URL(fileURLWithPath: "/")` với `volumeAvailableCapacityForImportantUsageKey`, `volumeTotalCapacityKey` | Trống / tổng của ổ khởi động, giống số Finder hiện |
| `NetworkStats` | sysctl `NET_RT_IFLIST2` → `if_msghdr2` (bộ đếm `ifi_ibytes`/`ifi_obytes` 64-bit) | Đọc bộ đếm theo **từng card mạng vật lý** (tên bắt đầu `en`: Wi-Fi/Ethernet) đang UP, bỏ loopback. Không đếm `utun*` (VPN), `bridge*`, `awdl*`… vì lưu lượng của chúng đi chồng qua `en*` nên sẽ bị đếm trùng. Hàm thuần `rates(from:to:elapsed:)` cộng Δbyte của các card có ở cả 2 lần đo; card mới xuất hiện hoặc có bộ đếm giảm (reset) thì bỏ qua card đó. Trả `nil` khi `elapsed <= 0` |
| `SystemSampler` | gom các thành phần trên qua protocol `SystemSource` (bản thật đọc hệ thống, bản giả cho test) | `sample(now: Date) -> SystemSnapshot`. Giữ mẫu CPU và mạng lần trước. Lần đầu: `cpuPercent` và tốc độ mạng là `nil` |

```swift
public struct SystemSnapshot: Equatable {
    public var cpuPercent: Double?          // 0...100
    public var memoryUsed: UInt64           // byte
    public var memoryTotal: UInt64
    public var memoryPressure: MemoryPressure
    public var diskFree: UInt64?            // nil nếu đọc lỗi
    public var diskTotal: UInt64?
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?
}
```

Lỗi đọc từng nguồn không làm hỏng cả snapshot: nguồn nào lỗi thì trường đó là `nil` (CPU, đĩa, mạng) hoặc giữ giá trị 0 (RAM, rất khó lỗi).

### Định dạng (thêm vào `Shared/Format`)

Dấu phẩy thập phân kiểu Việt, không phụ thuộc locale máy:

- `Format.memory(_ bytes: UInt64)`: hệ 1024 như Activity Monitor, 1 chữ số thập phân. 12_025_908_428 → "11,2 GB"; 17_179_869_184 → "16 GB" (bỏ ",0").
- `Format.disk(_ bytes: UInt64)`: hệ 1000 như Finder, số nguyên. 182_400_000_000 → "182 GB"; ≥ 1000 GB → "1,2 TB".
- `Format.rate(_ bytesPerSecond: Double?)`: hệ 1000. < 1000 → "850 B/s"; < 1 MB → "85 KB/s" (số nguyên); còn lại → "1,2 MB/s" (1 chữ số thập phân); `nil` → "--".
- `Format.percent(_ value: Double?)`: "23%"; `nil` → "--%".

### AppModel

- Thêm `private(set) var system: SystemSnapshot?` và một `SystemSampler` (`@ObservationIgnored`).
- Trong vòng poll 2 giây hiện có: lấy mẫu hệ thống (`system = sampler.sample(now: Date())`) rồi mới `refresh()` daemon. Lấy mẫu chạy cả khi chưa cài helper.

## Giao diện popover (bố cục A)

Rộng 300pt.

**Khối trên, tiêu đề nhỏ "Hệ thống":** lưới thẻ 2×2 (`LazyVGrid` 2 cột), mỗi thẻ là nền bo góc nhẹ với nhãn nhỏ, số lớn và dòng phụ.

| Thẻ (nhãn + SF Symbol) | Số lớn | Dòng phụ |
|---|---|---|
| CPU/GPU (`thermometer.medium`) | `Format.temperature(status?.temperature)` | `CPU 23%` |
| RAM (`memorychip`) | `11,2 GB` | `/ 16 GB · bình thường`; chữ "cao" màu cam, "nguy hiểm" màu đỏ |
| Ổ đĩa (`internaldrive`) | `182 GB` | `trống / 494 GB` |
| Mạng (`arrow.up.arrow.down`) | `↓ 1,2 MB/s` | `↑ 85 KB/s` |

Dưới lưới: các dòng `Quạt N` + `Format.rpm`. Cảnh báo quá nhiệt và `status.error` hiện như hiện tại.

**Khối dưới, tiêu đề nhỏ "Chế độ quạt":** ô bấm 2 cột (`LazyVGrid`) cho mọi preset (5 có sẵn + tùy chỉnh). Ô đang dùng tô `Color.accentColor`, chữ trắng đậm; ô khác nền xám nhạt. Bấm → `model.setMode(id)`.

**Chân:** `Cài đặt…` và `Thoát` như cũ.

**Trạng thái:**

- Lưới thẻ hệ thống **luôn hiện**.
- Chưa cài helper: thẻ CPU/GPU hiện `--°C`; thay dòng quạt + khối chế độ bằng khung "Chưa cài trình điều khiển quạt" + nút "Cài đặt helper" (như hiện tại).
- Mất kết nối helper: dòng lỗi đỏ + nút "Cài lại helper"; ẩn dòng quạt và khối chế độ.
- Đang kết nối (`status == nil`, chưa có lỗi): `ProgressView("Đang kết nối…")` ở vị trí dòng quạt + khối chế độ.
- `system == nil` (trước lần lấy mẫu đầu): các thẻ hiện `--`.

## Icon app

- Script `scripts/make-icon.swift` (chạy bằng `swift scripts/make-icon.swift <thư mục ra>`) vẽ bằng AppKit/CoreGraphics ảnh 1024×1024:
  - nền vuông bo góc kiểu macOS (bo ~22,5%, có lề trong suốt ~10% như icon chuẩn Big Sur+),
  - chuyển màu chéo xanh dương `#2F80ED` → xanh ngọc `#2BC0B4`,
  - hình quạt SF Symbol `fan.fill` màu trắng ở giữa (~55% cạnh), đổ bóng nhẹ.
- Script xuất đủ các cỡ của `AppIcon.iconset` (16…512 @1x/@2x); `iconutil -c icns` tạo `Resources/AppIcon.icns`, file này được commit.
- `Info.plist` thêm `CFBundleIconFile = AppIcon`; `Makefile` copy `AppIcon.icns` vào `Contents/Resources`.
- Sau khi vẽ, cho người dùng xem bản PNG để duyệt hoặc chỉnh màu/hình.

## Test

- **Unit test `SystemStats`** (hàm thuần, dữ liệu giả):
  - `CPUUsage.usage`: tính đúng %; Δtổng = 0 → `nil`.
  - Bộ nhớ đã dùng từ số trang mẫu; ánh xạ mức áp lực 1/2/4/khác.
  - `NetworkStats.rates`: cộng nhiều card; card mới bị bỏ qua; bộ đếm giảm bị bỏ qua; `elapsed <= 0` → `nil`.
  - `SystemSampler`: lần đầu CPU/mạng `nil`, lần hai có số (dùng nguồn giả qua protocol).
- **Unit test `Format`**: các ví dụ ở mục Định dạng.
- **Smoke test máy thật** (luôn chạy, chỉ đọc): CPU trong 0...100 ở lần đo thứ hai; `memoryUsed <= memoryTotal`; `diskFree <= diskTotal`; mạng ≥ 0.
- **Kiểm tra tay:** mở popover, so với Activity Monitor (CPU, Memory Used, áp lực) và Finder (dung lượng trống); tải một file lớn để thấy tốc độ mạng; xem icon trong Finder, Launchpad và DMG (app là LSUIElement nên không có icon Dock).
