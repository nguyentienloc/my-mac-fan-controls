import Foundation
import IOKit
import IOKit.pwr_mgt

/// Báo khi máy thức dậy. Các hằng kIOMessage* là macro C nên Swift không import được:
/// iokit_common_msg(x) = 0xE0000000 | x.
/// Phải sống suốt tiến trình vì refcon truyền không giữ (unretained).
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

    var isRegistered: Bool { rootPort != 0 }

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
