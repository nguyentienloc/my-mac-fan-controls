# System Stats + App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Popover của FanControl hiện thêm CPU %, RAM, ổ đĩa, tốc độ mạng theo bố cục "A" (lưới thẻ 2×2 phía trên, ô chọn chế độ 2 cột phía dưới), và app có icon riêng.

**Architecture:** Thêm library target `SystemStats` (Swift thuần, test được). Các hàm tính toán là hàm thuần; `LiveSystemSource` đọc Mach/sysctl/URL; `SystemSampler` gom lại thành `SystemSnapshot`. App lấy mẫu mỗi 2 giây trong vòng poll sẵn có của `AppModel`. Daemon không đổi. Icon được vẽ bằng script Swift/AppKit, xuất `.icns` bằng `iconutil`.

**Tech Stack:** Swift 6.2 toolchain (Swift 5 language mode), SwiftPM, swift-testing, Darwin (Mach `host_statistics`, sysctl), SwiftUI, AppKit.

**Spec:** `docs/superpowers/specs/2026-10-27-system-stats-design.md`

## Global Constraints

- Nền tảng `macOS 14+`, arm64; `swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]`; không dependency ngoài.
- Mọi chuỗi hiển thị và comment bằng **tiếng Việt**, viết thẳng trong code.
- Daemon `fanctld`, protocol XPC, `Config`/`Status` **không đổi**.
- Định dạng số: dấu phẩy thập phân; RAM hệ 1024 ("11,2 GB"), ổ đĩa hệ 1000 ("182 GB", "1,2 TB"), mạng hệ 1000 ("850 B/s", "85 KB/s", "1,2 MB/s"), phần trăm "23%"; thiếu số → "--" (mạng), "--%" (phần trăm), "--" (thẻ).
- Mạng chỉ đếm card có tên bắt đầu `en`, đang UP, không loopback.
- Áp lực bộ nhớ: sysctl `kern.memorystatus_vm_pressure_level` 2 → "cao" (cam), 4 → "nguy hiểm" (đỏ), khác → "bình thường".
- Thanh menu giữ nguyên (icon quạt + nhiệt độ).
- Icon: nền bo góc 22,5%, lề 10%, chuyển màu `#2F80ED` → `#2BC0B4` góc −45°, SF Symbol `fan.fill` trắng cỡ 40% cạnh, đổ bóng nhẹ.
- Ký app: `make app` ký Developer ID như hiện tại (không đổi Makefile phần ký).
- Mỗi commit kết thúc bằng dòng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (dùng `-m` thứ hai).

---

## File Structure

```
Package.swift                                   # + target SystemStats, test target, app phụ thuộc SystemStats
Sources/SystemStats/
  Snapshot.swift        # MemoryPressure, SystemSnapshot
  CPU.swift             # CPUTicks, CPUUsage.usage(from:to:)
  Memory.swift          # MemoryCounts.usedBytes(pageSize:)
  Network.swift         # InterfaceCounters, NetworkRates, NetworkStats.rates / isCounted
  Sampler.swift         # protocol SystemSource, SystemSampler
  LiveSystemSource.swift# đọc hệ thống thật
Sources/Shared/Format.swift                     # + memory, disk, rate, percent, decimal
Sources/FanControlApp/
  AppModel.swift        # + system, sampler
  PopoverView.swift     # viết lại theo bố cục A
  SystemTiles.swift     # SectionTitle, StatTile, SystemTiles
scripts/make-icon.swift                         # vẽ AppIcon.iconset
Resources/AppIcon.icns                          # icon đã xuất (commit)
Resources/Info.plist                            # + CFBundleIconFile
Makefile                                        # + target icon, copy AppIcon.icns
Tests/SystemStatsTests/
  CalculationTests.swift
  SamplerTests.swift
  LiveSourceTests.swift
Tests/SharedTests/FormatTests.swift             # + test định dạng mới
```

---

### Task 1: SystemStats — kiểu dữ liệu, hàm tính thuần, SystemSampler

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SystemStats/Snapshot.swift`, `Sources/SystemStats/CPU.swift`, `Sources/SystemStats/Memory.swift`, `Sources/SystemStats/Network.swift`, `Sources/SystemStats/Sampler.swift`
- Test: `Tests/SystemStatsTests/CalculationTests.swift`, `Tests/SystemStatsTests/SamplerTests.swift`

**Interfaces:**
- Consumes: không có.
- Produces:
  - `public enum MemoryPressure: Equatable, Sendable { case normal, warning, critical; init(sysctlLevel: Int32) }`
  - `public struct SystemSnapshot: Equatable, Sendable { cpuPercent: Double?; memoryUsed: UInt64; memoryTotal: UInt64; memoryPressure: MemoryPressure; diskFree: UInt64?; diskTotal: UInt64?; downloadBytesPerSecond: Double?; uploadBytesPerSecond: Double? }` (memberwise `public init` đủ tham số theo thứ tự trên)
  - `public struct CPUTicks: Equatable, Sendable { user, system, idle, nice: UInt64 }`; `public enum CPUUsage { static func usage(from: CPUTicks, to: CPUTicks) -> Double? }`
  - `public struct MemoryCounts: Equatable, Sendable { internalPages, purgeablePages, wiredPages, compressedPages: UInt64; func usedBytes(pageSize: UInt64) -> UInt64 }`
  - `public struct InterfaceCounters: Equatable, Sendable { received, sent: UInt64 }`; `public struct NetworkRates: Equatable, Sendable { download, upload: Double }`; `public enum NetworkStats { static func rates(from:to:elapsed:) -> NetworkRates?; static func isCounted(name: String) -> Bool }`
  - `public protocol SystemSource { cpuTicks() -> CPUTicks?; memoryCounts() -> MemoryCounts?; pageSize() -> UInt64; physicalMemory() -> UInt64; memoryPressureLevel() -> Int32; diskCapacity() -> (free: UInt64, total: UInt64)?; interfaceCounters() -> [String: InterfaceCounters] }`
  - `public final class SystemSampler { init(source: SystemSource); func sample(now: Date) -> SystemSnapshot }`

- [ ] **Step 1: Thêm target vào `Package.swift`**

Thay toàn bộ `Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .target(name: "FanCore", dependencies: ["Shared"]),
        .target(name: "SystemStats"),
        .executableTarget(name: "fanctld", dependencies: ["FanCore", "Shared"]),
        .executableTarget(name: "FanControlApp", dependencies: ["Shared", "SystemStats"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore", "Shared"]),
        .testTarget(name: "SystemStatsTests", dependencies: ["SystemStats"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Viết test thất bại**

`Tests/SystemStatsTests/CalculationTests.swift`:
```swift
import Testing
@testable import SystemStats

struct CalculationTests {
    @Test func cpuUsageFromTickDeltas() {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let new = CPUTicks(user: 130, system: 60, idle: 850, nice: 60)
        // bận = 30 + 10 + 10 = 50, tổng = 50 + 50 = 100
        #expect(CPUUsage.usage(from: old, to: new) == 50)
    }

    @Test func cpuUsageIsNilWithoutElapsedTicks() {
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        #expect(CPUUsage.usage(from: ticks, to: ticks) == nil)
    }

    @Test func cpuUsageIsNilWhenCountersGoBackwards() {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let new = CPUTicks(user: 90, system: 60, idle: 850, nice: 60)
        #expect(CPUUsage.usage(from: old, to: new) == nil)
    }

    @Test func memoryUsedMatchesActivityMonitorFormula() {
        let counts = MemoryCounts(internalPages: 500, purgeablePages: 100, wiredPages: 200, compressedPages: 50)
        // (500 − 100 + 200 + 50) × 16384
        #expect(counts.usedBytes(pageSize: 16384) == 650 * 16384)
    }

    @Test func memoryUsedNeverUnderflows() {
        let counts = MemoryCounts(internalPages: 10, purgeablePages: 20, wiredPages: 5, compressedPages: 0)
        #expect(counts.usedBytes(pageSize: 1) == 5)
    }

    @Test func memoryPressureMapping() {
        #expect(MemoryPressure(sysctlLevel: 1) == .normal)
        #expect(MemoryPressure(sysctlLevel: 2) == .warning)
        #expect(MemoryPressure(sysctlLevel: 4) == .critical)
        #expect(MemoryPressure(sysctlLevel: 0) == .normal)
    }

    @Test func networkRatesSumInterfaces() {
        let old = ["en0": InterfaceCounters(received: 1000, sent: 500), "en1": InterfaceCounters(received: 0, sent: 0)]
        let new = ["en0": InterfaceCounters(received: 3000, sent: 900), "en1": InterfaceCounters(received: 1000, sent: 100)]
        #expect(NetworkStats.rates(from: old, to: new, elapsed: 2) == NetworkRates(download: 1500, upload: 250))
    }

    @Test func networkRatesSkipNewAndResetInterfaces() {
        let old = ["en0": InterfaceCounters(received: 5000, sent: 5000)]
        let new = [
            "en0": InterfaceCounters(received: 100, sent: 100),       // bộ đếm giảm → bỏ qua
            "en5": InterfaceCounters(received: 9000, sent: 9000),     // card mới → bỏ qua
        ]
        #expect(NetworkStats.rates(from: old, to: new, elapsed: 1) == NetworkRates(download: 0, upload: 0))
    }

    @Test func networkRatesNeedPositiveElapsed() {
        #expect(NetworkStats.rates(from: [:], to: [:], elapsed: 0) == nil)
    }

    @Test func onlyPhysicalInterfacesAreCounted() {
        #expect(NetworkStats.isCounted(name: "en0"))
        #expect(NetworkStats.isCounted(name: "en7"))
        #expect(!NetworkStats.isCounted(name: "utun3"))
        #expect(!NetworkStats.isCounted(name: "bridge0"))
        #expect(!NetworkStats.isCounted(name: "awdl0"))
        #expect(!NetworkStats.isCounted(name: "lo0"))
    }
}
```

`Tests/SystemStatsTests/SamplerTests.swift`:
```swift
import Foundation
import Testing
@testable import SystemStats

/// Nguồn giả: trả các giá trị được gán sẵn.
final class FakeSource: SystemSource {
    var ticks: CPUTicks? = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
    var counts: MemoryCounts? = MemoryCounts(internalPages: 100, purgeablePages: 0, wiredPages: 0, compressedPages: 0)
    var pressureLevel: Int32 = 1
    var disk: (free: UInt64, total: UInt64)? = (free: 100, total: 500)
    var counters: [String: InterfaceCounters] = ["en0": InterfaceCounters(received: 0, sent: 0)]

    func cpuTicks() -> CPUTicks? { ticks }
    func memoryCounts() -> MemoryCounts? { counts }
    func pageSize() -> UInt64 { 1024 }
    func physicalMemory() -> UInt64 { 1_048_576 }
    func memoryPressureLevel() -> Int32 { pressureLevel }
    func diskCapacity() -> (free: UInt64, total: UInt64)? { disk }
    func interfaceCounters() -> [String: InterfaceCounters] { counters }
}

struct SamplerTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func firstSampleHasNoRates() {
        let sampler = SystemSampler(source: FakeSource())
        let snapshot = sampler.sample(now: start)
        #expect(snapshot.cpuPercent == nil)
        #expect(snapshot.downloadBytesPerSecond == nil)
        #expect(snapshot.uploadBytesPerSecond == nil)
        #expect(snapshot.memoryUsed == 102_400)
        #expect(snapshot.memoryTotal == 1_048_576)
        #expect(snapshot.memoryPressure == .normal)
        #expect(snapshot.diskFree == 100)
        #expect(snapshot.diskTotal == 500)
    }

    @Test func secondSampleComputesCPUAndNetwork() {
        let source = FakeSource()
        let sampler = SystemSampler(source: source)
        _ = sampler.sample(now: start)
        source.ticks = CPUTicks(user: 25, system: 0, idle: 75, nice: 0)
        source.counters = ["en0": InterfaceCounters(received: 4000, sent: 1000)]
        let snapshot = sampler.sample(now: start.addingTimeInterval(2))
        #expect(snapshot.cpuPercent == 25)
        #expect(snapshot.downloadBytesPerSecond == 2000)
        #expect(snapshot.uploadBytesPerSecond == 500)
    }

    @Test func failedSourcesBecomeNilOrZero() {
        let source = FakeSource()
        source.ticks = nil
        source.counts = nil
        source.disk = nil
        source.pressureLevel = 4
        let sampler = SystemSampler(source: source)
        _ = sampler.sample(now: start)
        let snapshot = sampler.sample(now: start.addingTimeInterval(2))
        #expect(snapshot.cpuPercent == nil)
        #expect(snapshot.memoryUsed == 0)
        #expect(snapshot.diskFree == nil)
        #expect(snapshot.diskTotal == nil)
        #expect(snapshot.memoryPressure == .critical)
    }
}
```

- [ ] **Step 3: Chạy test để xác nhận thất bại**

Run: `swift test --filter "CalculationTests|SamplerTests"`
Expected: build lỗi (target `SystemStats` chưa có source / không tìm thấy `CPUTicks`).

- [ ] **Step 4: Viết implementation**

`Sources/SystemStats/Snapshot.swift`:
```swift
import Foundation

public enum MemoryPressure: Equatable, Sendable {
    case normal
    case warning
    case critical

    /// Giá trị sysctl `kern.memorystatus_vm_pressure_level`: 1 bình thường, 2 cao, 4 nguy hiểm.
    public init(sysctlLevel: Int32) {
        switch sysctlLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }
}

/// Một lần lấy mẫu số liệu hệ thống. `nil` nghĩa là chưa có (lần đo đầu) hoặc đọc lỗi.
public struct SystemSnapshot: Equatable, Sendable {
    public var cpuPercent: Double?
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var memoryPressure: MemoryPressure
    public var diskFree: UInt64?
    public var diskTotal: UInt64?
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?

    public init(cpuPercent: Double?, memoryUsed: UInt64, memoryTotal: UInt64, memoryPressure: MemoryPressure,
                diskFree: UInt64?, diskTotal: UInt64?, downloadBytesPerSecond: Double?, uploadBytesPerSecond: Double?) {
        self.cpuPercent = cpuPercent
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.memoryPressure = memoryPressure
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}
```

`Sources/SystemStats/CPU.swift`:
```swift
import Foundation

/// Tổng tick CPU tích lũy từ lúc khởi động (mọi nhân).
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUUsage {
    /// % CPU bận giữa hai lần đọc. `nil` khi không có tick nào trôi qua hoặc bộ đếm bị reset.
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.user >= old.user, new.system >= old.system, new.idle >= old.idle, new.nice >= old.nice else {
            return nil
        }
        let busy = Double((new.user - old.user) + (new.system - old.system) + (new.nice - old.nice))
        let total = busy + Double(new.idle - old.idle)
        guard total > 0 else { return nil }
        return busy / total * 100
    }
}
```

`Sources/SystemStats/Memory.swift`:
```swift
import Foundation

/// Số trang bộ nhớ lấy từ `vm_statistics64`.
public struct MemoryCounts: Equatable, Sendable {
    public var internalPages: UInt64
    public var purgeablePages: UInt64
    public var wiredPages: UInt64
    public var compressedPages: UInt64

    public init(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64) {
        self.internalPages = internalPages
        self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
    }

    /// "Memory Used" như Activity Monitor: bộ nhớ app (internal − purgeable) + wired + compressed.
    public func usedBytes(pageSize: UInt64) -> UInt64 {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return (appPages + wiredPages + compressedPages) * pageSize
    }
}
```

`Sources/SystemStats/Network.swift`:
```swift
import Foundation

/// Bộ đếm byte tích lũy của một card mạng.
public struct InterfaceCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public struct NetworkRates: Equatable, Sendable {
    public var download: Double
    public var upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }
}

public enum NetworkStats {
    /// Tốc độ (byte/giây) giữa hai lần đọc. Card mới xuất hiện hoặc có bộ đếm giảm (reset) thì bỏ qua card đó.
    public static func rates(from old: [String: InterfaceCounters], to new: [String: InterfaceCounters],
                             elapsed: TimeInterval) -> NetworkRates? {
        guard elapsed > 0 else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, current) in new {
            guard let previous = old[name], current.received >= previous.received, current.sent >= previous.sent else {
                continue
            }
            received += current.received - previous.received
            sent += current.sent - previous.sent
        }
        return NetworkRates(download: Double(received) / elapsed, upload: Double(sent) / elapsed)
    }

    /// Chỉ đếm card vật lý Wi-Fi/Ethernet (`en*`): lưu lượng của utun (VPN), bridge, awdl đi chồng qua `en*`.
    public static func isCounted(name: String) -> Bool {
        name.hasPrefix("en")
    }
}
```

`Sources/SystemStats/Sampler.swift`:
```swift
import Foundation

/// Nguồn số liệu thô. `LiveSystemSource` đọc hệ thống thật; test dùng bản giả.
public protocol SystemSource {
    func cpuTicks() -> CPUTicks?
    func memoryCounts() -> MemoryCounts?
    func pageSize() -> UInt64
    func physicalMemory() -> UInt64
    func memoryPressureLevel() -> Int32
    func diskCapacity() -> (free: UInt64, total: UInt64)?
    func interfaceCounters() -> [String: InterfaceCounters]
}

/// Lấy mẫu định kỳ; giữ lần đọc CPU và mạng trước đó để tính % và tốc độ.
public final class SystemSampler {
    private let source: SystemSource
    private var lastTicks: CPUTicks?
    private var lastNetwork: (counters: [String: InterfaceCounters], time: Date)?

    public init(source: SystemSource) {
        self.source = source
    }

    public func sample(now: Date) -> SystemSnapshot {
        let ticks = source.cpuTicks()
        var cpuPercent: Double?
        if let previous = lastTicks, let ticks {
            cpuPercent = CPUUsage.usage(from: previous, to: ticks)
        }
        lastTicks = ticks

        let counters = source.interfaceCounters()
        var rates: NetworkRates?
        if let last = lastNetwork {
            rates = NetworkStats.rates(from: last.counters, to: counters, elapsed: now.timeIntervalSince(last.time))
        }
        lastNetwork = (counters, now)

        let disk = source.diskCapacity()
        return SystemSnapshot(
            cpuPercent: cpuPercent,
            memoryUsed: source.memoryCounts()?.usedBytes(pageSize: source.pageSize()) ?? 0,
            memoryTotal: source.physicalMemory(),
            memoryPressure: MemoryPressure(sysctlLevel: source.memoryPressureLevel()),
            diskFree: disk?.free,
            diskTotal: disk?.total,
            downloadBytesPerSecond: rates?.download,
            uploadBytesPerSecond: rates?.upload)
    }
}
```

- [ ] **Step 5: Chạy test để xác nhận đạt**

Run: `swift test --filter "CalculationTests|SamplerTests"`
Expected: 13 test pass.

Run: `swift test`
Expected: toàn bộ pass, không warning.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SystemStats Tests/SystemStatsTests
git commit -m "feat: add SystemStats calculations and sampler" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: LiveSystemSource — đọc hệ thống thật

**Files:**
- Create: `Sources/SystemStats/LiveSystemSource.swift`
- Modify: `Sources/SystemStats/Sampler.swift` (thêm `convenience init()`)
- Test: `Tests/SystemStatsTests/LiveSourceTests.swift`

**Interfaces:**
- Consumes: `SystemSource`, `CPUTicks`, `MemoryCounts`, `InterfaceCounters`, `NetworkStats.isCounted`, `SystemSampler` (Task 1).
- Produces: `public final class LiveSystemSource: SystemSource { public init() }`; `SystemSampler.init()` (convenience, dùng `LiveSystemSource()`).

Ghi chú nền (đã chạy thử trên máy đích): `host_statistics(HOST_CPU_LOAD_INFO)` trả `cpu_ticks` dạng tuple 4 phần tử theo thứ tự USER, SYSTEM, IDLE, NICE. `NET_RT_IFLIST2` trả chuỗi bản ghi `if_msghdr`; bản ghi có `ifm_type == RTM_IFINFO2` là `if_msghdr2` với bộ đếm 64-bit `ifm_data.ifi_ibytes/ifi_obytes`; đi tiếp bằng `ifm_msglen`.

- [ ] **Step 1: Viết test thất bại**

`Tests/SystemStatsTests/LiveSourceTests.swift`:
```swift
import Foundation
import Testing
@testable import SystemStats

/// Đọc số liệu thật của máy đang chạy test (chỉ đọc, không cần quyền đặc biệt).
struct LiveSourceTests {
    let source = LiveSystemSource()

    @Test func readsCPUTicks() {
        let ticks = source.cpuTicks()
        #expect(ticks != nil)
        #expect((ticks?.idle ?? 0) > 0)
    }

    @Test func readsMemory() throws {
        let counts = try #require(source.memoryCounts())
        let used = counts.usedBytes(pageSize: source.pageSize())
        #expect(used > 0)
        #expect(used <= source.physicalMemory())
        #expect([1, 2, 4].contains(source.memoryPressureLevel()))
    }

    @Test func readsDisk() throws {
        let disk = try #require(source.diskCapacity())
        #expect(disk.total > 0)
        #expect(disk.free <= disk.total)
    }

    @Test func readsOnlyPhysicalInterfaces() {
        let counters = source.interfaceCounters()
        #expect(!counters.isEmpty)
        #expect(counters.keys.allSatisfy { $0.hasPrefix("en") })
    }

    @Test func liveSamplerProducesRatesOnSecondSample() async throws {
        let sampler = SystemSampler()
        _ = sampler.sample(now: Date())
        try await Task.sleep(for: .milliseconds(300))
        let snapshot = sampler.sample(now: Date())
        let cpu = try #require(snapshot.cpuPercent)
        #expect((0...100).contains(cpu))
        #expect((snapshot.downloadBytesPerSecond ?? -1) >= 0)
        #expect((snapshot.uploadBytesPerSecond ?? -1) >= 0)
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter LiveSourceTests`
Expected: build lỗi, không tìm thấy `LiveSystemSource`.

- [ ] **Step 3: Viết implementation**

`Sources/SystemStats/LiveSystemSource.swift`:
```swift
import Darwin
import Foundation

/// Đọc số liệu thật qua Mach, sysctl và thông tin ổ đĩa. Không cần quyền root.
public final class LiveSystemSource: SystemSource {
    public init() {}

    public func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // Thứ tự: CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE
        let ticks = info.cpu_ticks
        return CPUTicks(user: UInt64(ticks.0), system: UInt64(ticks.1), idle: UInt64(ticks.2), nice: UInt64(ticks.3))
    }

    public func memoryCounts() -> MemoryCounts? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryCounts(internalPages: UInt64(stats.internal_page_count),
                            purgeablePages: UInt64(stats.purgeable_count),
                            wiredPages: UInt64(stats.wire_count),
                            compressedPages: UInt64(stats.compressor_page_count))
    }

    public func pageSize() -> UInt64 {
        UInt64(vm_kernel_page_size)
    }

    public func physicalMemory() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// 0 nếu đọc lỗi (được hiểu là "bình thường").
    public func memoryPressureLevel() -> Int32 {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 0 }
        return level
    }

    public func diskCapacity() -> (free: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity,
              free >= 0, total > 0 else { return nil }
        return (free: UInt64(free), total: UInt64(total))
    }

    public func interfaceCounters() -> [String: InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var counters: [String: InterfaceCounters] = [:]
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = (base + offset).loadUnaligned(as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if header.ifm_type == UInt8(RTM_IFINFO2),
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = (base + offset).loadUnaligned(as: if_msghdr2.self)
                    let isUp = message.ifm_flags & IFF_UP != 0
                    let isLoopback = message.ifm_flags & IFF_LOOPBACK != 0
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if isUp, !isLoopback, if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if NetworkStats.isCounted(name: name) {
                            counters[name] = InterfaceCounters(received: message.ifm_data.ifi_ibytes,
                                                               sent: message.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return counters
    }
}
```

Thêm vào cuối class `SystemSampler` trong `Sources/SystemStats/Sampler.swift` (ngay sau `public init(source:)`):
```swift
    /// Lấy mẫu từ hệ thống thật.
    public convenience init() {
        self.init(source: LiveSystemSource())
    }
```

- [ ] **Step 4: Chạy test để xác nhận đạt**

Run: `swift test --filter LiveSourceTests`
Expected: 5 test pass.

Run: `swift test`
Expected: toàn bộ pass, không warning.

- [ ] **Step 5: Commit**

```bash
git add Sources/SystemStats Tests/SystemStatsTests/LiveSourceTests.swift
git commit -m "feat: read CPU, memory, disk and network from the live system" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Định dạng số mới trong `Format`

**Files:**
- Modify: `Sources/Shared/Format.swift`
- Test: `Tests/SharedTests/FormatTests.swift`

**Interfaces:**
- Consumes: `Format.grouped(_:)` (đã có, internal).
- Produces: `Format.memory(_ bytes: UInt64) -> String`, `Format.disk(_ bytes: UInt64) -> String`, `Format.rate(_ bytesPerSecond: Double?) -> String`, `Format.percent(_ value: Double?) -> String`, `Format.decimal(_ value: Double, digits: Int) -> String` (internal).

- [ ] **Step 1: Viết test thất bại**

Thêm vào cuối struct `FormatTests` trong `Tests/SharedTests/FormatTests.swift` (trước dấu `}` cuối cùng):
```swift
    @Test func formatsDecimalWithComma() {
        #expect(Format.decimal(11.2, digits: 1) == "11,2")
        #expect(Format.decimal(16.0, digits: 1) == "16")
        #expect(Format.decimal(181.6, digits: 0) == "182")
    }

    @Test func formatsMemoryInBinaryGigabytes() {
        #expect(Format.memory(12_025_908_428) == "11,2 GB")
        #expect(Format.memory(17_179_869_184) == "16 GB")
    }

    @Test func formatsDiskInDecimalUnits() {
        #expect(Format.disk(182_400_000_000) == "182 GB")
        #expect(Format.disk(494_384_795_648) == "494 GB")
        #expect(Format.disk(1_234_000_000_000) == "1,2 TB")
    }

    @Test func formatsNetworkRate() {
        #expect(Format.rate(nil) == "--")
        #expect(Format.rate(.nan) == "--")
        #expect(Format.rate(850) == "850 B/s")
        #expect(Format.rate(85_000) == "85 KB/s")
        #expect(Format.rate(1_234_567) == "1,2 MB/s")
    }

    @Test func formatsPercent() {
        #expect(Format.percent(23.4) == "23%")
        #expect(Format.percent(nil) == "--%")
        #expect(Format.percent(.infinity) == "--%")
    }
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter FormatTests`
Expected: build lỗi, `Format` không có `memory`, `disk`, `rate`, `percent`, `decimal`.

- [ ] **Step 3: Viết implementation**

Thêm vào enum `Format` trong `Sources/Shared/Format.swift`, ngay trước `static func grouped`:
```swift
    /// RAM theo hệ 1024 như Activity Monitor: 12_025_908_428 → "11,2 GB"; 16 GiB → "16 GB".
    public static func memory(_ bytes: UInt64) -> String {
        "\(decimal(Double(bytes) / 1_073_741_824, digits: 1)) GB"
    }

    /// Ổ đĩa theo hệ 1000 như Finder: 182_400_000_000 → "182 GB"; từ 1000 GB → "1,2 TB".
    public static func disk(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1000 { return "\(decimal(gigabytes / 1000, digits: 1)) TB" }
        return "\(decimal(gigabytes, digits: 0)) GB"
    }

    /// Tốc độ mạng theo hệ 1000: "850 B/s", "85 KB/s", "1,2 MB/s"; nil → "--".
    public static func rate(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return "--" }
        if value < 1000 { return "\(Int(value.rounded())) B/s" }
        if value < 1_000_000 { return "\(Int((value / 1000).rounded())) KB/s" }
        return "\(decimal(value / 1_000_000, digits: 1)) MB/s"
    }

    /// 23.4 → "23%"; nil → "--%".
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    /// Làm tròn `digits` chữ số thập phân, dấu phẩy kiểu Việt, bỏ phần ",0".
    static func decimal(_ value: Double, digits: Int) -> String {
        let factor = pow(10, Double(digits))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() { return grouped(Int(rounded)) }
        return String(format: "%.\(digits)f", rounded).replacingOccurrences(of: ".", with: ",")
    }
```

- [ ] **Step 4: Chạy test để xác nhận đạt**

Run: `swift test --filter FormatTests`
Expected: toàn bộ `FormatTests` pass.

Run: `swift test`
Expected: toàn bộ pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/Format.swift Tests/SharedTests/FormatTests.swift
git commit -m "feat: add Vietnamese formatting for memory, disk, rate and percent" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Popover bố cục A + lấy mẫu trong AppModel

**Files:**
- Modify: `Sources/FanControlApp/AppModel.swift`
- Create: `Sources/FanControlApp/SystemTiles.swift`
- Modify (viết lại toàn bộ): `Sources/FanControlApp/PopoverView.swift`

**Interfaces:**
- Consumes: `SystemSampler()`, `SystemSnapshot`, `MemoryPressure` (Task 1–2); `Format.memory/disk/rate/percent/temperature/rpm` (Task 3 + có sẵn); `AppModel.status`, `helperInstalled`, `connectionError`, `actionError`, `setMode(_:)`, `installHelper()`; `Status`, `FanStatus.fraction`, `Preset`.
- Produces: `AppModel.system: SystemSnapshot?`; views `SectionTitle`, `StatTile`, `SystemTiles`, `PopoverView`.

Không có unit test (view SwiftUI). Kiểm chứng bằng build không warning + chạy app + so số với Activity Monitor/Finder.

- [ ] **Step 1: Thêm lấy mẫu vào `AppModel`**

Trong `Sources/FanControlApp/AppModel.swift`:

Thêm `import SystemStats` sau `import Shared`.

Thêm thuộc tính ngay sau dòng `var actionError: String?`:
```swift
    /// Số liệu hệ thống (CPU, RAM, ổ đĩa, mạng), lấy trong app, không cần helper.
    private(set) var system: SystemSnapshot?
```

Thêm ngay sau dòng `@ObservationIgnored private let client = DaemonClient()`:
```swift
    @ObservationIgnored private let sampler = SystemSampler()
```

Thay vòng lặp trong `init()`:
```swift
    init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.system = self.sampler.sample(now: Date())
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
```

- [ ] **Step 2: Tạo `SystemTiles.swift`**

`Sources/FanControlApp/SystemTiles.swift`:
```swift
import SwiftUI
import Shared
import SystemStats

/// Tiêu đề nhỏ viết hoa của từng khối trong popover.
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Thẻ số liệu: nhãn nhỏ, số lớn, dòng phụ.
struct StatTile<Detail: View>: View {
    let title: String
    let symbol: String
    let value: String
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            detail()
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Lưới 2×2: CPU/GPU, RAM, ổ đĩa, mạng.
struct SystemTiles: View {
    let system: SystemSnapshot?
    let temperature: Double?

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            StatTile(title: "CPU/GPU", symbol: "thermometer.medium", value: Format.temperature(temperature)) {
                Text("CPU \(Format.percent(system?.cpuPercent))")
            }
            StatTile(title: "RAM", symbol: "memorychip",
                     value: system.map { Format.memory($0.memoryUsed) } ?? "--") {
                if let system {
                    HStack(spacing: 0) {
                        Text("/ \(Format.memory(system.memoryTotal)) · ")
                        Text(system.memoryPressure.label)
                            .foregroundStyle(system.memoryPressure.color)
                    }
                } else {
                    Text("--")
                }
            }
            StatTile(title: "Ổ đĩa", symbol: "internaldrive",
                     value: system?.diskFree.map { Format.disk($0) } ?? "--") {
                Text("trống / \(system?.diskTotal.map { Format.disk($0) } ?? "--")")
            }
            StatTile(title: "Mạng", symbol: "arrow.up.arrow.down",
                     value: "↓ \(Format.rate(system?.downloadBytesPerSecond))") {
                Text("↑ \(Format.rate(system?.uploadBytesPerSecond))")
            }
        }
    }
}

extension MemoryPressure {
    var label: String {
        switch self {
        case .normal: return "bình thường"
        case .warning: return "cao"
        case .critical: return "nguy hiểm"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
```

- [ ] **Step 3: Viết lại `PopoverView.swift`**

Thay toàn bộ `Sources/FanControlApp/PopoverView.swift`:
```swift
import AppKit
import SwiftUI
import Shared

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Hệ thống")
            SystemTiles(system: model.system, temperature: model.status?.temperature)

            if !model.helperInstalled {
                HelperMissingView()
            } else if let message = model.connectionError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Cài lại helper") { Task { await model.installHelper() } }
            } else if let status = model.status {
                FanSection(status: status)
                Divider()
                SectionTitle("Chế độ quạt")
                ModeGrid(status: status)
            } else {
                ProgressView("Đang kết nối…")
                    .frame(maxWidth: .infinity)
            }

            if let error = model.actionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button("Cài đặt…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Thoát") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct HelperMissingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Chưa cài trình điều khiển quạt", systemImage: "exclamationmark.circle")
                .font(.headline)
            Text("Helper chạy nền với quyền quản trị để chỉnh tốc độ quạt. macOS sẽ hỏi mật khẩu một lần.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cài đặt helper") { Task { await model.installHelper() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Cảnh báo từ daemon và tốc độ từng quạt.
private struct FanSection: View {
    let status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if status.safetyActive {
                Label("Quá nóng – đang chạy quạt tối đa", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let error = status.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(status.fans, id: \.index) { fan in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Quạt \(fan.index + 1)")
                        Spacer()
                        Text(Format.rpm(fan.rpm))
                            .monospacedDigit()
                    }
                    ProgressView(value: fan.fraction)
                }
            }
        }
    }
}

/// Ô chọn nhanh chế độ, 2 cột; ô đang dùng tô màu nhấn.
private struct ModeGrid: View {
    @Environment(AppModel.self) private var model
    let status: Status

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(status.presets) { preset in
                let active = preset.id == status.activePresetID
                Button {
                    Task { await model.setMode(preset.id) }
                } label: {
                    Text(preset.name)
                        .font(.callout.weight(active ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .background(active ? Color.accentColor : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 4: Build và kiểm chứng**

Run: `swift build 2>&1 | grep -E "warning|error"; swift test 2>&1 | tail -1`
Expected: không có dòng warning/error; dòng cuối báo toàn bộ test pass.

Run: `make install && (pkill -x FanControl; open /Applications/FanControl.app) && perl -e 'select(undef,undef,undef,3)' && pgrep -x FanControl`
Expected: in ra PID.

Kiểm tra tay (controller/người dùng): mở popover → thấy tiêu đề "HỆ THỐNG", 4 thẻ, dòng quạt, "CHẾ ĐỘ QUẠT" với ô 2 cột, ô đang dùng màu xanh; sau ~2 giây thẻ CPU và Mạng có số; RAM/ổ đĩa khớp Activity Monitor và Finder (sai số làm tròn).

- [ ] **Step 5: Commit**

```bash
git add Sources/FanControlApp/AppModel.swift Sources/FanControlApp/SystemTiles.swift Sources/FanControlApp/PopoverView.swift
git commit -m "feat: show system stats tiles and fan mode grid in popover" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Icon app

**Files:**
- Create: `scripts/make-icon.swift`, `Resources/AppIcon.icns`
- Modify: `Resources/Info.plist`, `Makefile`

**Interfaces:**
- Consumes: `Makefile` target `app` hiện có.
- Produces: `make icon` (tạo lại `Resources/AppIcon.icns`), bundle có `Contents/Resources/AppIcon.icns`, `CFBundleIconFile = AppIcon`.

- [ ] **Step 1: Viết script vẽ icon**

`scripts/make-icon.swift`:
```swift
// Vẽ icon app vào một thư mục .iconset: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

/// Nền bo góc chuyển màu xanh dương → xanh ngọc, hình quạt trắng ở giữa.
func render(size: Int) -> Data {
    let side = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Lề 10% như icon macOS chuẩn, bo góc 22,5%
    let inset = side * 0.1
    let rect = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = side * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.01)
    shadow.set()
    color(0x2F80ED).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x2F80ED), ending: color(0x2BC0B4))!.draw(in: shape, angle: -45)

    let config = NSImage.SymbolConfiguration(pointSize: side * 0.40, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let fan = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let fanSize = fan.size
    fan.draw(in: NSRect(x: (side - fanSize.width) / 2, y: (side - fanSize.height) / 2,
                        width: fanSize.width, height: fanSize.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
```

- [ ] **Step 2: Thêm target `icon` và copy icon trong `Makefile`**

Trong `Makefile`:
- Sửa dòng `.PHONY:` thành: `.PHONY: build test app install dmg notarize icon clean`
- Thêm ngay sau dòng `cp Resources/local.fancontrol.daemon.plist $(APP)/Contents/Resources/` (trong target `app`, thụt bằng tab):
```make
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
```
- Thêm target mới ngay trước `clean:` (thụt bằng tab):
```make
icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

- [ ] **Step 3: Khai báo icon trong `Resources/Info.plist`**

Thêm ngay sau cặp `<key>CFBundleExecutable</key>` / `<string>FanControl</string>`:
```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
```

- [ ] **Step 4: Tạo icon và kiểm chứng**

Run: `make icon && ls -la Resources/AppIcon.icns && plutil -lint Resources/Info.plist`
Expected: `Resources/AppIcon.icns` tồn tại (vài trăm KB); `Resources/Info.plist: OK`.

Run: `sips -s format png Resources/AppIcon.icns --out /tmp/appicon-check.png >/dev/null && sips -g pixelWidth /tmp/appicon-check.png`
Expected: `pixelWidth: 1024`. Mở `/tmp/appicon-check.png` (Read tool) để xem icon: nền bo góc xanh dương → xanh ngọc, quạt trắng ở giữa.

Run: `make install && codesign --verify --strict --deep /Applications/FanControl.app && echo signed-ok`
Expected: `signed-ok`. Icon hiện trong Finder ở `/Applications` (có thể cần `killall Finder` để làm mới cache icon).

- [ ] **Step 5: Commit**

```bash
git add scripts/make-icon.swift Resources/AppIcon.icns Resources/Info.plist Makefile
git commit -m "feat: add generated app icon" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Phiên bản mới, README, build DMG

**Files:**
- Modify: `Resources/Info.plist` (`CFBundleShortVersionString` 1.0 → 1.1, `CFBundleVersion` 1 → 2), `README.md`

**Interfaces:**
- Consumes: mọi task trước; `make notarize` (keychain profile `fancontrol-notary` đã có trên máy).
- Produces: `build/FanControl-1.1.dmg` đã ký + notarize + staple.

- [ ] **Step 1: Tăng phiên bản**

Trong `Resources/Info.plist`: đổi `<string>1.0</string>` sau `CFBundleShortVersionString` thành `<string>1.1</string>`, và `<string>1</string>` sau `CFBundleVersion` thành `<string>2</string>`.

- [ ] **Step 2: Cập nhật README**

Trong `README.md`, ngay sau dòng mô tả đầu tiên (`App menu bar tự chỉnh tốc độ quạt ...`), thêm đoạn:
```markdown

Popover còn hiện nhanh CPU %, RAM (kèm áp lực bộ nhớ), dung lượng ổ đĩa trống và tốc độ mạng (Wi-Fi/Ethernet).
```

Trong khối lệnh build, thêm dòng sau `make install`:
```
make icon        # vẽ lại Resources/AppIcon.icns từ scripts/make-icon.swift
```

- [ ] **Step 3: Build, notarize và kiểm chứng**

Run: `swift test 2>&1 | tail -1`
Expected: toàn bộ test pass.

Run: `make notarize` (chạy nền, mất vài phút)
Expected: `status: Accepted`, `The staple and validate action worked!`, `build/FanControl-1.1.dmg: accepted` / `source=Notarized Developer ID`.

- [ ] **Step 4: Commit**

```bash
git add Resources/Info.plist README.md
git commit -m "chore: bump version to 1.1 and document system stats" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
