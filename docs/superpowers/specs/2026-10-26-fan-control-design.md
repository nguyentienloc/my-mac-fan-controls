# Fan Control — Thiết kế

Ngày: 2026-10-26

## Mục tiêu

App menu bar cho macOS tự điều chỉnh tốc độ quạt theo nhiệt độ CPU/GPU, thay cho Macs Fan Control (hiện chỉ dùng được chế độ full blast). Chỉ dùng cá nhân trên máy của người dùng, build từ source, không cần Apple Developer account.

**Máy mục tiêu:** MacBook Pro M1 Pro (MacBookPro18,3), macOS 15.6.1.

**Ngoài phạm vi:** hỗ trợ máy Mac khác (Intel, M3/M4 với key `Ftst`), ký Developer ID / notarize, đa ngôn ngữ, đường cong riêng cho từng quạt, chọn cảm biến tùy ý.

## Kết quả khảo sát phần cứng (đọc SMC, không cần root)

- `FNum` = 2 quạt.
- Quạt 0: `F0Mn` 1200, `F0Mx` 5779 RPM. Quạt 1: `F1Mn` 1200, `F1Mx` 6241 RPM.
- Kiểu dữ liệu: `FxAc`/`FxMn`/`FxMx`/`FxTg` là `flt ` (float32 little-endian), `FxMd` là `ui8 `.
- Không có key `Ftst` → chỉ cần `FxMd=1` rồi ghi `FxTg` để điều khiển.
- Cảm biến nhiệt (`flt `): CPU P-core `Tp*`, E-core `Te*`, GPU `Tg*` (khoảng 37 key). Danh sách được tìm động khi khởi động bằng cách duyệt `#KEY`.
- Lưu ý khi dùng IOKit từ Swift: struct `SMCKeyData` phải có padding tường minh sau `keyInfo` (`UInt32, UInt32, UInt8` + 3 byte đệm) để khớp layout C 80 byte. Thiếu padding thì mọi lệnh gọi đều thất bại.

## Kiến trúc

Swift Package gồm 4 target:

| Target | Loại | Vai trò |
|---|---|---|
| `FanCore` | library | SMC, cảm biến, đường cong, vòng điều khiển. Không phụ thuộc UI/XPC, test được bằng mock. |
| `Shared` | library | Model `Config`, `Preset`, `CurvePoint`, `Status` (Codable) và protocol XPC. |
| `fanctld` | executable | Daemon chạy root qua launchd. Chạy `Controller` mỗi 2 giây, phục vụ XPC, lưu cấu hình. |
| `FanControlApp` | executable | App menu bar SwiftUI, chạy quyền user. |

`Makefile` build release và đóng gói `FanControl.app` với `fanctld` cùng file plist launchd nằm trong `Contents/Resources`, ký ad-hoc (`codesign -s -`).

### Luồng dữ liệu

```
FanControlApp ──XPC──▶ fanctld (root, launchd) ──IOKit──▶ AppleSMC
     ▲  setMode / savePreset      │  mỗi 2s: đọc nhiệt độ → tính RPM → ghi FxTg
     └──── getStatus (poll 2s) ───┘
```

### Thành phần FanCore

- `SMCDevice` (protocol): `readKey`, `writeKey`, `allKeys`. `AppleSMC` là bản thật dùng IOKit (selector 2, lệnh đọc info 9, đọc 5, ghi 6, đọc key theo index 8). `MockSMC` dùng trong test.
- `FanService`: đọc số quạt và min/max; `setManual(fan, rpm)` ghi `FxMd=1` + `FxTg`; `setAuto(fan)` ghi `FxMd=0`.
- `SensorService`: khi khởi động, tìm các key `Tp*`, `Te*`, `Tg*` có kiểu `flt `; `readMaxTemperature()` trả về max của các giá trị hợp lệ (0–130°C). Trả lỗi nếu không có giá trị hợp lệ nào.
- `FanCurve`: danh sách `CurvePoint(temp: Double, percent: Double)`. Hàm `percent(at:)` trả về `nil` khi dưới điểm đầu (nghĩa là Apple Auto), nội suy tuyến tính giữa hai điểm, giữ % điểm cuối khi vượt điểm cuối. Hàm `validate()`: ít nhất 2 điểm, nhiệt độ tăng ngặt, % không giảm, nhiệt độ trong 20–110°C, % trong 0–100.
- `Controller`: máy trạng thái thuần, nhận nhiệt độ đọc được và mode, trả về lệnh cho từng quạt (`.auto` hoặc `.manual(rpm)`). Phần I/O nằm ngoài để dễ test.

### Daemon `fanctld`

- Cài vào `/Library/PrivilegedHelperTools/fanctld`, plist `/Library/LaunchDaemons/local.fancontrol.daemon.plist` với `RunAtLoad`, `KeepAlive`, `MachServices: local.fancontrol.daemon`.
- Cấu hình lưu ở `/Library/Application Support/FanControl/config.json`. Nếu file hỏng hoặc thiếu thì dùng mặc định (mode Cân bằng) và ghi đè lại.
- XPC (`NSXPCConnection`, mach service): `getStatus`, `setMode(presetID)`, `savePreset(preset)`, `deletePreset(id)`. Daemon validate mọi đầu vào và từ chối đường cong không hợp lệ hoặc thao tác xóa/sửa preset có sẵn.
- Cờ `--dry-run`: chỉ log lệnh, không ghi SMC.
- Bắt SIGTERM/SIGINT: trả mọi quạt về Auto rồi thoát. Khi khởi động: trả mọi quạt về Auto trước, sau đó mới bắt đầu vòng điều khiển.
- Lắng nghe sự kiện wake (`IORegisterForSystemPower`): sau khi máy thức dậy, buộc ghi lại toàn bộ lệnh ở chu kỳ kế tiếp.

## Đường cong và preset

`%` quy đổi theo từng quạt: `rpm = min + percent/100 × (max − min)`. Cả hai quạt dùng chung một đường cong.

| ID | Tên hiển thị | Hành vi |
|---|---|---|
| `auto` | Apple tự động | Daemon không can thiệp (`FxMd=0`) |
| `silent` | Êm | 65°C→0%, 75°C→30%, 85°C→60%, 92°C→100% |
| `balanced` | Cân bằng *(mặc định)* | 55°C→0%, 65°C→35%, 75°C→65%, 85°C→100% |
| `performance` | Hiệu năng | 45°C→20%, 60°C→50%, 70°C→80%, 78°C→100% |
| `max` | Tối đa | Luôn 100% |
| UUID | Tên người dùng đặt | Đường cong tùy chỉnh, không giới hạn số lượng |

Preset có sẵn là chỉ đọc. Muốn chỉnh thì bấm "Nhân bản" để tạo bản tùy chỉnh rồi sửa bản đó.

## Vòng điều khiển (mỗi 2 giây)

1. Đọc nhiệt độ max (CPU + GPU). Lỗi đọc → tăng bộ đếm lỗi; 3 lần liên tiếp → mọi quạt về Auto, `Status.error` được đặt. Đọc thành công lần sau thì xóa lỗi.
2. Làm mượt bằng EMA với α = 0.3 (khoảng 6 giây). Riêng ngưỡng an toàn dùng giá trị thô chưa làm mượt.
3. **Ngưỡng an toàn:** nhiệt độ thô ≥ 95°C → mọi quạt 100%, bất kể mode nào (kể cả Apple tự động). Thoát khỏi chế độ an toàn khi nhiệt độ < 90°C.
4. Tính `percent(at: smoothed)`.
   - Kết quả `nil` (dưới điểm đầu): nếu đang manual thì chỉ trả về Auto khi `smoothed < điểm đầu − 3°C` (hysteresis); trong khoảng giữa thì giữ mức 0% của đường cong.
5. Đổi % sang RPM mục tiêu cho từng quạt, kẹp trong `[min, max]`.
6. **Tăng ngay, giảm từ từ:** RPM mới cao hơn thì áp dụng ngay; thấp hơn thì giảm tối đa 300 RPM mỗi chu kỳ.
7. Chỉ ghi SMC khi RPM thay đổi > 50 RPM so với lần ghi trước, khi chuyển giữa Auto và manual, hoặc ngay sau khi máy thức dậy.

**Cần kiểm chứng khi implement:** ghi `FxMd=0` có thực sự trả quyền cho Apple (quạt về 0 RPM khi mát) trên M1 Pro hay không. Nếu không được, "Auto" sẽ được thay bằng giữ quạt ở mức min, và thực tế này sẽ được ghi lại vào spec.

## Giao diện (toàn bộ tiếng Việt)

Chuỗi hiển thị viết trực tiếp bằng tiếng Việt trong code, không dùng hệ thống localization.

**Thanh menu:** icon `fan` (SF Symbol) + nhiệt độ, ví dụ `58°`. Chữ đỏ khi đang ở chế độ an toàn, daemon báo lỗi, hoặc không kết nối được daemon.

**Popover:**

- Dòng `Nhiệt độ CPU/GPU: 58°C`.
- Mỗi quạt một dòng: `Quạt 1: 2.450 vòng/phút` kèm thanh tiến độ.
- Danh sách chọn mode: Apple tự động, Êm, Cân bằng, Hiệu năng, Tối đa, và các preset tùy chỉnh.
- Nút `Cài đặt…` và `Thoát`.
- Chưa cài helper: thay toàn bộ phần trên bằng thông báo "Chưa cài trình điều khiển quạt" và nút `Cài đặt helper`.

**Cửa sổ Cài đặt**, 2 tab:

- **Đường cong:** danh sách preset bên trái. Bên phải là biểu đồ Swift Charts (trục X: nhiệt độ °C, trục Y: % tốc độ), kéo thả được các điểm, có đường dọc đánh dấu nhiệt độ hiện tại, kèm bảng nhập số chính xác. Các nút `Nhân bản`, `Đổi tên`, `Xóa`, `Thêm điểm`, `Xóa điểm`, `Lưu`. Preset có sẵn hiển thị ở chế độ chỉ đọc. Đường cong không hợp lệ thì vô hiệu nút Lưu và hiện lý do.
- **Chung:** trạng thái helper (Đã cài / Chưa cài / Lỗi kết nối), nút `Cài đặt helper` / `Gỡ helper`, công tắc `Mở khi đăng nhập` (`SMAppService.mainApp`).

**Cài helper:** app chạy `osascript` với `do shell script … with administrator privileges` để copy `fanctld` và plist vào đúng chỗ rồi `launchctl bootstrap system`. **Gỡ helper:** `launchctl bootout system/local.fancontrol.daemon` (daemon nhận SIGTERM và trả quạt về Auto), sau đó xóa các file đã cài.

`Thoát` chỉ tắt app; daemon vẫn tiếp tục điều khiển quạt.

## Xử lý lỗi

| Tình huống | Hành vi |
|---|---|
| Không mở được AppleSMC | Daemon log lỗi và thoát với mã ≠ 0; launchd khởi động lại sau 10 giây (`ThrottleInterval`) |
| Đọc cảm biến lỗi 3 lần liên tiếp | Mọi quạt về Auto, UI hiện lỗi |
| Ghi SMC lỗi | Log, thử lại ở chu kỳ sau; 3 lần liên tiếp thì về Auto và báo lỗi |
| App không kết nối được daemon | Thanh menu đỏ, popover hiện "Không kết nối được helper" kèm nút cài lại |
| Config hỏng | Dùng mặc định và ghi đè |
| Macs Fan Control cũng đang chạy | Không tự phát hiện; README hướng dẫn thoát Macs Fan Control |

## Test

- **Unit test `FanCore`** (`swift test`) với `MockSMC`:
  - `FanCurve`: nội suy, dưới điểm đầu, trên điểm cuối, `validate()` cho từng luật.
  - Ánh xạ % sang RPM theo min/max riêng của từng quạt, kẹp giá trị.
  - `Controller`: hysteresis về Auto, tăng ngay/giảm 300 RPM, ngưỡng ghi 50 RPM, ngưỡng an toàn 95°C/90°C (kể cả ở mode Apple tự động), 3 lỗi đọc thì về Auto, mode Tối đa, ghi lại sau khi thức dậy.
  - `SensorService`: lọc giá trị ngoài 0–130°C, lỗi khi không có giá trị hợp lệ.
  - Encode/decode `Config`, config hỏng thì về mặc định.
- **Kiểm tra trên máy thật:**
  1. `fanctld --dry-run` chạy dưới sudo, xem log RPM dự kiến.
  2. Cài helper thật, tạo tải (`yes > /dev/null` × số core) rồi quan sát quạt tăng; dừng tải và quan sát quạt giảm từ từ rồi về Auto.
  3. `launchctl bootout` daemon → xác nhận `F0Md`/`F1Md` = 0.
  4. Sleep/wake máy → xác nhận quạt vẫn theo đường cong.
