# Fan Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App menu bar macOS (giao diện tiếng Việt) tự chỉnh tốc độ quạt MacBook Pro M1 Pro theo nhiệt độ CPU/GPU, thông qua một daemon root ghi vào SMC.

**Architecture:** Swift Package gồm `Shared` (model + protocol XPC + logic thuần dùng chung), `FanCore` (SMC, cảm biến, bộ điều khiển, vòng điều khiển — test bằng `MockSMC`), `fanctld` (daemon launchd chạy root, phục vụ XPC) và `FanControlApp` (SwiftUI `MenuBarExtra` + cửa sổ Cài đặt). App đóng gói thành `FanControl.app` bằng `Makefile`, nhúng sẵn `fanctld`; nút "Cài đặt helper" trong app copy daemon vào hệ thống qua AppleScript có quyền admin.

**Tech Stack:** Swift 6.2 toolchain (Swift 5 language mode), SwiftPM, swift-testing, IOKit, SwiftUI, Swift Charts, NSXPCConnection, ServiceManagement.

**Spec:** `docs/superpowers/specs/2026-10-26-fan-control-design.md`

## Global Constraints

- Nền tảng: `macOS 14+` (`platforms: [.macOS(.v14)]`), chỉ arm64, máy mục tiêu MacBookPro18,3 (M1 Pro).
- `swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]` (tránh strict concurrency của Swift 6).
- Không dùng dependency bên ngoài.
- Mọi chuỗi hiển thị cho người dùng viết trực tiếp bằng **tiếng Việt** trong code, không dùng localization. Comment trong code cũng bằng tiếng Việt.
- Định danh: mach service / launchd label `local.fancontrol.daemon`, bundle id app `local.fancontrol.app`.
- Đường dẫn cài đặt: `/Library/PrivilegedHelperTools/fanctld`, `/Library/LaunchDaemons/local.fancontrol.daemon.plist`, cấu hình `/Library/Application Support/FanControl/config.json`, log `/var/log/fanctld.log`.
- Thông số điều khiển: chu kỳ 2 giây; EMA α = 0.3; ngưỡng an toàn bật ≥ 95°C (nhiệt độ thô), tắt < 90°C; hysteresis về Auto 3°C; giảm tối đa 300 RPM/chu kỳ; chỉ ghi khi lệch > 50 RPM; 3 lỗi liên tiếp (đọc hoặc ghi) → về Auto.
- Cảm biến hợp lệ: key bắt đầu bằng `Tp`, `Te`, `Tg`, kiểu `flt `, giá trị trong `0...130`.
- Preset có sẵn (id → tên): `auto` → "Apple tự động", `silent` → "Êm", `balanced` → "Cân bằng" (mặc định), `performance` → "Hiệu năng", `max` → "Tối đa".
- Mỗi commit kết thúc bằng dòng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (dùng `-m` thứ hai như trong các bước).
- Các bước cần mật khẩu admin (cài helper, `sudo`) do **người dùng** thực hiện; agent dừng lại và nhờ người dùng.

**Chênh lệch nhỏ so với spec (có chủ đích):**
- `FanCurve` nằm trong `Shared` thay vì `FanCore`, để app dùng lại `validate()` khi chỉnh đường cong.
- `Status` chứa luôn danh sách preset, nên protocol XPC không cần thêm hàm `getConfig`.
- "Đổi tên" là ô nhập tên ngay trong trình chỉnh preset; "Xóa điểm" là xóa điểm cuối.

---

## File Structure

```
Package.swift
Makefile
.gitignore
README.md
Resources/
  Info.plist                          # Info.plist của FanControl.app (LSUIElement)
  local.fancontrol.daemon.plist       # launchd plist của daemon
Sources/
  Shared/
    FanCurve.swift                    # CurvePoint, FanCurve (nội suy, validate)
    Preset.swift                      # PresetKind, Preset, preset có sẵn
    Config.swift                      # Config + thao tác sửa có kiểm tra
    Status.swift                      # FanStatus, Status (daemon → app)
    Format.swift                      # định dạng số kiểu Việt
    XPCProtocol.swift                 # FanDaemonProtocol, XPCConstants
    HelperScripts.swift               # lệnh shell cài/gỡ helper
  FanCore/
    FourCC.swift                      # chuyển key 4 ký tự ↔ UInt32
    SMC.swift                         # SMCDevice protocol, SMCKeyInfo, SMCError, đọc/ghi kiểu
    AppleSMC.swift                    # bản thật dùng IOKit
    Fans.swift                        # FanInfo, FanCommand, FanService
    Sensors.swift                     # SensorService
    Controller.swift                  # máy trạng thái điều khiển (thuần)
    ConfigStore.swift                 # đọc/ghi config.json
    ControlLoop.swift                 # ghép SMC + Controller + cấu hình
  fanctld/
    main.swift                        # entry point daemon
    DaemonService.swift               # đối tượng XPC
    PowerMonitor.swift                # sự kiện thức dậy
  FanControlApp/
    App.swift                         # @main, scene
    DaemonClient.swift                # client XPC async
    HelperInstaller.swift             # chạy AppleScript cài/gỡ
    AppModel.swift                    # trạng thái app (@Observable)
    MenuBarLabel.swift
    PopoverView.swift
    SettingsView.swift
    GeneralTab.swift
    CurvesTab.swift
    PresetEditor.swift                # PresetEditor, CurveChart, PointTable
Tests/
  SharedTests/
    FanCurveTests.swift
    ConfigTests.swift
    FormatTests.swift
    HelperScriptsTests.swift
  FanCoreTests/
    MockSMC.swift
    SMCTests.swift
    FanServiceTests.swift
    SensorServiceTests.swift
    ControllerTests.swift
    ConfigStoreTests.swift
    ControlLoopTests.swift
```

---

### Task 1: Khởi tạo package + FanCurve

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/Shared/FanCurve.swift`
- Test: `Tests/SharedTests/FanCurveTests.swift`

**Interfaces:**
- Consumes: không có.
- Produces:
  - `public struct CurvePoint: Codable, Hashable, Sendable { var temp: Double; var percent: Double; init(temp:percent:) }`
  - `public struct FanCurve: Codable, Hashable, Sendable { var points: [CurvePoint]; init(points:); static let validTempRange: ClosedRange<Double> /*20...110*/; static let validPercentRange /*0...100*/; func percent(at temp: Double) -> Double?; func validate() -> ValidationError? }`
  - `public enum FanCurve.ValidationError: Error, Equatable, Sendable { case tooFewPoints, tempOutOfRange, percentOutOfRange, tempNotIncreasing, percentDecreasing; var message: String }`

- [ ] **Step 1: Tạo `Package.swift` và `.gitignore`**

`Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
    ],
    swiftLanguageModes: [.v5]
)
```

`.gitignore`:
```
.build/
build/
.swiftpm/
*.xcodeproj
.DS_Store
```

- [ ] **Step 2: Viết test thất bại**

`Tests/SharedTests/FanCurveTests.swift`:
```swift
import Testing
@testable import Shared

struct FanCurveTests {
    let balanced = FanCurve(points: [
        CurvePoint(temp: 55, percent: 0),
        CurvePoint(temp: 65, percent: 35),
        CurvePoint(temp: 75, percent: 65),
        CurvePoint(temp: 85, percent: 100),
    ])

    @Test func belowFirstPointReturnsNil() {
        #expect(balanced.percent(at: 54.9) == nil)
    }

    @Test func atFirstPointReturnsFirstPercent() {
        #expect(balanced.percent(at: 55) == 0)
    }

    @Test func interpolatesBetweenPoints() {
        #expect(balanced.percent(at: 60) == 17.5)
        #expect(balanced.percent(at: 70) == 50)
    }

    @Test func aboveLastPointHoldsLastPercent() {
        #expect(balanced.percent(at: 99) == 100)
    }

    @Test func emptyCurveReturnsNil() {
        #expect(FanCurve(points: []).percent(at: 70) == nil)
    }

    @Test func validCurvePasses() {
        #expect(balanced.validate() == nil)
    }

    @Test func rejectsTooFewPoints() {
        #expect(FanCurve(points: [CurvePoint(temp: 50, percent: 0)]).validate() == .tooFewPoints)
    }

    @Test func rejectsTempOutOfRange() {
        let curve = FanCurve(points: [CurvePoint(temp: 15, percent: 0), CurvePoint(temp: 60, percent: 50)])
        #expect(curve.validate() == .tempOutOfRange)
    }

    @Test func rejectsPercentOutOfRange() {
        let curve = FanCurve(points: [CurvePoint(temp: 50, percent: 0), CurvePoint(temp: 60, percent: 120)])
        #expect(curve.validate() == .percentOutOfRange)
    }

    @Test func rejectsNonIncreasingTemp() {
        let curve = FanCurve(points: [CurvePoint(temp: 60, percent: 0), CurvePoint(temp: 60, percent: 50)])
        #expect(curve.validate() == .tempNotIncreasing)
    }

    @Test func rejectsDecreasingPercent() {
        let curve = FanCurve(points: [CurvePoint(temp: 50, percent: 60), CurvePoint(temp: 70, percent: 40)])
        #expect(curve.validate() == .percentDecreasing)
    }

    @Test func validationMessagesAreVietnamese() {
        #expect(FanCurve.ValidationError.tooFewPoints.message == "Cần ít nhất 2 điểm")
    }
}
```

- [ ] **Step 3: Chạy test để xác nhận thất bại**

Run: `swift test --filter FanCurveTests`
Expected: build lỗi vì không tìm thấy `FanCurve` / `CurvePoint` (hoặc lỗi "target Shared has no sources").

- [ ] **Step 4: Viết implementation**

`Sources/Shared/FanCurve.swift`:
```swift
import Foundation

/// Một điểm trên đường cong: tại `temp` °C quạt chạy `percent` % (0 = min, 100 = max của từng quạt).
public struct CurvePoint: Codable, Hashable, Sendable {
    public var temp: Double
    public var percent: Double

    public init(temp: Double, percent: Double) {
        self.temp = temp
        self.percent = percent
    }
}

public struct FanCurve: Codable, Hashable, Sendable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points
    }

    public static let validTempRange: ClosedRange<Double> = 20...110
    public static let validPercentRange: ClosedRange<Double> = 0...100

    /// % tốc độ tại `temp`. `nil` nghĩa là dưới điểm đầu → trả quạt cho Apple.
    public func percent(at temp: Double) -> Double? {
        guard let first = points.first, let last = points.last, temp >= first.temp else { return nil }
        if temp >= last.temp { return last.percent }
        for (a, b) in zip(points, points.dropFirst()) where temp < b.temp {
            let t = (temp - a.temp) / (b.temp - a.temp)
            return a.percent + t * (b.percent - a.percent)
        }
        return last.percent
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case tooFewPoints
        case tempOutOfRange
        case percentOutOfRange
        case tempNotIncreasing
        case percentDecreasing

        public var message: String {
            switch self {
            case .tooFewPoints: return "Cần ít nhất 2 điểm"
            case .tempOutOfRange: return "Nhiệt độ phải trong khoảng 20–110°C"
            case .percentOutOfRange: return "Tốc độ phải trong khoảng 0–100%"
            case .tempNotIncreasing: return "Nhiệt độ các điểm phải tăng dần"
            case .percentDecreasing: return "Tốc độ không được giảm khi nhiệt độ tăng"
            }
        }
    }

    public func validate() -> ValidationError? {
        guard points.count >= 2 else { return .tooFewPoints }
        if points.contains(where: { !Self.validTempRange.contains($0.temp) }) { return .tempOutOfRange }
        if points.contains(where: { !Self.validPercentRange.contains($0.percent) }) { return .percentOutOfRange }
        for (a, b) in zip(points, points.dropFirst()) {
            if b.temp <= a.temp { return .tempNotIncreasing }
            if b.percent < a.percent { return .percentDecreasing }
        }
        return nil
    }
}
```

- [ ] **Step 5: Chạy test để xác nhận đạt**

Run: `swift test --filter FanCurveTests`
Expected: `Test run with 12 tests ... passed`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources/Shared/FanCurve.swift Tests/SharedTests/FanCurveTests.swift
git commit -m "feat: scaffold package and add FanCurve" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Preset, Config, Status, Format, protocol XPC

**Files:**
- Create: `Sources/Shared/Preset.swift`, `Sources/Shared/Config.swift`, `Sources/Shared/Status.swift`, `Sources/Shared/Format.swift`, `Sources/Shared/XPCProtocol.swift`
- Test: `Tests/SharedTests/ConfigTests.swift`, `Tests/SharedTests/FormatTests.swift`

**Interfaces:**
- Consumes: `CurvePoint`, `FanCurve`, `FanCurve.ValidationError` (Task 1).
- Produces:
  - `public enum PresetKind: String, Codable, Sendable { case auto, max, curve }`
  - `public struct Preset: Codable, Hashable, Identifiable, Sendable { var id: String; var name: String; var kind: PresetKind; var curve: FanCurve; var isBuiltIn: Bool; init(id:name:kind:curve:isBuiltIn:); static let autoID, silentID, balancedID, performanceID, maxID: String; static let builtIns: [Preset]; static var balanced: Preset; func duplicated() -> Preset }`
  - `public struct Config: Codable, Equatable, Sendable { var activePresetID: String; var customPresets: [Preset]; init(activePresetID:customPresets:); static let default; var allPresets: [Preset]; var activePreset: Preset; mutating func setActive(_ id: String) throws; mutating func upsert(_ preset: Preset) throws; mutating func delete(_ id: String) throws }`
  - `public enum Config.EditError: Error, Equatable, Sendable { case unknownPreset, builtInReadOnly, emptyName, notACurve, invalidCurve(FanCurve.ValidationError); var message: String }`
  - `public struct FanStatus: Codable, Equatable, Sendable { var index: Int; var rpm: Double; var minRPM: Double; var maxRPM: Double; var manual: Bool; var fraction: Double }`
  - `public struct Status: Codable, Equatable, Sendable { var temperature: Double?; var fans: [FanStatus]; var activePresetID: String; var presets: [Preset]; var safetyActive: Bool; var error: String? }`
  - `public enum Format { static func rpm(_:) -> String; static func temperature(_: Double?) -> String; static func shortTemperature(_: Double?) -> String }`
  - `public enum XPCConstants { static let machServiceName = "local.fancontrol.daemon" }`
  - `@objc public protocol FanDaemonProtocol { getStatus(reply: (Data) -> Void); setMode(_ presetID: String, reply: (String?) -> Void); savePreset(_ presetJSON: Data, reply: (String?) -> Void); deletePreset(_ presetID: String, reply: (String?) -> Void) }`

- [ ] **Step 1: Viết test thất bại**

`Tests/SharedTests/ConfigTests.swift`:
```swift
import Foundation
import Testing
@testable import Shared

struct ConfigTests {
    func customPreset(id: String = "c1", name: String = "Chơi game") -> Preset {
        Preset(id: id, name: name, kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 50, percent: 10), CurvePoint(temp: 80, percent: 100),
        ]))
    }

    @Test func builtInsHaveExpectedIDsAndNames() {
        #expect(Preset.builtIns.map(\.id) == ["auto", "silent", "balanced", "performance", "max"])
        #expect(Preset.builtIns.map(\.name) == ["Apple tự động", "Êm", "Cân bằng", "Hiệu năng", "Tối đa"])
        #expect(Preset.builtIns.allSatisfy(\.isBuiltIn))
    }

    @Test func builtInCurvesAreValid() {
        for preset in Preset.builtIns where preset.kind == .curve {
            #expect(preset.curve.validate() == nil, "\(preset.id)")
        }
    }

    @Test func defaultConfigUsesBalanced() {
        #expect(Config.default.activePreset.id == Preset.balancedID)
    }

    @Test func activePresetFallsBackToBalancedForUnknownID() {
        let config = Config(activePresetID: "missing")
        #expect(config.activePreset.id == Preset.balancedID)
    }

    @Test func setActiveRejectsUnknownPreset() {
        var config = Config()
        #expect(throws: Config.EditError.unknownPreset) { try config.setActive("nope") }
    }

    @Test func setActiveAcceptsBuiltIn() throws {
        var config = Config()
        try config.setActive(Preset.maxID)
        #expect(config.activePresetID == "max")
    }

    @Test func upsertInsertsThenUpdates() throws {
        var config = Config()
        try config.upsert(customPreset())
        var renamed = customPreset()
        renamed.name = "Render"
        try config.upsert(renamed)
        #expect(config.customPresets.count == 1)
        #expect(config.customPresets[0].name == "Render")
        #expect(config.allPresets.count == 6)
    }

    @Test func upsertRejectsBuiltIn() {
        var config = Config()
        var preset = Preset.balanced
        preset.isBuiltIn = false
        #expect(throws: Config.EditError.builtInReadOnly) { try config.upsert(preset) }
    }

    @Test func upsertRejectsEmptyName() {
        var config = Config()
        #expect(throws: Config.EditError.emptyName) { try config.upsert(customPreset(name: "  ")) }
    }

    @Test func upsertRejectsNonCurve() {
        var config = Config()
        var preset = customPreset()
        preset.kind = .max
        #expect(throws: Config.EditError.notACurve) { try config.upsert(preset) }
    }

    @Test func upsertRejectsInvalidCurve() {
        var config = Config()
        var preset = customPreset()
        preset.curve.points = [CurvePoint(temp: 50, percent: 0)]
        #expect(throws: Config.EditError.invalidCurve(.tooFewPoints)) { try config.upsert(preset) }
    }

    @Test func deleteActiveCustomFallsBackToBalanced() throws {
        var config = Config()
        try config.upsert(customPreset())
        try config.setActive("c1")
        try config.delete("c1")
        #expect(config.customPresets.isEmpty)
        #expect(config.activePresetID == Preset.balancedID)
    }

    @Test func deleteRejectsBuiltInAndUnknown() {
        var config = Config()
        #expect(throws: Config.EditError.builtInReadOnly) { try config.delete(Preset.silentID) }
        #expect(throws: Config.EditError.unknownPreset) { try config.delete("nope") }
    }

    @Test func duplicatedPresetIsCustomAndSavable() throws {
        let copy = Preset.balanced.duplicated()
        #expect(copy.id != Preset.balancedID)
        #expect(copy.name == "Cân bằng (bản sao)")
        #expect(!copy.isBuiltIn)
        var config = Config()
        try config.upsert(copy)
        #expect(config.customPresets == [copy])
    }

    @Test func configRoundTripsThroughJSON() throws {
        var config = Config()
        try config.upsert(customPreset())
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func statusRoundTripsThroughJSON() throws {
        let status = Status(
            temperature: 58.5,
            fans: [FanStatus(index: 0, rpm: 2450, minRPM: 1200, maxRPM: 5779, manual: true)],
            activePresetID: "balanced", presets: Preset.builtIns, safetyActive: false, error: nil)
        let data = try JSONEncoder().encode(status)
        #expect(try JSONDecoder().decode(Status.self, from: data) == status)
    }

    @Test func fanFractionIsClamped() {
        #expect(FanStatus(index: 0, rpm: 0, minRPM: 1200, maxRPM: 5200, manual: false).fraction == 0)
        #expect(FanStatus(index: 0, rpm: 3200, minRPM: 1200, maxRPM: 5200, manual: true).fraction == 0.5)
        #expect(FanStatus(index: 0, rpm: 9000, minRPM: 1200, maxRPM: 5200, manual: true).fraction == 1)
    }
}
```

`Tests/SharedTests/FormatTests.swift`:
```swift
import Testing
@testable import Shared

struct FormatTests {
    @Test func groupsThousandsWithDots() {
        #expect(Format.grouped(0) == "0")
        #expect(Format.grouped(999) == "999")
        #expect(Format.grouped(2450) == "2.450")
        #expect(Format.grouped(12345) == "12.345")
        #expect(Format.grouped(1234567) == "1.234.567")
    }

    @Test func formatsRPM() {
        #expect(Format.rpm(2449.6) == "2.450 vòng/phút")
    }

    @Test func formatsTemperature() {
        #expect(Format.temperature(58.4) == "58°C")
        #expect(Format.temperature(nil) == "--°C")
        #expect(Format.shortTemperature(58.6) == "59°")
        #expect(Format.shortTemperature(nil) == "--°")
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter "ConfigTests|FormatTests"`
Expected: build lỗi vì không tìm thấy `Preset`, `Config`, `Status`, `Format`.

- [ ] **Step 3: Viết implementation**

`Sources/Shared/Preset.swift`:
```swift
import Foundation

public enum PresetKind: String, Codable, Sendable {
    case auto   // trả quạt cho Apple
    case max    // luôn 100%
    case curve  // theo đường cong
}

public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: PresetKind
    public var curve: FanCurve
    public var isBuiltIn: Bool

    public init(id: String, name: String, kind: PresetKind, curve: FanCurve = FanCurve(points: []), isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.curve = curve
        self.isBuiltIn = isBuiltIn
    }

    public static let autoID = "auto"
    public static let silentID = "silent"
    public static let balancedID = "balanced"
    public static let performanceID = "performance"
    public static let maxID = "max"

    public static let builtIns: [Preset] = [
        Preset(id: autoID, name: "Apple tự động", kind: .auto, isBuiltIn: true),
        Preset(id: silentID, name: "Êm", kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 65, percent: 0), CurvePoint(temp: 75, percent: 30),
            CurvePoint(temp: 85, percent: 60), CurvePoint(temp: 92, percent: 100),
        ]), isBuiltIn: true),
        Preset(id: balancedID, name: "Cân bằng", kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 55, percent: 0), CurvePoint(temp: 65, percent: 35),
            CurvePoint(temp: 75, percent: 65), CurvePoint(temp: 85, percent: 100),
        ]), isBuiltIn: true),
        Preset(id: performanceID, name: "Hiệu năng", kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 45, percent: 20), CurvePoint(temp: 60, percent: 50),
            CurvePoint(temp: 70, percent: 80), CurvePoint(temp: 78, percent: 100),
        ]), isBuiltIn: true),
        Preset(id: maxID, name: "Tối đa", kind: .max, isBuiltIn: true),
    ]

    public static var balanced: Preset { builtIns.first { $0.id == balancedID }! }

    /// Bản sao tùy chỉnh (id mới) để người dùng chỉnh sửa.
    public func duplicated() -> Preset {
        Preset(id: UUID().uuidString, name: "\(name) (bản sao)", kind: .curve, curve: curve, isBuiltIn: false)
    }
}
```

`Sources/Shared/Config.swift`:
```swift
import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var activePresetID: String
    public var customPresets: [Preset]

    public init(activePresetID: String = Preset.balancedID, customPresets: [Preset] = []) {
        self.activePresetID = activePresetID
        self.customPresets = customPresets
    }

    public static let `default` = Config()

    public var allPresets: [Preset] { Preset.builtIns + customPresets }

    public var activePreset: Preset {
        allPresets.first { $0.id == activePresetID } ?? Preset.balanced
    }

    public enum EditError: Error, Equatable, Sendable {
        case unknownPreset
        case builtInReadOnly
        case emptyName
        case notACurve
        case invalidCurve(FanCurve.ValidationError)

        public var message: String {
            switch self {
            case .unknownPreset: return "Không tìm thấy chế độ này"
            case .builtInReadOnly: return "Chế độ có sẵn không thể sửa hoặc xóa"
            case .emptyName: return "Tên không được để trống"
            case .notACurve: return "Chế độ tùy chỉnh phải là đường cong"
            case .invalidCurve(let error): return error.message
            }
        }
    }

    public mutating func setActive(_ id: String) throws {
        guard allPresets.contains(where: { $0.id == id }) else { throw EditError.unknownPreset }
        activePresetID = id
    }

    /// Thêm mới hoặc cập nhật một chế độ tùy chỉnh.
    public mutating func upsert(_ preset: Preset) throws {
        if preset.isBuiltIn || Preset.builtIns.contains(where: { $0.id == preset.id }) {
            throw EditError.builtInReadOnly
        }
        if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw EditError.emptyName }
        guard preset.kind == .curve else { throw EditError.notACurve }
        if let error = preset.curve.validate() { throw EditError.invalidCurve(error) }

        if let index = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[index] = preset
        } else {
            customPresets.append(preset)
        }
    }

    public mutating func delete(_ id: String) throws {
        if Preset.builtIns.contains(where: { $0.id == id }) { throw EditError.builtInReadOnly }
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { throw EditError.unknownPreset }
        customPresets.remove(at: index)
        if activePresetID == id { activePresetID = Preset.balancedID }
    }
}
```

`Sources/Shared/Status.swift`:
```swift
import Foundation

public struct FanStatus: Codable, Equatable, Sendable {
    public var index: Int
    public var rpm: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var manual: Bool

    public init(index: Int, rpm: Double, minRPM: Double, maxRPM: Double, manual: Bool) {
        self.index = index
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.manual = manual
    }

    /// 0...1 cho thanh tiến độ (0 RPM khi Apple cho quạt nghỉ cũng hiển thị 0).
    public var fraction: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max((rpm - minRPM) / (maxRPM - minRPM), 0), 1)
    }
}

/// Trạng thái daemon gửi cho app mỗi lần app hỏi.
public struct Status: Codable, Equatable, Sendable {
    public var temperature: Double?
    public var fans: [FanStatus]
    public var activePresetID: String
    public var presets: [Preset]
    public var safetyActive: Bool
    public var error: String?

    public init(temperature: Double?, fans: [FanStatus], activePresetID: String, presets: [Preset], safetyActive: Bool, error: String?) {
        self.temperature = temperature
        self.fans = fans
        self.activePresetID = activePresetID
        self.presets = presets
        self.safetyActive = safetyActive
        self.error = error
    }
}
```

`Sources/Shared/Format.swift`:
```swift
import Foundation

/// Định dạng số kiểu Việt (dấu chấm phân cách hàng nghìn), không phụ thuộc locale máy.
public enum Format {
    /// 2450 → "2.450 vòng/phút"
    public static func rpm(_ value: Double) -> String {
        "\(grouped(Int(value.rounded()))) vòng/phút"
    }

    /// 58.4 → "58°C"; nil → "--°C"
    public static func temperature(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°C" } ?? "--°C"
    }

    /// Dùng trên thanh menu: 58.6 → "59°"; nil → "--°"
    public static func shortTemperature(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "--°"
    }

    static func grouped(_ number: Int) -> String {
        let digits = String(abs(number))
        var result = ""
        for (offset, character) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 { result.append(".") }
            result.append(character)
        }
        return number < 0 ? "-" + result : result
    }
}
```

`Sources/Shared/XPCProtocol.swift`:
```swift
import Foundation

public enum XPCConstants {
    public static let machServiceName = "local.fancontrol.daemon"
}

/// Giao tiếp app ↔ daemon. Model truyền dưới dạng JSON `Data`;
/// các hàm sửa trả về chuỗi lỗi tiếng Việt, `nil` nghĩa là thành công.
@objc public protocol FanDaemonProtocol {
    func getStatus(reply: @escaping (Data) -> Void)
    func setMode(_ presetID: String, reply: @escaping (String?) -> Void)
    func savePreset(_ presetJSON: Data, reply: @escaping (String?) -> Void)
    func deletePreset(_ presetID: String, reply: @escaping (String?) -> Void)
}
```

- [ ] **Step 4: Chạy test để xác nhận đạt**

Run: `swift test`
Expected: toàn bộ test `FanCurveTests`, `ConfigTests`, `FormatTests` đều pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared Tests/SharedTests
git commit -m "feat: add presets, config, status, formatting and XPC protocol" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Tầng SMC (FourCC, SMCDevice, AppleSMC, MockSMC)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/FanCore/FourCC.swift`, `Sources/FanCore/SMC.swift`, `Sources/FanCore/AppleSMC.swift`
- Test: `Tests/FanCoreTests/MockSMC.swift`, `Tests/FanCoreTests/SMCTests.swift`

**Interfaces:**
- Consumes: không có.
- Produces:
  - `func fourCC(_ s: String) -> UInt32`, `func fourCCString(_ v: UInt32) -> String` (internal)
  - `public struct SMCKeyInfo: Equatable, Sendable { var size: UInt32; var type: String }`
  - `public enum SMCError: Error, Equatable { case openFailed; case keyNotFound(String); case callFailed(String, Int32); case typeMismatch(key: String, expected: String, actual: String) }`
  - `public protocol SMCDevice: AnyObject { func keyInfo(_ key: String) throws -> SMCKeyInfo; func readBytes(_ key: String) throws -> [UInt8]; func writeBytes(_ key: String, _ bytes: [UInt8]) throws; func allKeys() throws -> [String] }`
  - Extension trên `SMCDevice`: `readFloat(_:) throws -> Float`, `readUInt8(_:) throws -> UInt8`, `writeFloat(_:_:) throws`, `writeUInt8(_:_:) throws`
  - `public final class AppleSMC: SMCDevice { init() throws }`
  - Test helper `final class MockSMC: SMCDevice` với `setFloat`, `setUInt8`, `float(_:)`, `uint8(_:)`, `writes`, `failingReads`, `failWrites`, `static func m1Pro() -> MockSMC`

Ghi chú nền: SMC được truy cập qua `IOConnectCallStructMethod(connection, 2, ...)` với struct C 80 byte. Mã lệnh nằm ở `data8`: 9 = đọc thông tin key, 5 = đọc byte, 6 = ghi byte, 8 = lấy tên key theo chỉ số. Swift không đệm cuối tuple như C, nên `keyInfo` phải có thêm 3 byte đệm tường minh; thiếu đệm thì mọi lệnh gọi đều thất bại (đã kiểm chứng bằng probe).

- [ ] **Step 1: Cập nhật `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .target(name: "FanCore", dependencies: ["Shared"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore", "Shared"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Viết MockSMC và test thất bại**

`Tests/FanCoreTests/MockSMC.swift`:
```swift
@testable import FanCore

/// SMC giả lập trong bộ nhớ, ghi lại mọi lệnh ghi.
final class MockSMC: SMCDevice {
    struct Entry {
        var type: String
        var bytes: [UInt8]
    }

    var entries: [String: Entry] = [:]
    var writes: [(key: String, bytes: [UInt8])] = []
    var failingReads: Set<String> = []
    var failWrites = false

    func setFloat(_ key: String, _ value: Float) {
        entries[key] = Entry(type: "flt ", bytes: withUnsafeBytes(of: value) { Array($0) })
    }

    func setUInt8(_ key: String, _ value: UInt8) {
        entries[key] = Entry(type: "ui8 ", bytes: [value])
    }

    func float(_ key: String) -> Float? {
        entries[key].map { $0.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) } }
    }

    func uint8(_ key: String) -> UInt8? {
        entries[key]?.bytes.first
    }

    func keyInfo(_ key: String) throws -> SMCKeyInfo {
        guard let entry = entries[key] else { throw SMCError.keyNotFound(key) }
        return SMCKeyInfo(size: UInt32(entry.bytes.count), type: entry.type)
    }

    func readBytes(_ key: String) throws -> [UInt8] {
        if failingReads.contains(key) { throw SMCError.callFailed(key, -1) }
        guard let entry = entries[key] else { throw SMCError.keyNotFound(key) }
        return entry.bytes
    }

    func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        if failWrites { throw SMCError.callFailed(key, -1) }
        guard entries[key] != nil else { throw SMCError.keyNotFound(key) }
        entries[key]!.bytes = bytes
        writes.append((key, bytes))
    }

    func allKeys() throws -> [String] {
        entries.keys.sorted()
    }

    /// Giống MacBook Pro M1 Pro: 2 quạt, 3 cảm biến hợp lệ, 1 key nhiễu kiểu ui8.
    static func m1Pro() -> MockSMC {
        let smc = MockSMC()
        smc.setUInt8("FNum", 2)
        for (index, maxRPM) in [(0, Float(5779)), (1, Float(6241))] {
            smc.setFloat("F\(index)Mn", 1200)
            smc.setFloat("F\(index)Mx", maxRPM)
            smc.setFloat("F\(index)Ac", 0)
            smc.setFloat("F\(index)Tg", 0)
            smc.setUInt8("F\(index)Md", 0)
        }
        smc.setFloat("Tp01", 50)
        smc.setFloat("Te05", 45)
        smc.setFloat("Tg05", 48)
        smc.setUInt8("Tp0Z", 77)
        return smc
    }
}
```

`Tests/FanCoreTests/SMCTests.swift`:
```swift
import Foundation
import Testing
@testable import FanCore

struct SMCTests {
    @Test func paramStructMatchesCLayout() {
        #expect(MemoryLayout<SMCParamStruct>.stride == 80)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo) == 28)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.bytes) == 48)
    }

    @Test func fourCCRoundTrips() {
        #expect(fourCC("F0Ac") == 0x4630_4163)
        #expect(fourCCString(0x4630_4163) == "F0Ac")
        #expect(fourCCString(fourCC("flt ")) == "flt ")
    }

    @Test func floatRoundTripsThroughDevice() throws {
        let smc = MockSMC.m1Pro()
        try smc.writeFloat("F0Tg", 2450.5)
        #expect(try smc.readFloat("F0Tg") == 2450.5)
    }

    @Test func uint8RoundTripsThroughDevice() throws {
        let smc = MockSMC.m1Pro()
        try smc.writeUInt8("F0Md", 1)
        #expect(try smc.readUInt8("F0Md") == 1)
    }

    @Test func typedReadRejectsWrongType() {
        let smc = MockSMC.m1Pro()
        #expect(throws: SMCError.typeMismatch(key: "F0Md", expected: "flt ", actual: "ui8 ")) {
            try smc.readFloat("F0Md")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FANCTL_HW"] == "1"))
    func readsRealSMC() throws {
        let smc = try AppleSMC()
        #expect(try smc.readUInt8("FNum") >= 1)
        #expect(try smc.readFloat("F0Mx") > 1000)
        #expect(try smc.allKeys().contains("F0Ac"))
    }
}
```

- [ ] **Step 3: Chạy test để xác nhận thất bại**

Run: `swift test --filter SMCTests`
Expected: build lỗi vì không tìm thấy `SMCDevice`, `SMCParamStruct`, `fourCC`.

- [ ] **Step 4: Viết implementation**

`Sources/FanCore/FourCC.swift`:
```swift
/// "F0Ac" → 0x46304163 (mã 4 ký tự big-endian mà SMC dùng làm key và kiểu dữ liệu).
func fourCC(_ string: String) -> UInt32 {
    string.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
}

func fourCCString(_ value: UInt32) -> String {
    String(decoding: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }, as: UTF8.self)
}
```

`Sources/FanCore/SMC.swift`:
```swift
import Foundation

public struct SMCKeyInfo: Equatable, Sendable {
    public var size: UInt32
    public var type: String

    public init(size: UInt32, type: String) {
        self.size = size
        self.type = type
    }
}

public enum SMCError: Error, Equatable {
    case openFailed
    case keyNotFound(String)
    case callFailed(String, Int32)
    case typeMismatch(key: String, expected: String, actual: String)
}

/// Truy cập thô vào SMC. `AppleSMC` là bản thật; test dùng `MockSMC`.
public protocol SMCDevice: AnyObject {
    func keyInfo(_ key: String) throws -> SMCKeyInfo
    func readBytes(_ key: String) throws -> [UInt8]
    func writeBytes(_ key: String, _ bytes: [UInt8]) throws
    func allKeys() throws -> [String]
}

public extension SMCDevice {
    /// `flt ` trên Apple Silicon là float32 little-endian.
    func readFloat(_ key: String) throws -> Float {
        try requireType(key, "flt ")
        let bytes = try readBytes(key)
        guard bytes.count >= 4 else {
            throw SMCError.typeMismatch(key: key, expected: "flt ", actual: "\(bytes.count) byte")
        }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    func readUInt8(_ key: String) throws -> UInt8 {
        try requireType(key, "ui8 ")
        guard let value = try readBytes(key).first else {
            throw SMCError.typeMismatch(key: key, expected: "ui8 ", actual: "0 byte")
        }
        return value
    }

    func writeFloat(_ key: String, _ value: Float) throws {
        try requireType(key, "flt ")
        try writeBytes(key, withUnsafeBytes(of: value) { Array($0) })
    }

    func writeUInt8(_ key: String, _ value: UInt8) throws {
        try requireType(key, "ui8 ")
        try writeBytes(key, [value])
    }

    private func requireType(_ key: String, _ expected: String) throws {
        let actual = try keyInfo(key).type
        guard actual == expected else { throw SMCError.typeMismatch(key: key, expected: expected, actual: actual) }
    }
}
```

`Sources/FanCore/AppleSMC.swift`:
```swift
import Foundation
import IOKit

/// Layout khớp struct C `SMCParamStruct` (80 byte) của driver AppleSMC.
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    // dataSize, dataType, dataAttributes + 3 byte đệm: Swift không tự đệm cuối tuple như C
    var keyInfo: (UInt32, UInt32, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0)
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// SMC thật qua IOKit. Đọc không cần root; ghi cần root.
public final class AppleSMC: SMCDevice {
    private enum Command: UInt8 {
        case readBytes = 5
        case writeBytes = 6
        case readIndex = 8
        case readKeyInfo = 9
    }

    private static let kernelIndex: UInt32 = 2
    private static let keyNotFoundResult: UInt8 = 132
    private var connection: io_connect_t = 0

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.openFailed }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            throw SMCError.openFailed
        }
    }

    deinit {
        IOServiceClose(connection)
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = Command.readKeyInfo.rawValue
        let output = try call(&input, key: key)
        return SMCKeyInfo(size: output.keyInfo.0, type: fourCCString(output.keyInfo.1))
    }

    public func readBytes(_ key: String) throws -> [UInt8] {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.0 = info.size
        input.data8 = Command.readBytes.rawValue
        let output = try call(&input, key: key)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.size))) }
    }

    public func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        guard bytes.count == Int(info.size) else {
            throw SMCError.typeMismatch(key: key, expected: "\(info.size) byte", actual: "\(bytes.count) byte")
        }
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.0 = info.size
        input.data8 = Command.writeBytes.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (offset, byte) in bytes.enumerated() { buffer[offset] = byte }
        }
        _ = try call(&input, key: key)
    }

    public func allKeys() throws -> [String] {
        // #KEY là ui32 big-endian
        let count = try readBytes("#KEY").reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return try (0..<count).map { index in
            var input = SMCParamStruct()
            input.data8 = Command.readIndex.rawValue
            input.data32 = index
            return fourCCString(try call(&input, key: "#\(index)").key)
        }
    }

    private func call(_ input: inout SMCParamStruct, key: String) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.kernelIndex, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(key, result) }
        guard output.result == 0 else {
            throw output.result == Self.keyNotFoundResult
                ? SMCError.keyNotFound(key)
                : SMCError.callFailed(key, Int32(output.result))
        }
        return output
    }
}
```

- [ ] **Step 5: Chạy test để xác nhận đạt (kể cả test phần cứng thật)**

Run: `swift test --filter SMCTests`
Expected: 5 test pass, `readsRealSMC` bị skip.

Run: `FANCTL_HW=1 swift test --filter readsRealSMC`
Expected: `readsRealSMC` pass (chỉ đọc SMC, không cần root).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/FanCore Tests/FanCoreTests
git commit -m "feat: add SMC access layer with IOKit and mock" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: FanService và SensorService

**Files:**
- Create: `Sources/FanCore/Fans.swift`, `Sources/FanCore/Sensors.swift`
- Test: `Tests/FanCoreTests/FanServiceTests.swift`, `Tests/FanCoreTests/SensorServiceTests.swift`

**Interfaces:**
- Consumes: `SMCDevice` cùng extension `readFloat/readUInt8/writeFloat/writeUInt8`, `MockSMC.m1Pro()` (Task 3).
- Produces:
  - `public struct FanInfo: Equatable, Sendable { let index: Int; let minRPM: Double; let maxRPM: Double; init(index:minRPM:maxRPM:); func rpm(forPercent: Double) -> Double }`
  - `public enum FanCommand: Equatable, Sendable { case auto; case manual(rpm: Double) }`
  - `public final class FanService { init(smc: SMCDevice); func discoverFans() throws -> [FanInfo]; func currentRPM(_ index: Int) throws -> Double; func isManual(_ index: Int) throws -> Bool; func apply(_ command: FanCommand, to fan: FanInfo) throws }`
  - `public enum SensorError: Error, Equatable { case noValidReading }`
  - `public final class SensorService { static let validRange: ClosedRange<Double>; let keys: [String]; init(smc: SMCDevice) throws; func readMaxTemperature() throws -> Double }`

- [ ] **Step 1: Viết test thất bại**

`Tests/FanCoreTests/FanServiceTests.swift`:
```swift
import Testing
@testable import FanCore

struct FanServiceTests {
    @Test func discoversBothFans() throws {
        let fans = try FanService(smc: MockSMC.m1Pro()).discoverFans()
        #expect(fans == [
            FanInfo(index: 0, minRPM: 1200, maxRPM: 5779),
            FanInfo(index: 1, minRPM: 1200, maxRPM: 6241),
        ])
    }

    @Test func percentMapsToRPMAndClamps() {
        let fan = FanInfo(index: 0, minRPM: 1200, maxRPM: 5779)
        #expect(fan.rpm(forPercent: 50) == 3489.5)
        #expect(fan.rpm(forPercent: -10) == 1200)
        #expect(fan.rpm(forPercent: 150) == 5779)
    }

    @Test func manualCommandSetsModeAndTarget() throws {
        let smc = MockSMC.m1Pro()
        let fan = FanInfo(index: 1, minRPM: 1200, maxRPM: 6241)
        try FanService(smc: smc).apply(.manual(rpm: 3000), to: fan)
        #expect(smc.uint8("F1Md") == 1)
        #expect(smc.float("F1Tg") == 3000)
    }

    @Test func manualCommandIsClampedToFanRange() throws {
        let smc = MockSMC.m1Pro()
        let fan = FanInfo(index: 0, minRPM: 1200, maxRPM: 5779)
        try FanService(smc: smc).apply(.manual(rpm: 9999), to: fan)
        #expect(smc.float("F0Tg") == 5779)
        try FanService(smc: smc).apply(.manual(rpm: 10), to: fan)
        #expect(smc.float("F0Tg") == 1200)
    }

    @Test func autoCommandClearsManualMode() throws {
        let smc = MockSMC.m1Pro()
        smc.setUInt8("F0Md", 1)
        try FanService(smc: smc).apply(.auto, to: FanInfo(index: 0, minRPM: 1200, maxRPM: 5779))
        #expect(smc.uint8("F0Md") == 0)
    }

    @Test func readsCurrentRPMAndMode() throws {
        let smc = MockSMC.m1Pro()
        smc.setFloat("F0Ac", 2450)
        smc.setUInt8("F0Md", 1)
        let service = FanService(smc: smc)
        #expect(try service.currentRPM(0) == 2450)
        #expect(try service.isManual(0))
        #expect(try !service.isManual(1))
    }
}
```

`Tests/FanCoreTests/SensorServiceTests.swift`:
```swift
import Testing
@testable import FanCore

struct SensorServiceTests {
    @Test func discoversOnlyFloatCPUAndGPUKeys() throws {
        let sensors = try SensorService(smc: MockSMC.m1Pro())
        #expect(sensors.keys == ["Te05", "Tg05", "Tp01"])
    }

    @Test func returnsMaximumTemperature() throws {
        let smc = MockSMC.m1Pro()
        smc.setFloat("Tg05", 61.5)
        #expect(try SensorService(smc: smc).readMaxTemperature() == 61.5)
    }

    @Test func ignoresOutOfRangeValues() throws {
        let smc = MockSMC.m1Pro()
        smc.setFloat("Tg05", 200)
        smc.setFloat("Te05", -5)
        #expect(try SensorService(smc: smc).readMaxTemperature() == 50)
    }

    @Test func ignoresFailingSensors() throws {
        let smc = MockSMC.m1Pro()
        let sensors = try SensorService(smc: smc)
        smc.failingReads = ["Tp01"]
        #expect(try sensors.readMaxTemperature() == 48)
    }

    @Test func throwsWhenNoValidReading() throws {
        let smc = MockSMC.m1Pro()
        let sensors = try SensorService(smc: smc)
        smc.failingReads = ["Tp01", "Te05", "Tg05"]
        #expect(throws: SensorError.noValidReading) { try sensors.readMaxTemperature() }
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter "FanServiceTests|SensorServiceTests"`
Expected: build lỗi vì không tìm thấy `FanService`, `FanInfo`, `SensorService`.

- [ ] **Step 3: Viết implementation**

`Sources/FanCore/Fans.swift`:
```swift
import Foundation

public struct FanInfo: Equatable, Sendable {
    public let index: Int
    public let minRPM: Double
    public let maxRPM: Double

    public init(index: Int, minRPM: Double, maxRPM: Double) {
        self.index = index
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    /// % (0–100) → RPM, kẹp trong [min, max].
    public func rpm(forPercent percent: Double) -> Double {
        let clamped = min(max(percent, 0), 100)
        return minRPM + clamped / 100 * (maxRPM - minRPM)
    }
}

public enum FanCommand: Equatable, Sendable {
    case auto
    case manual(rpm: Double)
}

/// Đọc/ghi quạt qua các key SMC: FNum, FxMn, FxMx, FxAc, FxMd (0 = Apple, 1 = manual), FxTg.
public final class FanService {
    private let smc: SMCDevice

    public init(smc: SMCDevice) {
        self.smc = smc
    }

    public func discoverFans() throws -> [FanInfo] {
        let count = Int(try smc.readUInt8("FNum"))
        return try (0..<count).map { index in
            FanInfo(index: index,
                    minRPM: Double(try smc.readFloat("F\(index)Mn")),
                    maxRPM: Double(try smc.readFloat("F\(index)Mx")))
        }
    }

    public func currentRPM(_ index: Int) throws -> Double {
        Double(try smc.readFloat("F\(index)Ac"))
    }

    public func isManual(_ index: Int) throws -> Bool {
        try smc.readUInt8("F\(index)Md") != 0
    }

    public func apply(_ command: FanCommand, to fan: FanInfo) throws {
        switch command {
        case .auto:
            try smc.writeUInt8("F\(fan.index)Md", 0)
        case .manual(let rpm):
            try smc.writeUInt8("F\(fan.index)Md", 1)
            try smc.writeFloat("F\(fan.index)Tg", Float(min(max(rpm, fan.minRPM), fan.maxRPM)))
        }
    }
}
```

`Sources/FanCore/Sensors.swift`:
```swift
import Foundation

public enum SensorError: Error, Equatable {
    case noValidReading
}

/// Nhiệt độ cao nhất giữa CPU (Tp*, Te*) và GPU (Tg*).
public final class SensorService {
    public static let validRange: ClosedRange<Double> = 0...130

    private let smc: SMCDevice
    public let keys: [String]

    public init(smc: SMCDevice) throws {
        self.smc = smc
        keys = try smc.allKeys().filter { key in
            guard ["Tp", "Te", "Tg"].contains(where: { key.hasPrefix($0) }) else { return false }
            return (try? smc.keyInfo(key).type) == "flt "
        }
    }

    public func readMaxTemperature() throws -> Double {
        let values = keys
            .compactMap { try? Double(smc.readFloat($0)) }
            .filter { Self.validRange.contains($0) }
        guard let maximum = values.max() else { throw SensorError.noValidReading }
        return maximum
    }
}
```

- [ ] **Step 4: Chạy test để xác nhận đạt**

Run: `swift test --filter "FanServiceTests|SensorServiceTests"`
Expected: 11 test pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FanCore/Fans.swift Sources/FanCore/Sensors.swift Tests/FanCoreTests/FanServiceTests.swift Tests/FanCoreTests/SensorServiceTests.swift
git commit -m "feat: add fan and temperature sensor services" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Controller (máy trạng thái điều khiển)

**Files:**
- Create: `Sources/FanCore/Controller.swift`
- Test: `Tests/FanCoreTests/ControllerTests.swift`

**Interfaces:**
- Consumes: `FanInfo`, `FanCommand` (Task 4); `Preset`, `PresetKind`, `FanCurve` (Task 1–2).
- Produces:
  - `public struct ControllerSettings: Sendable { emaAlpha, safetyOn, safetyOff, autoHysteresis, maxDecreasePerTick, writeThreshold: Double; maxConsecutiveFailures: Int; init(... defaults 0.3, 95, 90, 3, 300, 50, 3) }`
  - `public struct ControlOutput: Equatable { var commands: [Int: FanCommand]; var smoothedTemperature: Double?; var safetyActive: Bool; var error: String? }`
  - `public final class Controller { let fans: [FanInfo]; static let sensorErrorMessage: String; static let writeErrorMessage: String; init(fans:settings:); func step(reading: Double?, preset: Preset) -> ControlOutput; func commit(_ command: FanCommand, fan: Int, success: Bool); func markNeedsRewrite() }`

Quy ước: `reading == nil` nghĩa là đọc cảm biến lỗi. `step` chỉ trả về lệnh cho những quạt **cần ghi**. Bên gọi phải báo kết quả từng lệnh qua `commit` thì Controller mới biết trạng thái thật của quạt.

- [ ] **Step 1: Viết test thất bại**

`Tests/FanCoreTests/ControllerTests.swift`:
```swift
import Testing
import Shared
@testable import FanCore

struct ControllerTests {
    let fans = [
        FanInfo(index: 0, minRPM: 1200, maxRPM: 5779),
        FanInfo(index: 1, minRPM: 1200, maxRPM: 6241),
    ]
    let balanced = Preset.balanced
    let autoPreset = Preset.builtIns.first { $0.id == Preset.autoID }!
    let maxPreset = Preset.builtIns.first { $0.id == Preset.maxID }!

    /// α = 1 để tắt làm mượt, giúp test dễ tính.
    func makeController() -> Controller {
        Controller(fans: fans, settings: ControllerSettings(emaAlpha: 1))
    }

    /// Một bước điều khiển, giả lập daemon ghi thành công mọi lệnh.
    @discardableResult
    func run(_ controller: Controller, _ temp: Double?, _ preset: Preset) -> ControlOutput {
        let output = controller.step(reading: temp, preset: preset)
        for (fan, command) in output.commands { controller.commit(command, fan: fan, success: true) }
        return output
    }

    @Test func autoPresetReleasesFansOnce() {
        let c = makeController()
        #expect(run(c, 60, autoPreset).commands == [0: .auto, 1: .auto])
        #expect(run(c, 60, autoPreset).commands == [:])
    }

    @Test func curveInterpolatesToPerFanRPM() {
        let c = makeController()
        #expect(run(c, 70, balanced).commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
    }

    @Test func belowFirstPointWithoutEngagingIsAuto() {
        let c = makeController()
        #expect(run(c, 50, balanced).commands == [0: .auto, 1: .auto])
    }

    @Test func hysteresisHoldsFirstPointBeforeReleasing() {
        let c = makeController()
        #expect(run(c, 55, balanced).commands == [0: .manual(rpm: 1200), 1: .manual(rpm: 1200)])
        #expect(run(c, 53, balanced).commands == [:])
        #expect(run(c, 51.9, balanced).commands == [0: .auto, 1: .auto])
    }

    @Test func rampsDownAtMost300PerTick() {
        let c = makeController()
        run(c, 85, balanced)
        #expect(run(c, 55, balanced).commands == [0: .manual(rpm: 5479), 1: .manual(rpm: 5941)])
    }

    @Test func rampsUpImmediately() {
        let c = makeController()
        run(c, 55, balanced)
        #expect(run(c, 85, balanced).commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
    }

    @Test func skipsChangesOf50RPMOrLess() {
        let c = makeController()
        run(c, 70, balanced)
        #expect(run(c, 70.2, balanced).commands == [:])
    }

    @Test func safetyForcesMaxEvenInAutoModeWithHysteresis() {
        let c = makeController()
        let hot = run(c, 96, autoPreset)
        #expect(hot.commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
        #expect(hot.safetyActive)

        let cooling = run(c, 92, autoPreset)
        #expect(cooling.safetyActive)
        #expect(cooling.commands == [:])

        let cool = run(c, 89, autoPreset)
        #expect(!cool.safetyActive)
        #expect(cool.commands == [0: .auto, 1: .auto])
    }

    @Test func smoothsWithEMA() {
        let c = Controller(fans: fans)
        #expect(c.step(reading: 60, preset: balanced).smoothedTemperature == 60)
        let second = c.step(reading: 70, preset: balanced).smoothedTemperature!
        #expect(abs(second - 63) < 1e-9)
    }

    @Test func safetyUsesRawTemperatureNotSmoothed() {
        let c = Controller(fans: fans)
        run(c, 60, balanced)
        let output = run(c, 96, balanced)
        #expect(output.smoothedTemperature! < 95)
        #expect(output.safetyActive)
        #expect(output.commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
    }

    @Test func threeReadFailuresReleaseToAuto() {
        let c = makeController()
        run(c, 70, balanced)
        let first = run(c, nil, balanced)
        #expect(first.commands == [:])
        #expect(first.error == nil)
        run(c, nil, balanced)
        let third = run(c, nil, balanced)
        #expect(third.commands == [0: .auto, 1: .auto])
        #expect(third.error == Controller.sensorErrorMessage)

        let recovered = run(c, 70, balanced)
        #expect(recovered.error == nil)
        #expect(recovered.commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
    }

    @Test func failedWritesAreRetriedThenReleaseToAuto() {
        let c = makeController()
        let first = c.step(reading: 70, preset: balanced)
        for (fan, command) in first.commands { c.commit(command, fan: fan, success: false) }

        let retry = c.step(reading: 70, preset: balanced)
        #expect(retry.commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
        #expect(retry.error == nil)
        c.commit(.manual(rpm: 3489.5), fan: 0, success: false)

        let giveUp = c.step(reading: 70, preset: balanced)
        #expect(giveUp.error == Controller.writeErrorMessage)
        #expect(giveUp.commands == [0: .auto, 1: .auto])
    }

    @Test func maxPresetRunsFullSpeed() {
        let c = makeController()
        #expect(run(c, 40, maxPreset).commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
    }

    @Test func markNeedsRewriteResendsUnchangedCommandsOnce() {
        let c = makeController()
        run(c, 70, balanced)
        c.markNeedsRewrite()
        #expect(run(c, 70, balanced).commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
        #expect(run(c, 70, balanced).commands == [:])
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter ControllerTests`
Expected: build lỗi vì không tìm thấy `Controller`, `ControllerSettings`.

- [ ] **Step 3: Viết implementation**

`Sources/FanCore/Controller.swift`:
```swift
import Foundation
import Shared

public struct ControllerSettings: Sendable {
    public var emaAlpha: Double
    public var safetyOn: Double
    public var safetyOff: Double
    public var autoHysteresis: Double
    public var maxDecreasePerTick: Double
    public var writeThreshold: Double
    public var maxConsecutiveFailures: Int

    public init(emaAlpha: Double = 0.3, safetyOn: Double = 95, safetyOff: Double = 90, autoHysteresis: Double = 3,
                maxDecreasePerTick: Double = 300, writeThreshold: Double = 50, maxConsecutiveFailures: Int = 3) {
        self.emaAlpha = emaAlpha
        self.safetyOn = safetyOn
        self.safetyOff = safetyOff
        self.autoHysteresis = autoHysteresis
        self.maxDecreasePerTick = maxDecreasePerTick
        self.writeThreshold = writeThreshold
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }
}

public struct ControlOutput: Equatable {
    /// Chỉ gồm các quạt cần ghi ở chu kỳ này.
    public var commands: [Int: FanCommand]
    public var smoothedTemperature: Double?
    public var safetyActive: Bool
    public var error: String?
}

/// Máy trạng thái thuần: nhận nhiệt độ + chế độ, trả về lệnh cho từng quạt. Không làm I/O.
public final class Controller {
    public static let sensorErrorMessage = "Không đọc được cảm biến nhiệt độ"
    public static let writeErrorMessage = "Không ghi được tốc độ quạt"

    public let fans: [FanInfo]
    private let settings: ControllerSettings
    private var smoothed: Double?
    private var safetyActive = false
    private var curveEngaged = false
    private var readFailures = 0
    private var writeFailures = 0
    private var lastWritten: [Int: FanCommand] = [:]
    private var forceRewrite = false

    public init(fans: [FanInfo], settings: ControllerSettings = ControllerSettings()) {
        self.fans = fans
        self.settings = settings
    }

    /// `reading == nil` nghĩa là đọc cảm biến lỗi.
    public func step(reading: Double?, preset: Preset) -> ControlOutput {
        var desired: [Int: FanCommand]
        var error: String?

        if let raw = reading {
            readFailures = 0
            let temp = smoothed.map { settings.emaAlpha * raw + (1 - settings.emaAlpha) * $0 } ?? raw
            smoothed = temp
            // Ngưỡng an toàn dùng giá trị thô để phản ứng ngay
            if raw >= settings.safetyOn {
                safetyActive = true
            } else if raw < settings.safetyOff {
                safetyActive = false
            }
            desired = desiredCommands(preset: preset, temp: temp)
        } else {
            readFailures += 1
            if readFailures < settings.maxConsecutiveFailures {
                return ControlOutput(commands: [:], smoothedTemperature: smoothed, safetyActive: safetyActive, error: nil)
            }
            error = Self.sensorErrorMessage
            safetyActive = false
            curveEngaged = false
            desired = allAuto()
        }

        if writeFailures >= settings.maxConsecutiveFailures {
            error = Self.writeErrorMessage
            curveEngaged = false
            desired = allAuto()
        }

        let commands = desired.filter { needsWrite($0.value, previous: lastWritten[$0.key]) }
        forceRewrite = false
        return ControlOutput(commands: commands, smoothedTemperature: smoothed, safetyActive: safetyActive, error: error)
    }

    /// Bên gọi báo kết quả ghi từng lệnh. Ghi lỗi thì lần sau ghi lại.
    public func commit(_ command: FanCommand, fan: Int, success: Bool) {
        if success {
            lastWritten[fan] = command
            writeFailures = 0
        } else {
            lastWritten[fan] = nil
            writeFailures += 1
        }
    }

    /// Sau khi máy thức dậy SMC có thể đã reset: chu kỳ sau ghi lại toàn bộ.
    public func markNeedsRewrite() {
        forceRewrite = true
    }

    private func desiredCommands(preset: Preset, temp: Double) -> [Int: FanCommand] {
        if safetyActive { return percentCommands(100) }
        switch preset.kind {
        case .auto:
            curveEngaged = false
            return allAuto()
        case .max:
            curveEngaged = false
            return percentCommands(100)
        case .curve:
            if let percent = preset.curve.percent(at: temp) {
                curveEngaged = true
                return percentCommands(percent)
            }
            // Dưới điểm đầu: chỉ trả về Apple khi đã thấp hơn điểm đầu đủ hysteresis
            if curveEngaged, let first = preset.curve.points.first, temp >= first.temp - settings.autoHysteresis {
                return percentCommands(first.percent)
            }
            curveEngaged = false
            return allAuto()
        }
    }

    /// Tăng ngay, giảm tối đa `maxDecreasePerTick` mỗi chu kỳ so với lần ghi trước.
    private func percentCommands(_ percent: Double) -> [Int: FanCommand] {
        Dictionary(uniqueKeysWithValues: fans.map { fan in
            var rpm = fan.rpm(forPercent: percent)
            if case .manual(let previous)? = lastWritten[fan.index], rpm < previous {
                rpm = max(rpm, previous - settings.maxDecreasePerTick)
            }
            return (fan.index, FanCommand.manual(rpm: rpm))
        })
    }

    private func allAuto() -> [Int: FanCommand] {
        Dictionary(uniqueKeysWithValues: fans.map { ($0.index, FanCommand.auto) })
    }

    private func needsWrite(_ command: FanCommand, previous: FanCommand?) -> Bool {
        if forceRewrite { return true }
        switch (previous, command) {
        case (nil, _):
            return true
        case (.auto?, .auto):
            return false
        case let (.manual(old)?, .manual(new)):
            return abs(new - old) > settings.writeThreshold
        default:
            return true
        }
    }
}
```

- [ ] **Step 4: Chạy test để xác nhận đạt**

Run: `swift test --filter ControllerTests`
Expected: 14 test pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FanCore/Controller.swift Tests/FanCoreTests/ControllerTests.swift
git commit -m "feat: add fan controller state machine" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: ConfigStore và ControlLoop

**Files:**
- Create: `Sources/FanCore/ConfigStore.swift`, `Sources/FanCore/ControlLoop.swift`
- Test: `Tests/FanCoreTests/ConfigStoreTests.swift`, `Tests/FanCoreTests/ControlLoopTests.swift`

**Interfaces:**
- Consumes: `Config`, `Status`, `FanStatus` (Task 2); `SMCDevice`, `MockSMC` (Task 3); `FanService`, `SensorService`, `FanInfo`, `FanCommand` (Task 4); `Controller`, `ControllerSettings`, `ControlOutput` (Task 5).
- Produces:
  - `public final class ConfigStore { let url: URL; private(set) var config: Config; init(url: URL); func update(_ mutate: (inout Config) throws -> Void) throws }`
  - `public final class ControlLoop { private(set) var status: Status; init(smc: SMCDevice, store: ConfigStore, dryRun: Bool = false, settings: ControllerSettings = ControllerSettings(), log: @escaping (String) -> Void = { print($0) }) throws; func start(); func tick(); func releaseAll(); func markWake() }`

`ControlLoop` không tự lập lịch: daemon gọi `tick()` mỗi 2 giây trên một queue nối tiếp, và mọi thao tác XPC cũng chạy trên queue đó.

- [ ] **Step 1: Viết test thất bại**

`Tests/FanCoreTests/ConfigStoreTests.swift`:
```swift
import Foundation
import Testing
import Shared
@testable import FanCore

struct ConfigStoreTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json")

    @Test func missingFileCreatesDefault() throws {
        let store = ConfigStore(url: url)
        #expect(store.config == .default)
        let saved = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        #expect(saved == .default)
    }

    @Test func corruptFileIsReplacedWithDefault() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("không phải json".utf8).write(to: url)
        let store = ConfigStore(url: url)
        #expect(store.config == .default)
        #expect(try JSONDecoder().decode(Config.self, from: Data(contentsOf: url)) == .default)
    }

    @Test func updatePersistsAcrossInstances() throws {
        try ConfigStore(url: url).update { try $0.setActive(Preset.maxID) }
        #expect(ConfigStore(url: url).config.activePresetID == Preset.maxID)
    }

    @Test func failedUpdateLeavesConfigUnchanged() throws {
        let store = ConfigStore(url: url)
        #expect(throws: Config.EditError.unknownPreset) { try store.update { try $0.setActive("nope") } }
        #expect(store.config == .default)
        #expect(ConfigStore(url: url).config == .default)
    }
}
```

`Tests/FanCoreTests/ControlLoopTests.swift`:
```swift
import Foundation
import Testing
import Shared
@testable import FanCore

struct ControlLoopTests {
    let smc = MockSMC.m1Pro()
    let store = ConfigStore(url: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json"))

    func makeLoop(dryRun: Bool = false) throws -> ControlLoop {
        try ControlLoop(smc: smc, store: store, dryRun: dryRun, log: { _ in })
    }

    @Test func startReleasesAllFans() throws {
        smc.setUInt8("F0Md", 1)
        smc.setUInt8("F1Md", 1)
        try makeLoop().start()
        #expect(smc.uint8("F0Md") == 0)
        #expect(smc.uint8("F1Md") == 0)
    }

    @Test func tickAppliesBalancedCurve() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        #expect(smc.uint8("F0Md") == 1)
        #expect(smc.float("F0Tg") == 3489.5)
        #expect(smc.float("F1Tg") == 3720.5)
    }

    @Test func tickUpdatesStatus() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        smc.setFloat("F0Ac", 3400)
        loop.tick()
        #expect(loop.status.temperature == 70)
        #expect(loop.status.fans.map(\.rpm) == [3400, 0])
        #expect(loop.status.fans[0].manual)
        #expect(loop.status.activePresetID == Preset.balancedID)
        #expect(loop.status.presets.count == 5)
        #expect(loop.status.error == nil)
    }

    @Test func dryRunNeverWrites() throws {
        let loop = try makeLoop(dryRun: true)
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        #expect(smc.writes.isEmpty)
    }

    @Test func releaseAllReturnsFansToApple() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        loop.releaseAll()
        #expect(smc.uint8("F0Md") == 0)
        #expect(smc.uint8("F1Md") == 0)
    }

    @Test func followsActivePresetFromStore() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        try store.update { try $0.setActive(Preset.autoID) }
        loop.tick()
        #expect(smc.uint8("F0Md") == 0)
        #expect(loop.status.activePresetID == Preset.autoID)
    }

    @Test func repeatedWriteFailuresSurfaceError() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        smc.failWrites = true
        loop.tick()
        loop.tick()
        loop.tick()
        #expect(loop.status.error == Controller.writeErrorMessage)
    }

    @Test func repeatedSensorFailuresReleaseFans() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        smc.failingReads = ["Tp01", "Te05", "Tg05"]
        loop.tick()
        loop.tick()
        loop.tick()
        #expect(loop.status.error == Controller.sensorErrorMessage)
        #expect(smc.uint8("F0Md") == 0)
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter "ConfigStoreTests|ControlLoopTests"`
Expected: build lỗi vì không tìm thấy `ConfigStore`, `ControlLoop`.

- [ ] **Step 3: Viết implementation**

`Sources/FanCore/ConfigStore.swift`:
```swift
import Foundation
import Shared

/// Đọc/ghi config.json. File thiếu hoặc hỏng → dùng mặc định và ghi đè.
public final class ConfigStore {
    public let url: URL
    public private(set) var config: Config

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = .default
            try? save()
        }
    }

    /// Chỉ giữ thay đổi và lưu khi `mutate` không ném lỗi.
    public func update(_ mutate: (inout Config) throws -> Void) throws {
        var copy = config
        try mutate(&copy)
        config = copy
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
```

`Sources/FanCore/ControlLoop.swift`:
```swift
import Foundation
import Shared

/// Ghép SMC + cảm biến + Controller + cấu hình. Không tự lập lịch:
/// daemon gọi `tick()` mỗi 2 giây trên một queue nối tiếp.
public final class ControlLoop {
    private let fanService: FanService
    private let sensors: SensorService
    private let controller: Controller
    private let store: ConfigStore
    private let dryRun: Bool
    private let log: (String) -> Void
    public private(set) var status: Status

    public init(smc: SMCDevice, store: ConfigStore, dryRun: Bool = false,
                settings: ControllerSettings = ControllerSettings(),
                log: @escaping (String) -> Void = { print($0) }) throws {
        let fanService = FanService(smc: smc)
        let fans = try fanService.discoverFans()
        self.fanService = fanService
        self.sensors = try SensorService(smc: smc)
        self.controller = Controller(fans: fans, settings: settings)
        self.store = store
        self.dryRun = dryRun
        self.log = log
        self.status = Status(
            temperature: nil,
            fans: fans.map { FanStatus(index: $0.index, rpm: 0, minRPM: $0.minRPM, maxRPM: $0.maxRPM, manual: false) },
            activePresetID: store.config.activePresetID,
            presets: store.config.allPresets,
            safetyActive: false,
            error: nil)
        log("Tìm thấy \(fans.count) quạt, \(sensors.keys.count) cảm biến nhiệt")
    }

    /// Khởi động: trả mọi quạt về Apple trước khi bắt đầu điều khiển.
    public func start() {
        releaseAll()
    }

    /// Trả mọi quạt về Apple (khi thoát hoặc gỡ cài đặt).
    public func releaseAll() {
        for fan in controller.fans { apply(.auto, to: fan) }
    }

    public func markWake() {
        controller.markNeedsRewrite()
    }

    public func tick() {
        let reading = try? sensors.readMaxTemperature()
        let output = controller.step(reading: reading, preset: store.config.activePreset)
        for fan in controller.fans {
            if let command = output.commands[fan.index] { apply(command, to: fan) }
        }
        refreshStatus(output)
    }

    private func apply(_ command: FanCommand, to fan: FanInfo) {
        if dryRun {
            log("[dry-run] quạt \(fan.index): \(command)")
            controller.commit(command, fan: fan.index, success: true)
            return
        }
        do {
            try fanService.apply(command, to: fan)
            controller.commit(command, fan: fan.index, success: true)
        } catch {
            log("Lỗi ghi quạt \(fan.index): \(error)")
            controller.commit(command, fan: fan.index, success: false)
        }
    }

    private func refreshStatus(_ output: ControlOutput) {
        status.temperature = output.smoothedTemperature
        status.safetyActive = output.safetyActive
        status.error = output.error
        status.activePresetID = store.config.activePresetID
        status.presets = store.config.allPresets
        status.fans = controller.fans.map { fan in
            FanStatus(index: fan.index,
                      rpm: (try? fanService.currentRPM(fan.index)) ?? 0,
                      minRPM: fan.minRPM,
                      maxRPM: fan.maxRPM,
                      manual: (try? fanService.isManual(fan.index)) ?? false)
        }
    }
}
```

- [ ] **Step 4: Chạy toàn bộ test**

Run: `swift test`
Expected: mọi test pass (riêng `readsRealSMC` bị skip).

- [ ] **Step 5: Commit**

```bash
git add Sources/FanCore/ConfigStore.swift Sources/FanCore/ControlLoop.swift Tests/FanCoreTests/ConfigStoreTests.swift Tests/FanCoreTests/ControlLoopTests.swift
git commit -m "feat: add config store and control loop" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Daemon `fanctld`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/fanctld/main.swift`, `Sources/fanctld/DaemonService.swift`, `Sources/fanctld/PowerMonitor.swift`, `Resources/local.fancontrol.daemon.plist`

**Interfaces:**
- Consumes: `AppleSMC`, `FanService`, `SensorService`, `ConfigStore`, `ControlLoop` (Task 3–6); `Config`, `Preset`, `FanDaemonProtocol`, `XPCConstants` (Task 2).
- Produces: executable `fanctld` với các cờ:
  - `--probe`: in thông tin quạt/nhiệt độ rồi thoát, không cần root.
  - `--dry-run`: chạy vòng điều khiển, chỉ log lệnh, không ghi SMC và không mở XPC.
  - `--config <path>`: đường dẫn cấu hình, mặc định `/Library/Application Support/FanControl/config.json`.
  - launchd plist dùng cho Task 8.

Không có unit test riêng: phần này chỉ là glue mỏng, logic đã được test ở Task 3–6. Kiểm chứng bằng `--probe` và `--dry-run` trên máy thật.

- [ ] **Step 1: Cập nhật `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .target(name: "FanCore", dependencies: ["Shared"]),
        .executableTarget(name: "fanctld", dependencies: ["FanCore", "Shared"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore", "Shared"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Viết `PowerMonitor.swift`**

`Sources/fanctld/PowerMonitor.swift`:
```swift
import Foundation
import IOKit
import IOKit.pwr_mgt

/// Báo khi máy thức dậy. Các hằng kIOMessage* là macro C nên Swift không import được:
/// iokit_common_msg(x) = 0xE0000000 | x.
final class PowerMonitor {
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    private let onWake: () -> Void
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init(queue: DispatchQueue, onWake: @escaping () -> Void) {
        self.onWake = onWake
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            Unmanaged<PowerMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(messageType, messageArgument)
        }, &notifier)
        if let notifyPort { IONotificationPortSetDispatchQueue(notifyPort, queue) }
    }

    private func handle(_ messageType: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case Self.canSystemSleep, Self.systemWillSleep:
            // Phải trả lời, nếu không macOS chờ 30 giây mới ngủ
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.systemHasPoweredOn:
            onWake()
        default:
            break
        }
    }
}
```

- [ ] **Step 3: Viết `DaemonService.swift`**

`Sources/fanctld/DaemonService.swift`:
```swift
import Foundation
import FanCore
import Shared

/// Đối tượng XPC. Mọi thao tác chạy trên queue của vòng điều khiển để không đua với `tick()`.
final class DaemonService: NSObject, NSXPCListenerDelegate, FanDaemonProtocol {
    private let queue: DispatchQueue
    private let loop: ControlLoop
    private let store: ConfigStore
    private let log: (String) -> Void

    init(queue: DispatchQueue, loop: ControlLoop, store: ConfigStore, log: @escaping (String) -> Void) {
        self.queue = queue
        self.loop = loop
        self.store = store
        self.log = log
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanDaemonProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func getStatus(reply: @escaping (Data) -> Void) {
        queue.async {
            reply((try? JSONEncoder().encode(self.loop.status)) ?? Data())
        }
    }

    func setMode(_ presetID: String, reply: @escaping (String?) -> Void) {
        edit(reply) { try $0.setActive(presetID) }
    }

    func savePreset(_ presetJSON: Data, reply: @escaping (String?) -> Void) {
        guard let preset = try? JSONDecoder().decode(Preset.self, from: presetJSON) else {
            reply("Dữ liệu chế độ không hợp lệ")
            return
        }
        edit(reply) { try $0.upsert(preset) }
    }

    func deletePreset(_ presetID: String, reply: @escaping (String?) -> Void) {
        edit(reply) { try $0.delete(presetID) }
    }

    private func edit(_ reply: @escaping (String?) -> Void, _ mutate: @escaping (inout Config) throws -> Void) {
        queue.async {
            do {
                try self.store.update(mutate)
                self.loop.tick() // áp dụng ngay, không đợi chu kỳ sau
                reply(nil)
            } catch let error as Config.EditError {
                reply(error.message)
            } catch {
                self.log("Lỗi lưu cấu hình: \(error)")
                reply("Không lưu được cấu hình")
            }
        }
    }
}
```

- [ ] **Step 4: Viết `main.swift`**

`Sources/fanctld/main.swift`:
```swift
import Foundation
import FanCore
import Shared

setvbuf(stdout, nil, _IOLBF, 0)

func logLine(_ message: String) {
    print("[\(ISO8601DateFormatter().string(from: Date()))] \(message)")
}

let arguments = CommandLine.arguments
let dryRun = arguments.contains("--dry-run")
let configPath = arguments.firstIndex(of: "--config").flatMap { index in
    index + 1 < arguments.count ? arguments[index + 1] : nil
} ?? "/Library/Application Support/FanControl/config.json"

let smc: AppleSMC
do {
    smc = try AppleSMC()
} catch {
    logLine("Không mở được AppleSMC: \(error)")
    exit(1)
}

if arguments.contains("--probe") {
    // In thông tin quạt và nhiệt độ rồi thoát (không cần root)
    let fanService = FanService(smc: smc)
    for fan in try fanService.discoverFans() {
        let mode = try fanService.isManual(fan.index) ? "manual" : "Apple"
        let rpm = Int(try fanService.currentRPM(fan.index))
        print("Quạt \(fan.index): \(Int(fan.minRPM))–\(Int(fan.maxRPM)) vòng/phút, hiện tại \(rpm), chế độ \(mode)")
    }
    let sensors = try SensorService(smc: smc)
    let maxTemp = try sensors.readMaxTemperature()
    print("\(sensors.keys.count) cảm biến, nhiệt độ cao nhất \(maxTemp)°C")
    exit(0)
}

let store = ConfigStore(url: URL(fileURLWithPath: configPath))
let loop: ControlLoop
do {
    loop = try ControlLoop(smc: smc, store: store, dryRun: dryRun, log: logLine)
} catch {
    logLine("Không khởi tạo được bộ điều khiển: \(error)")
    exit(1)
}

let queue = DispatchQueue(label: "local.fancontrol.daemon.loop")
queue.sync { loop.start() }
logLine("fanctld khởi động\(dryRun ? " (dry-run)" : ""), chế độ: \(store.config.activePreset.name)")

// Thoát êm: trả quạt cho Apple
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
    source.setEventHandler {
        logLine("Nhận tín hiệu \(signalNumber), trả quạt về Apple")
        loop.releaseAll()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now(), repeating: .seconds(2))
timer.setEventHandler { loop.tick() }
timer.resume()

let powerMonitor = PowerMonitor(queue: queue) {
    logLine("Máy thức dậy, ghi lại lệnh quạt")
    loop.markWake()
}

// Dry-run chạy ngoài launchd nên không đăng ký được mach service
let service = DaemonService(queue: queue, loop: loop, store: store, log: logLine)
let listener = NSXPCListener(machServiceName: XPCConstants.machServiceName)
if !dryRun {
    listener.delegate = service
    listener.resume()
}

dispatchMain()
```

- [ ] **Step 5: Viết launchd plist**

`Resources/local.fancontrol.daemon.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.fancontrol.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/fanctld</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>local.fancontrol.daemon</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>/var/log/fanctld.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/fanctld.log</string>
</dict>
</plist>
```

- [ ] **Step 6: Build và kiểm chứng**

Run: `swift build && plutil -lint Resources/local.fancontrol.daemon.plist`
Expected: build thành công; `Resources/local.fancontrol.daemon.plist: OK`.

Run: `.build/debug/fanctld --probe`
Expected (con số thay đổi theo máy): 2 dòng `Quạt 0: 1200–5779 vòng/phút, ...`, `Quạt 1: 1200–6241 vòng/phút, ...`, rồi dòng `~37 cảm biến, nhiệt độ cao nhất XX.X°C`.

Run (không cần root, dùng config tạm):
```bash
rm -f /tmp/fanctl-dry.json; .build/debug/fanctld --dry-run --config /tmp/fanctl-dry.json & p=$!; perl -e 'select(undef,undef,undef,7)'; kill -TERM $p; wait $p
```
Expected:
- `Tìm thấy 2 quạt, N cảm biến nhiệt`
- `[dry-run] quạt 0: auto`, `[dry-run] quạt 1: auto`
- `fanctld khởi động (dry-run), chế độ: Cân bằng`
- Tiếp theo là các dòng `[dry-run] quạt 0: manual(rpm: ...)` nếu nhiệt độ ≥ 55°C (máy mát hơn thì không có dòng nào, vì quạt vẫn ở Auto)
- `Nhận tín hiệu 15, trả quạt về Apple`, sau đó là `[dry-run] quạt 0: auto`, `[dry-run] quạt 1: auto`

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/fanctld Resources/local.fancontrol.daemon.plist
git commit -m "feat: add fanctld daemon with XPC, signals and wake handling" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Đóng gói app + menu bar + popover + tab Chung

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Shared/HelperScripts.swift`, `Makefile`, `Resources/Info.plist`, `Sources/FanControlApp/App.swift`, `Sources/FanControlApp/DaemonClient.swift`, `Sources/FanControlApp/HelperInstaller.swift`, `Sources/FanControlApp/AppModel.swift`, `Sources/FanControlApp/MenuBarLabel.swift`, `Sources/FanControlApp/PopoverView.swift`, `Sources/FanControlApp/SettingsView.swift`, `Sources/FanControlApp/GeneralTab.swift`
- Test: `Tests/SharedTests/HelperScriptsTests.swift`

**Interfaces:**
- Consumes: `Status`, `FanStatus`, `Preset`, `Format`, `FanDaemonProtocol`, `XPCConstants` (Task 2); `Resources/local.fancontrol.daemon.plist` và binary `fanctld` (Task 7).
- Produces:
  - `public enum HelperScripts { static let label, helperPath, plistPath: String; static func install(bundledHelper:bundledPlist:) -> String; static func uninstall() -> String; static func quote(_:) -> String; static func appleScript(running:) -> String }`
  - `@MainActor @Observable final class AppModel { status: Status?; helperInstalled: Bool; connectionError: String?; actionError: String?; launchAtLogin: Bool; presets: [Preset]; isAlert: Bool; func refresh() async; func setMode(_:) async; func savePreset(_:) async -> Bool; func deletePreset(_:) async; func installHelper() async; func uninstallHelper() async; func setLaunchAtLogin(_:) }`
  - `struct SettingsView: View` (Task 9 thêm tab Đường cong), `struct GeneralTab: View`
  - Scene cửa sổ cài đặt id `"settings"`
  - `make app` tạo `build/FanControl.app`; `make install` copy app vào `/Applications`

- [ ] **Step 1: Viết test thất bại cho HelperScripts**

`Tests/SharedTests/HelperScriptsTests.swift`:
```swift
import Testing
@testable import Shared

struct HelperScriptsTests {
    @Test func quotesForShell() {
        #expect(HelperScripts.quote("/a b/c") == "'/a b/c'")
        #expect(HelperScripts.quote("it's") == "'it'\\''s'")
    }

    @Test func installScriptCopiesAndBootstraps() {
        let script = HelperScripts.install(bundledHelper: "/Apps/Fan Control.app/fanctld", bundledPlist: "/Apps/p.plist")
        #expect(script.hasPrefix("launchctl bootout system/local.fancontrol.daemon 2>/dev/null; sleep 1; "))
        #expect(script.contains("cp '/Apps/Fan Control.app/fanctld' '/Library/PrivilegedHelperTools/fanctld' && "))
        #expect(script.contains("chown root:wheel '/Library/LaunchDaemons/local.fancontrol.daemon.plist'"))
        #expect(script.hasSuffix("launchctl bootstrap system '/Library/LaunchDaemons/local.fancontrol.daemon.plist'"))
    }

    @Test func uninstallScriptBootsOutAndRemoves() {
        #expect(HelperScripts.uninstall() ==
            "launchctl bootout system/local.fancontrol.daemon 2>/dev/null; rm -f '/Library/PrivilegedHelperTools/fanctld' '/Library/LaunchDaemons/local.fancontrol.daemon.plist'")
    }

    @Test func appleScriptEscapesQuotesAndBackslashes() {
        #expect(HelperScripts.appleScript(running: #"echo "a\b""#) ==
            #"do shell script "echo \"a\\b\"" with administrator privileges"#)
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận thất bại**

Run: `swift test --filter HelperScriptsTests`
Expected: build lỗi vì không tìm thấy `HelperScripts`.

- [ ] **Step 3: Viết `HelperScripts.swift`**

`Sources/Shared/HelperScripts.swift`:
```swift
import Foundation

/// Lệnh shell cài/gỡ daemon, chạy qua AppleScript với quyền admin.
public enum HelperScripts {
    public static let label = XPCConstants.machServiceName
    public static let helperPath = "/Library/PrivilegedHelperTools/fanctld"
    public static let plistPath = "/Library/LaunchDaemons/local.fancontrol.daemon.plist"

    public static func install(bundledHelper: String, bundledPlist: String) -> String {
        // Gỡ bản cũ (nếu có) rồi chờ launchd dọn xong trước khi nạp lại
        "launchctl bootout system/\(label) 2>/dev/null; sleep 1; " + [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp \(quote(bundledHelper)) \(quote(helperPath))",
            "chown root:wheel \(quote(helperPath))",
            "chmod 755 \(quote(helperPath))",
            "cp \(quote(bundledPlist)) \(quote(plistPath))",
            "chown root:wheel \(quote(plistPath))",
            "chmod 644 \(quote(plistPath))",
            "launchctl bootstrap system \(quote(plistPath))",
        ].joined(separator: " && ")
    }

    /// bootout gửi SIGTERM → daemon trả quạt về Apple rồi thoát.
    public static func uninstall() -> String {
        "launchctl bootout system/\(label) 2>/dev/null; rm -f \(quote(helperPath)) \(quote(plistPath))"
    }

    /// Bọc chuỗi trong dấu nháy đơn cho sh.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func appleScript(running script: String) -> String {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
```

Run: `swift test --filter HelperScriptsTests`
Expected: 4 test pass.

- [ ] **Step 4: Cập nhật `Package.swift` (thêm target app)**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .target(name: "FanCore", dependencies: ["Shared"]),
        .executableTarget(name: "fanctld", dependencies: ["FanCore", "Shared"]),
        .executableTarget(name: "FanControlApp", dependencies: ["Shared"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore", "Shared"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 5: Viết tầng kết nối: `DaemonClient.swift`, `HelperInstaller.swift`**

`Sources/FanControlApp/DaemonClient.swift`:
```swift
import Foundation
import Shared

enum DaemonError: LocalizedError {
    case rejected(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .rejected(let message): return message
        case .badResponse: return "Phản hồi không hợp lệ từ helper"
        }
    }
}

/// Client XPC tới daemon. Kết nối tự tạo lại khi bị invalidate (daemon khởi động lại).
@MainActor
final class DaemonClient {
    private var connection: NSXPCConnection?

    func status() async throws -> Status {
        let data: Data = try await call { proxy, done in proxy.getStatus { done(.success($0)) } }
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { throw DaemonError.badResponse }
        return status
    }

    func setMode(_ presetID: String) async throws {
        try await mutation { proxy, reply in proxy.setMode(presetID, reply: reply) }
    }

    func savePreset(_ preset: Preset) async throws {
        let data = try JSONEncoder().encode(preset)
        try await mutation { proxy, reply in proxy.savePreset(data, reply: reply) }
    }

    func deletePreset(_ presetID: String) async throws {
        try await mutation { proxy, reply in proxy.deletePreset(presetID, reply: reply) }
    }

    private func mutation(_ body: (FanDaemonProtocol, @escaping (String?) -> Void) -> Void) async throws {
        let message: String? = try await call { proxy, done in body(proxy) { done(.success($0)) } }
        if let message { throw DaemonError.rejected(message) }
    }

    /// XPC đảm bảo chỉ gọi một trong hai: reply hoặc error handler.
    private func call<T>(_ body: (FanDaemonProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = makeProxy(onError: { continuation.resume(throwing: $0) }) else {
                continuation.resume(throwing: DaemonError.badResponse)
                return
            }
            body(proxy) { continuation.resume(with: $0) }
        }
    }

    private func makeProxy(onError: @escaping (Error) -> Void) -> FanDaemonProtocol? {
        if connection == nil {
            let newConnection = NSXPCConnection(machServiceName: XPCConstants.machServiceName, options: .privileged)
            newConnection.remoteObjectInterface = NSXPCInterface(with: FanDaemonProtocol.self)
            newConnection.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            newConnection.resume()
            connection = newConnection
        }
        return connection?.remoteObjectProxyWithErrorHandler(onError) as? FanDaemonProtocol
    }
}
```

`Sources/FanControlApp/HelperInstaller.swift`:
```swift
import Foundation
import Shared

/// Cài/gỡ daemon bằng AppleScript `with administrator privileges` (macOS hỏi mật khẩu).
enum HelperInstaller {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperScripts.plistPath)
    }

    static func install() throws {
        guard let helper = Bundle.main.path(forResource: "fanctld", ofType: nil),
              let plist = Bundle.main.path(forResource: "local.fancontrol.daemon", ofType: "plist") else {
            throw DaemonError.rejected("Không tìm thấy fanctld trong app. Hãy build bằng `make app`.")
        }
        try runAsAdmin(HelperScripts.install(bundledHelper: helper, bundledPlist: plist))
    }

    static func uninstall() throws {
        try runAsAdmin(HelperScripts.uninstall())
    }

    private static func runAsAdmin(_ script: String) throws {
        var error: NSDictionary?
        NSAppleScript(source: HelperScripts.appleScript(running: script))?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Lỗi không xác định"
            throw DaemonError.rejected(message)
        }
    }
}
```

- [ ] **Step 6: Viết `AppModel.swift`**

`Sources/FanControlApp/AppModel.swift`:
```swift
import Foundation
import Observation
import ServiceManagement
import Shared

@MainActor
@Observable
final class AppModel {
    private(set) var status: Status?
    private(set) var helperInstalled = HelperInstaller.isInstalled
    private(set) var connectionError: String?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var actionError: String?

    @ObservationIgnored private let client = DaemonClient()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    var presets: [Preset] { status?.presets ?? Preset.builtIns }

    /// Chữ đỏ trên thanh menu: quá nhiệt, daemon báo lỗi hoặc mất kết nối.
    var isAlert: Bool {
        connectionError != nil || status?.error != nil || status?.safetyActive == true
    }

    func refresh() async {
        helperInstalled = HelperInstaller.isInstalled
        guard helperInstalled else {
            status = nil
            connectionError = nil
            return
        }
        do {
            status = try await client.status()
            connectionError = nil
        } catch {
            status = nil
            connectionError = "Không kết nối được helper"
        }
    }

    func setMode(_ presetID: String) async {
        await perform { try await self.client.setMode(presetID) }
    }

    @discardableResult
    func savePreset(_ preset: Preset) async -> Bool {
        await perform { try await self.client.savePreset(preset) }
    }

    func deletePreset(_ presetID: String) async {
        await perform { try await self.client.deletePreset(presetID) }
    }

    func installHelper() async {
        await perform { try HelperInstaller.install() }
    }

    func uninstallHelper() async {
        await perform { try HelperInstaller.uninstall() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            actionError = nil
        } catch {
            actionError = "Không đổi được cài đặt mở khi đăng nhập: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    private func perform(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            actionError = nil
            await refresh()
            return true
        } catch {
            actionError = error.localizedDescription
            await refresh()
            return false
        }
    }
}
```

- [ ] **Step 7: Viết các view: `App.swift`, `MenuBarLabel.swift`, `PopoverView.swift`, `SettingsView.swift`, `GeneralTab.swift`**

`Sources/FanControlApp/App.swift`:
```swift
import SwiftUI

@main
struct FanControlMain: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Cài đặt Fan Control", id: "settings") {
            SettingsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
    }
}
```

`Sources/FanControlApp/MenuBarLabel.swift`:
```swift
import AppKit
import SwiftUI
import Shared

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let text = Format.shortTemperature(model.status?.temperature)
        if model.isAlert, let image = Self.alertImage(text) {
            Image(nsImage: image)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "fan")
                Text(text)
            }
        }
    }

    /// Thanh menu vẽ label dạng template (đơn sắc); muốn chữ đỏ phải render thành ảnh không-template.
    @MainActor
    static func alertImage(_ text: String) -> NSImage? {
        let renderer = ImageRenderer(content:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(text)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.red)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }
}
```

`Sources/FanControlApp/PopoverView.swift`:
```swift
import AppKit
import SwiftUI
import Shared

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.helperInstalled {
                HelperMissingView()
            } else if let message = model.connectionError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Cài lại helper") { Task { await model.installHelper() } }
            } else if let status = model.status {
                StatusSection(status: status)
                Divider()
                ModeList(status: status)
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
        .padding(14)
        .frame(width: 290)
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

private struct StatusSection: View {
    let status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Nhiệt độ CPU/GPU")
                Spacer()
                Text(Format.temperature(status.temperature))
                    .monospacedDigit()
                    .bold()
            }
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

private struct ModeList: View {
    @Environment(AppModel.self) private var model
    let status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(status.presets) { preset in
                Button {
                    Task { await model.setMode(preset.id) }
                } label: {
                    HStack {
                        Image(systemName: preset.id == status.activePresetID ? "largecircle.fill.circle" : "circle")
                        Text(preset.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
    }
}
```

`Sources/FanControlApp/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("Chung", systemImage: "gearshape") }
        }
        .frame(width: 820, height: 500)
    }
}
```

`Sources/FanControlApp/GeneralTab.swift`:
```swift
import SwiftUI

struct GeneralTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Helper điều khiển quạt") {
                LabeledContent("Trạng thái") {
                    Text(helperState).foregroundStyle(helperColor)
                }
                HStack {
                    Button(model.helperInstalled ? "Cài lại helper" : "Cài đặt helper") {
                        Task { await model.installHelper() }
                    }
                    if model.helperInstalled {
                        Button("Gỡ helper", role: .destructive) {
                            Task { await model.uninstallHelper() }
                        }
                    }
                }
                Text("Gỡ helper sẽ trả quạt về chế độ tự động của Apple. Hãy thoát Macs Fan Control để hai app không tranh nhau điều khiển quạt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Khởi động") {
                Toggle("Mở khi đăng nhập", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
            }
            if let error = model.actionError {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private var helperState: String {
        if !model.helperInstalled { return "Chưa cài" }
        if model.connectionError != nil { return "Lỗi kết nối" }
        return model.status == nil ? "Đang kết nối…" : "Đã cài"
    }

    private var helperColor: Color {
        if !model.helperInstalled || model.connectionError != nil { return .red }
        return model.status == nil ? .secondary : .green
    }
}
```

- [ ] **Step 8: Viết `Resources/Info.plist` và `Makefile`**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FanControl</string>
    <key>CFBundleIdentifier</key>
    <string>local.fancontrol.app</string>
    <key>CFBundleName</key>
    <string>Fan Control</string>
    <key>CFBundleDisplayName</key>
    <string>Fan Control</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

`Makefile` (thụt lề bằng **tab**):
```make
APP := build/FanControl.app

.PHONY: build test app install clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/FanControlApp $(APP)/Contents/MacOS/FanControl
	cp .build/release/fanctld $(APP)/Contents/Resources/fanctld
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/local.fancontrol.daemon.plist $(APP)/Contents/Resources/
	codesign --force -s - $(APP)/Contents/Resources/fanctld
	codesign --force -s - $(APP)

install: app
	rm -rf /Applications/FanControl.app
	cp -R $(APP) /Applications/

clean:
	rm -rf .build build
```

- [ ] **Step 9: Build và kiểm chứng**

Run: `swift test && make app && codesign -v build/FanControl.app && ls build/FanControl.app/Contents/Resources`
Expected: test pass; `make app` thành công; `codesign -v` không in lỗi; liệt kê ra `fanctld` và `local.fancontrol.daemon.plist`.

Run: `make install && open /Applications/FanControl.app`
Expected: icon `⚠ --°` màu đỏ (hoặc `🌀 --°`) xuất hiện trên thanh menu, app không có icon trên Dock. Click vào icon thấy "Chưa cài trình điều khiển quạt" kèm nút "Cài đặt helper".

**Người dùng thực hiện** (cần mật khẩu admin): thoát Macs Fan Control, rồi bấm "Cài đặt helper" và nhập mật khẩu. Sau khoảng 2–4 giây:
- Thanh menu hiện `🌀 XX°`.
- Popover hiện nhiệt độ, 2 quạt và danh sách 5 chế độ, chế độ "Cân bằng" được chọn.
- Bấm "Tối đa" thì quạt rú lên trong vòng 2 giây; bấm "Apple tự động" thì quạt giảm về.
- `sudo launchctl print system/local.fancontrol.daemon | grep state` in ra `state = running`.
- `tail /var/log/fanctld.log` có dòng `fanctld khởi động, chế độ: Cân bằng`.
- Cài đặt… → tab Chung hiện "Đã cài" màu xanh.

- [ ] **Step 10: Commit**

```bash
git add Package.swift Makefile Resources/Info.plist Sources/Shared/HelperScripts.swift Sources/FanControlApp Tests/SharedTests/HelperScriptsTests.swift
git commit -m "feat: add menu bar app with helper installer and popover" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Tab Đường cong (trình chỉnh preset)

**Files:**
- Create: `Sources/FanControlApp/CurvesTab.swift`, `Sources/FanControlApp/PresetEditor.swift`
- Modify: `Sources/FanControlApp/SettingsView.swift`

**Interfaces:**
- Consumes: `AppModel.presets`, `AppModel.status`, `AppModel.savePreset(_:) async -> Bool`, `AppModel.deletePreset(_:) async`, `AppModel.actionError` (Task 8); `Preset`, `Preset.duplicated()`, `FanCurve.validate()`, `FanCurve.validTempRange`, `CurvePoint`, `Format.temperature` (Task 1–2).
- Produces: `struct CurvesTab: View`, `struct PresetEditor: View`, `struct CurveChart: View`, `struct PointTable: View`.

Hành vi:
- Danh sách bên trái chia 2 mục "Có sẵn" và "Tùy chỉnh". Chọn một preset thì tạo bản nháp (`draft`) để chỉnh.
- Preset có sẵn hiển thị chỉ đọc; nút "Nhân bản" tạo bản tùy chỉnh, lưu ngay xuống daemon và chọn bản đó.
- Biểu đồ: kéo điểm trong bán kính 20pt; nhiệt độ làm tròn và bị kẹp giữa hai điểm lân cận (±1°C); % kẹp trong 0–100. Đường dọc màu cam đánh dấu nhiệt độ hiện tại.
- Nút "Lưu" bị vô hiệu khi không có thay đổi, đường cong không hợp lệ, hoặc tên trống.

- [ ] **Step 1: Viết `PresetEditor.swift`**

`Sources/FanControlApp/PresetEditor.swift`:
```swift
import Charts
import SwiftUI
import Shared

struct PresetEditor: View {
    @Binding var draft: Preset
    let original: Preset?
    let currentTemp: Double?
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSave: () -> Void

    private var readOnly: Bool { draft.isBuiltIn }

    private var validationError: String? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Tên không được để trống" }
        return draft.kind == .curve ? draft.curve.validate()?.message : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if readOnly {
                    Text(draft.name).font(.title2.bold())
                    Text("Có sẵn – chỉ đọc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Tên chế độ", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .frame(maxWidth: 260)
                }
                Spacer()
                Button("Nhân bản", action: onDuplicate)
                    .disabled(draft.kind != .curve)
                if !readOnly {
                    Button("Xóa", role: .destructive, action: onDelete)
                }
            }

            switch draft.kind {
            case .auto:
                Text("macOS tự điều khiển quạt theo đường cong mặc định của Apple.")
                    .foregroundStyle(.secondary)
            case .max:
                Text("Quạt luôn chạy ở tốc độ tối đa.")
                    .foregroundStyle(.secondary)
            case .curve:
                HStack(alignment: .top, spacing: 16) {
                    CurveChart(points: $draft.curve.points, currentTemp: currentTemp, editable: !readOnly)
                        .frame(minHeight: 260)
                    PointTable(points: $draft.curve.points, editable: !readOnly)
                        .frame(width: 200)
                }
            }

            Spacer(minLength: 0)

            if !readOnly && draft.kind == .curve {
                HStack {
                    if let validationError {
                        Label(validationError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Lưu", action: onSave)
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .disabled(validationError != nil || draft == original)
                }
            }
        }
        .padding()
    }
}

struct CurveChart: View {
    @Binding var points: [CurvePoint]
    let currentTemp: Double?
    let editable: Bool
    @State private var dragIndex: Int?

    private static let hitRadius: CGFloat = 20

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Nhiệt độ", point.temp), y: .value("Tốc độ", point.percent))
                PointMark(x: .value("Nhiệt độ", point.temp), y: .value("Tốc độ", point.percent))
                    .symbolSize(editable ? 120 : 60)
            }
            if let currentTemp {
                let x = min(max(currentTemp, FanCurve.validTempRange.lowerBound), FanCurve.validTempRange.upperBound)
                RuleMark(x: .value("Hiện tại", x))
                    .foregroundStyle(.orange)
                    .annotation(position: .top, alignment: .leading) {
                        Text(Format.temperature(currentTemp))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
            }
        }
        .chartXScale(domain: FanCurve.validTempRange)
        .chartYScale(domain: FanCurve.validPercentRange)
        .chartXAxisLabel("Nhiệt độ (°C)")
        .chartYAxisLabel("Tốc độ (%)")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(proxy: proxy, geometry: geometry))
                    .allowsHitTesting(editable)
            }
        }
    }

    private func dragGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let plotFrame = proxy.plotFrame else { return }
                let origin = geometry[plotFrame].origin
                if dragIndex == nil {
                    let start = CGPoint(x: value.startLocation.x - origin.x, y: value.startLocation.y - origin.y)
                    dragIndex = nearestIndex(to: start, proxy: proxy)
                }
                guard let index = dragIndex,
                      let temp: Double = proxy.value(atX: value.location.x - origin.x),
                      let percent: Double = proxy.value(atY: value.location.y - origin.y) else { return }
                let lower = index > 0 ? points[index - 1].temp + 1 : FanCurve.validTempRange.lowerBound
                let upper = index < points.count - 1 ? points[index + 1].temp - 1 : FanCurve.validTempRange.upperBound
                points[index].temp = min(max(temp.rounded(), lower), upper)
                points[index].percent = min(max(percent.rounded(), 0), 100)
            }
            .onEnded { _ in dragIndex = nil }
    }

    /// Điểm gần nhất trong bán kính `hitRadius` quanh vị trí bắt đầu kéo.
    private func nearestIndex(to location: CGPoint, proxy: ChartProxy) -> Int? {
        let distances = points.enumerated().compactMap { index, point -> (Int, CGFloat)? in
            guard let x = proxy.position(forX: point.temp), let y = proxy.position(forY: point.percent) else { return nil }
            return (index, hypot(x - location.x, y - location.y))
        }
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= Self.hitRadius else { return nil }
        return nearest.0
    }
}

struct PointTable: View {
    @Binding var points: [CurvePoint]
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Nhiệt độ (°C)").bold()
                    Text("Tốc độ (%)").bold()
                }
                ForEach(points.indices, id: \.self) { index in
                    GridRow {
                        TextField("", value: $points[index].temp, format: .number)
                            .frame(width: 80)
                        TextField("", value: $points[index].percent, format: .number)
                            .frame(width: 80)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(!editable)

            if editable {
                HStack {
                    Button("Thêm điểm", action: addPoint)
                        .disabled((points.last?.temp ?? 0) >= FanCurve.validTempRange.upperBound)
                    Button("Xóa điểm cuối") { points.removeLast() }
                        .disabled(points.count <= 2)
                }
            }
        }
    }

    private func addPoint() {
        let last = points.last ?? CurvePoint(temp: 50, percent: 0)
        points.append(CurvePoint(temp: min(last.temp + 5, FanCurve.validTempRange.upperBound), percent: last.percent))
    }
}
```

- [ ] **Step 2: Viết `CurvesTab.swift`**

`Sources/FanControlApp/CurvesTab.swift`:
```swift
import SwiftUI
import Shared

struct CurvesTab: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String? = Preset.balancedID
    @State private var draft: Preset?

    private var selectedPreset: Preset? {
        model.presets.first { $0.id == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Có sẵn") {
                    ForEach(model.presets.filter(\.isBuiltIn)) { Text($0.name).tag($0.id) }
                }
                Section("Tùy chỉnh") {
                    ForEach(model.presets.filter { !$0.isBuiltIn }) { Text($0.name).tag($0.id) }
                }
            }
            .frame(width: 190)

            Divider()

            VStack(spacing: 0) {
                if let draft = Binding($draft) {
                    PresetEditor(
                        draft: draft,
                        original: selectedPreset,
                        currentTemp: model.status?.temperature,
                        onDuplicate: duplicate,
                        onDelete: delete,
                        onSave: save)
                } else {
                    Text("Chọn một chế độ")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let error = model.actionError {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }
            }
        }
        .onChange(of: selectedID, initial: true) { draft = selectedPreset }
        .onChange(of: model.presets) {
            // Không ghi đè bản nháp đang sửa; chỉ làm mới khi preset đang chọn biến mất
            if let id = draft?.id, !model.presets.contains(where: { $0.id == id }) {
                draft = selectedPreset
            }
        }
    }

    private func duplicate() {
        guard let source = draft else { return }
        let copy = source.duplicated()
        Task {
            if await model.savePreset(copy) { selectedID = copy.id }
        }
    }

    private func delete() {
        guard let id = draft?.id else { return }
        Task {
            await model.deletePreset(id)
            selectedID = Preset.balancedID
        }
    }

    private func save() {
        guard let preset = draft else { return }
        Task { await model.savePreset(preset) }
    }
}
```

- [ ] **Step 3: Thêm tab Đường cong vào `SettingsView.swift`**

Thay toàn bộ nội dung `Sources/FanControlApp/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            CurvesTab()
                .tabItem { Label("Đường cong", systemImage: "chart.xyaxis.line") }
            GeneralTab()
                .tabItem { Label("Chung", systemImage: "gearshape") }
        }
        .frame(width: 820, height: 500)
    }
}
```

- [ ] **Step 4: Build và kiểm chứng**

Run: `swift build && make install && (pkill -x FanControl; open /Applications/FanControl.app)`
Expected: build thành công, app mở lại.

Kiểm tra thủ công (helper đã cài ở Task 8):
1. Popover → "Cài đặt…" → cửa sổ "Cài đặt Fan Control" mở ra ở phía trước, tab "Đường cong" được chọn sẵn với "Cân bằng".
2. "Cân bằng" hiện biểu đồ 4 điểm và bảng số ở chế độ chỉ đọc; kéo điểm không có tác dụng; có đường cam ở nhiệt độ hiện tại.
3. Bấm "Nhân bản": mục "Tùy chỉnh" có thêm "Cân bằng (bản sao)" và mục này được chọn.
4. Kéo một điểm thì điểm di chuyển và số trong bảng cập nhật. Kéo một điểm làm % thấp hơn điểm trước thì hiện "Tốc độ không được giảm khi nhiệt độ tăng" và nút Lưu bị mờ.
5. Sửa lại cho hợp lệ, đổi tên thành "Chơi game", bấm Lưu. Popover có thêm chế độ "Chơi game"; chọn nó thì quạt chạy theo đường cong mới.
6. Bấm "Xóa" trên "Chơi game": preset biến mất, danh sách quay về "Cân bằng", và nếu "Chơi game" đang được dùng thì daemon chuyển sang "Cân bằng".

- [ ] **Step 5: Commit**

```bash
git add Sources/FanControlApp/CurvesTab.swift Sources/FanControlApp/PresetEditor.swift Sources/FanControlApp/SettingsView.swift
git commit -m "feat: add curve editor tab with draggable chart" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: README, kiểm chứng phần cứng, cập nhật spec

**Files:**
- Create: `README.md`
- Modify: `docs/superpowers/specs/2026-10-26-fan-control-design.md` (mục "Cần kiểm chứng khi implement")

**Interfaces:**
- Consumes: toàn bộ app + daemon đã cài (Task 8–9), `fanctld --probe` (Task 7).
- Produces: tài liệu sử dụng và kết quả kiểm chứng `FxMd=0`.

- [ ] **Step 1: Viết `README.md`**

````markdown
# Fan Control

App menu bar tự chỉnh tốc độ quạt MacBook Pro (M1 Pro) theo nhiệt độ CPU/GPU.

## Cài đặt

Yêu cầu: macOS 14+, Xcode (hoặc Command Line Tools) có Swift 6.

```bash
make install                       # build, đóng gói và copy vào /Applications
open /Applications/FanControl.app
```

1. **Thoát Macs Fan Control** (hoặc để nó ở chế độ Auto) để hai app không tranh nhau điều khiển quạt.
2. Click icon quạt trên thanh menu → **Cài đặt helper** → nhập mật khẩu admin.
3. Chọn chế độ trong popover. Muốn chỉnh đường cong: **Cài đặt… → Đường cong → Nhân bản**.

Bật "Mở khi đăng nhập" trong **Cài đặt… → Chung**. Kể cả khi không mở app, helper vẫn điều khiển quạt theo chế độ đã chọn.

## Chế độ

| Chế độ | Hành vi |
|---|---|
| Apple tự động | macOS tự lo |
| Êm | 65°C→0%, 75°C→30%, 85°C→60%, 92°C→100% |
| Cân bằng | 55°C→0%, 65°C→35%, 75°C→65%, 85°C→100% |
| Hiệu năng | 45°C→20%, 60°C→50%, 70°C→80%, 78°C→100% |
| Tối đa | luôn 100% |

Dưới điểm đầu tiên của đường cong, quạt được trả về cho Apple (có thể dừng hẳn khi máy mát). Ở mọi chế độ, khi nhiệt độ ≥ 95°C quạt luôn chạy tối đa.

## Gỡ cài đặt

**Cài đặt… → Chung → Gỡ helper** (quạt trở về chế độ của Apple), rồi xóa `/Applications/FanControl.app`.

## Gỡ lỗi

```bash
.build/release/fanctld --probe                                   # xem quạt + nhiệt độ (không cần root)
.build/release/fanctld --dry-run --config /tmp/fanctl.json       # chạy thử, chỉ log
tail -f /var/log/fanctld.log                                     # log helper
sudo launchctl print system/local.fancontrol.daemon | grep state # trạng thái helper
swift test                                                       # unit test
FANCTL_HW=1 swift test --filter readsRealSMC                     # test đọc SMC thật
```
````

- [ ] **Step 2: Kiểm chứng phần cứng (người dùng thực hiện, agent hướng dẫn và ghi kết quả)**

Chạy song song `tail -f /var/log/fanctld.log` và `watch -n2 .build/release/fanctld --probe` (hoặc chạy lại `--probe` nhiều lần). Lần lượt kiểm tra:

1. **Apple tự động trả quyền thật:** chọn "Apple tự động" khi máy mát (< 50°C), đợi 30 giây. `--probe` phải báo `chế độ Apple` cho cả 2 quạt và ghi lại RPM thực tế (kỳ vọng 0 RPM khi mát).
2. **Đường cong tăng:** chọn "Cân bằng", chạy tải `for i in $(seq $(sysctl -n hw.ncpu)); do yes > /dev/null & done`. Quạt phải chuyển sang `manual` khi nhiệt độ đạt khoảng 55°C, rồi tăng dần theo nhiệt độ.
3. **Giảm từ từ:** `killall yes`. RPM giảm tối đa khoảng 300 mỗi 2 giây, sau đó về `chế độ Apple` khi nhiệt độ < 52°C.
4. **Failsafe khi tắt daemon:** chọn "Tối đa", rồi `sudo launchctl kill SIGTERM system/local.fancontrol.daemon`. Log phải có `Nhận tín hiệu 15`, quạt về `Apple`. launchd tự khởi động lại daemon (KeepAlive), sau đó quạt về lại "Tối đa".
5. **Sleep/wake:** chọn "Tối đa", gập máy khoảng 1 phút rồi mở. Log phải có `Máy thức dậy` và quạt vẫn ở tối đa.

- [ ] **Step 3: Cập nhật spec theo kết quả**

Trong `docs/superpowers/specs/2026-10-26-fan-control-design.md`, thay đoạn "**Cần kiểm chứng khi implement:** …" bằng kết quả thực tế. Ví dụ, nếu bước 1 cho 0 RPM:

```markdown
**Đã kiểm chứng (M1 Pro, macOS 15.6.1):** ghi `FxMd=0` trả quyền cho Apple; khi máy mát quạt dừng ở 0 RPM.
```

Nếu bước 1 cho thấy quạt vẫn kẹt ở RPM cũ hoặc `FxMd` không về 0, ghi lại đúng hiện tượng và tạo một task tiếp theo để chuyển "Auto" sang giữ mức min (`.manual(rpm: minRPM)`).

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/specs/2026-10-26-fan-control-design.md
git commit -m "docs: add README and record hardware verification results" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
