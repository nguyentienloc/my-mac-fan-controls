# GPU % và chọn chế độ quạt dạng select — Thiết kế

Ngày: 2026-11-17

## Mục tiêu

1. Popover hiện **% sử dụng GPU** cạnh % CPU.
2. Khối chế độ quạt đổi từ lưới ô bấm 2 cột sang **một menu xổ xuống (select)** cho gọn.
3. Đóng gói bản **1.2** (ký + notarize).

**Ngoài phạm vi:** bộ nhớ GPU, nhiều GPU, đổi thanh menu.

## GPU %

- Nguồn: IOKit, dịch vụ `IOAccelerator`, thuộc tính `PerformanceStatistics` (từ điển), khóa `"Device Utilization %"` (số nguyên 0–100). Không cần root. Đây là số Activity Monitor hiển thị. Đã kiểm chứng trên M1 Pro (GPU 14 nhân): đọc ra 30.
- `SystemSource` thêm `gpuStatistics() -> [String: Any]?`: lấy từ điển `PerformanceStatistics` của `IOAccelerator` đầu tiên có thuộc tính này; `nil` nếu không có.
- Hàm thuần `GPUStats.utilization(from:) -> Double?`: lấy `"Device Utilization %"` dạng `NSNumber`, kẹp 0...100; thiếu khóa, sai kiểu hoặc không hữu hạn → `nil`.
- `SystemSnapshot` thêm `gpuPercent: Double?`. Không cần lần đo trước (khác CPU), nên có số ngay từ lần lấy mẫu đầu.
- Thẻ CPU/GPU: dòng phụ `CPU 23% · GPU 30%` (`Format.percent`, thiếu số → `--%`).

## Chế độ quạt dạng select

- Thay `SectionTitle("Chế độ quạt")` + `ModeGrid` bằng `ModePicker`: `Picker("Chế độ quạt", …)` kiểu `.menu` — nhãn bên trái, nút menu bên phải hiện tên chế độ đang dùng.
- Danh sách: 5 chế độ có sẵn, rồi (nếu có) đường kẻ ngăn và các preset tùy chỉnh.
- `selection` lấy từ `status.activePresetID`; chọn mục khác → `model.setMode(id)`.
- Các trạng thái chưa cài helper / mất kết nối / đang kết nối giữ nguyên như bản 1.1.

## Test

- Unit: `GPUStats.utilization` (đọc số, thiếu khóa, sai kiểu, kẹp > 100); `SystemSampler` trả `gpuPercent` từ nguồn giả và `nil` khi nguồn trả `nil`.
- Smoke máy thật: `gpuStatistics()` khác `nil`, `utilization` trong 0...100.
- Kiểm tra tay: mở popover, so % GPU với Activity Monitor (Window → GPU History); chọn chế độ qua menu và thấy quạt đổi.
