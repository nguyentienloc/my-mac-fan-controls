# GPU % + Mode Select Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hiện % GPU cạnh % CPU trong popover và đổi khối chế độ quạt sang menu xổ xuống; đóng gói bản 1.2.

**Architecture:** `SystemStats` thêm nguồn `gpuStatistics()` (IOKit `IOAccelerator` → `PerformanceStatistics`) và hàm thuần `GPUStats.utilization(from:)`; `SystemSnapshot` thêm `gpuPercent`. Popover đổi dòng phụ thẻ CPU/GPU và thay `ModeGrid` bằng `ModePicker` (`Picker` kiểu `.menu`).

**Tech Stack:** Swift 6.2 (Swift 5 mode), SwiftPM, swift-testing, IOKit, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-11-17-gpu-and-mode-select-design.md`

## Global Constraints

- macOS 14+, arm64; `swiftLanguageModes: [.v5]`; không dependency ngoài.
- Chuỗi hiển thị và comment bằng tiếng Việt, viết thẳng trong code.
- Daemon, protocol XPC, `Config`/`Status` không đổi.
- Thiếu số → `--%` (qua `Format.percent`).
- Mỗi commit kết thúc bằng dòng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (dùng `-m` thứ hai).

---

### Task 1: GPU % trong SystemStats

**Files:**
- Create: `Sources/SystemStats/GPU.swift`
- Modify: `Sources/SystemStats/Snapshot.swift`, `Sources/SystemStats/Sampler.swift`, `Sources/SystemStats/LiveSystemSource.swift`
- Test: `Tests/SystemStatsTests/CalculationTests.swift`, `Tests/SystemStatsTests/SamplerTests.swift`, `Tests/SystemStatsTests/LiveSourceTests.swift`

**Interfaces:**
- Consumes: `SystemSource`, `SystemSampler`, `SystemSnapshot`, `LiveSystemSource`, test helper `FakeSource` (đã có).
- Produces: `public enum GPUStats { static func utilization(from: [String: Any]) -> Double? }`; `SystemSource.gpuStatistics() -> [String: Any]?`; `SystemSnapshot.gpuPercent: Double?` (tham số init `gpuPercent:` ngay sau `cpuPercent:`).

- [ ] **Step 1: Viết test thất bại**

Thêm vào cuối struct `CalculationTests` (`Tests/SystemStatsTests/CalculationTests.swift`):
```swift
    @Test func gpuUtilizationReadsDeviceUtilization() {
        #expect(GPUStats.utilization(from: ["Device Utilization %": 30]) == 30)
    }

    @Test func gpuUtilizationIsNilWhenMissingOrWrongType() {
        #expect(GPUStats.utilization(from: [:]) == nil)
        #expect(GPUStats.utilization(from: ["Device Utilization %": "30"]) == nil)
    }

    @Test func gpuUtilizationIsClamped() {
        #expect(GPUStats.utilization(from: ["Device Utilization %": 150]) == 100)
        #expect(GPUStats.utilization(from: ["Device Utilization %": -5]) == 0)
    }
```

Trong `Tests/SystemStatsTests/SamplerTests.swift`, thêm vào `FakeSource` (sau dòng `var counters ...`):
```swift
    var gpu: [String: Any]? = ["Device Utilization %": 30]
```
và (sau `func interfaceCounters()`):
```swift
    func gpuStatistics() -> [String: Any]? { gpu }
```
Thêm vào cuối struct `SamplerTests`:
```swift
    @Test func gpuPercentAvailableOnFirstSample() {
        let sampler = SystemSampler(source: FakeSource())
        #expect(sampler.sample(now: start).gpuPercent == 30)
    }

    @Test func gpuPercentIsNilWhenSourceFails() {
        let source = FakeSource()
        source.gpu = nil
        #expect(SystemSampler(source: source).sample(now: start).gpuPercent == nil)
    }
```

Thêm vào cuối struct `LiveSourceTests` (`Tests/SystemStatsTests/LiveSourceTests.swift`):
```swift
    @Test func readsGPUUtilization() throws {
        let statistics = try #require(source.gpuStatistics())
        let percent = try #require(GPUStats.utilization(from: statistics))
        #expect((0...100).contains(percent))
    }
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter "CalculationTests|SamplerTests|LiveSourceTests"`
Expected: build lỗi (`GPUStats` chưa có, `FakeSource` có hàm không thuộc protocol / `gpuPercent` không tồn tại).

- [ ] **Step 3: Viết implementation**

`Sources/SystemStats/GPU.swift`:
```swift
import Foundation

public enum GPUStats {
    /// % GPU bận lấy từ từ điển `PerformanceStatistics` của IOAccelerator (khóa "Device Utilization %",
    /// cùng số Activity Monitor hiển thị). Kẹp 0...100; thiếu khóa hoặc sai kiểu → nil.
    public static func utilization(from statistics: [String: Any]) -> Double? {
        guard let number = statistics["Device Utilization %"] as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }
}
```

`Sources/SystemStats/Snapshot.swift`:
- Thêm thuộc tính ngay sau `public var cpuPercent: Double?`:
```swift
    public var gpuPercent: Double?          // 0...100
```
- Thêm tham số `gpuPercent: Double?,` ngay sau `cpuPercent: Double?,` trong `public init(...)`, và `self.gpuPercent = gpuPercent` ngay sau `self.cpuPercent = cpuPercent`.

`Sources/SystemStats/Sampler.swift`:
- Thêm vào protocol `SystemSource` (sau `func interfaceCounters()`):
```swift
    func gpuStatistics() -> [String: Any]?
```
- Trong `sample(now:)`, ở lời gọi `SystemSnapshot(`, thêm ngay sau dòng `cpuPercent: cpuPercent,`:
```swift
            gpuPercent: source.gpuStatistics().flatMap(GPUStats.utilization),
```

`Sources/SystemStats/LiveSystemSource.swift`:
- Thêm `import IOKit` cạnh các import hiện có.
- Thêm phương thức vào class `LiveSystemSource` (sau `interfaceCounters()`):
```swift
    /// Từ điển `PerformanceStatistics` của IOAccelerator đầu tiên có thuộc tính này
    /// (Apple Silicon có một GPU tích hợp). Không cần quyền root.
    public func gpuStatistics() -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let statistics = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                return statistics
            }
        }
        return nil
    }
```

- [ ] **Step 4: Chạy test để xác nhận đạt**

Run: `swift test --filter "CalculationTests|SamplerTests|LiveSourceTests"` rồi `swift test`
Expected: toàn bộ pass, không warning.

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemStats Tests/SystemStatsTests
git commit -m "feat: read GPU utilization from IOAccelerator" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Popover — GPU % và chọn chế độ dạng menu

**Files:**
- Modify: `Sources/FanControlApp/SystemTiles.swift`, `Sources/FanControlApp/PopoverView.swift`

**Interfaces:**
- Consumes: `SystemSnapshot.gpuPercent` (Task 1), `Format.percent`, `Status.presets`, `Status.activePresetID`, `Preset.isBuiltIn`, `AppModel.setMode(_:)`.
- Produces: `private struct ModePicker: View` thay `ModeGrid`.

Không có unit test (view). Kiểm chứng bằng build không warning, test xanh, chạy app.

- [ ] **Step 1: Dòng phụ thẻ CPU/GPU**

Trong `Sources/FanControlApp/SystemTiles.swift`, thay dòng:
```swift
                Text("CPU \(Format.percent(system?.cpuPercent))")
```
bằng:
```swift
                Text("CPU \(Format.percent(system?.cpuPercent)) · GPU \(Format.percent(system?.gpuPercent))")
```

- [ ] **Step 2: Thay `ModeGrid` bằng `ModePicker`**

Trong `Sources/FanControlApp/PopoverView.swift`, thay hai dòng:
```swift
                SectionTitle("Chế độ quạt")
                ModeGrid(status: status)
```
bằng:
```swift
                ModePicker(status: status)
```

Thay toàn bộ struct `ModeGrid` (kèm comment `/// Ô chọn nhanh chế độ, 2 cột; ô đang dùng tô màu nhấn.` phía trên) bằng:
```swift
/// Chọn nhanh chế độ quạt bằng menu xổ xuống: chế độ có sẵn, rồi các preset tùy chỉnh.
private struct ModePicker: View {
    @Environment(AppModel.self) private var model
    let status: Status

    var body: some View {
        Picker("Chế độ quạt", selection: Binding(
            get: { status.activePresetID },
            set: { id in Task { await model.setMode(id) } })) {
            ForEach(status.presets.filter(\.isBuiltIn)) { preset in
                Text(preset.name).tag(preset.id)
            }
            let custom = status.presets.filter { !$0.isBuiltIn }
            if !custom.isEmpty {
                Divider()
                ForEach(custom) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
        }
        .pickerStyle(.menu)
    }
}
```

- [ ] **Step 3: Build và kiểm chứng**

Run: `swift build 2>&1 | grep -E "warning|error"; swift test 2>&1 | tail -1`
Expected: không dòng warning/error; toàn bộ test pass.

Run: `make install && (pkill -x FanControl; perl -e 'select(undef,undef,undef,1.5)'; open /Applications/FanControl.app) && perl -e 'select(undef,undef,undef,2)' && pgrep -x FanControl`
Expected: in PID (nếu `open` báo -600, chạy lại `open /Applications/FanControl.app`).

- [ ] **Step 4: Commit**

```bash
git add Sources/FanControlApp/SystemTiles.swift Sources/FanControlApp/PopoverView.swift
git commit -m "feat: show GPU usage and switch fan mode via menu picker" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Bản 1.2

**Files:**
- Modify: `Resources/Info.plist`, `README.md`

- [ ] **Step 1:** `/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.2' -c 'Set :CFBundleVersion 3' Resources/Info.plist`
- [ ] **Step 2:** Trong `README.md`, đổi `Popover còn hiện nhanh CPU %, RAM` thành `Popover còn hiện nhanh CPU % và GPU %, RAM`.
- [ ] **Step 3:** `swift test` (toàn bộ pass) rồi `make notarize` (Accepted, staple OK, `source=Notarized Developer ID`).
- [ ] **Step 4:** Commit:
```bash
git add Resources/Info.plist README.md
git commit -m "chore: bump version to 1.2" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
