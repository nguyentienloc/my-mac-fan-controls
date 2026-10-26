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
    print("\(sensors.keys.count) cảm biến, nhiệt độ cao nhất \(String(format: "%.1f", maxTemp))°C")
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
if !powerMonitor.isRegistered {
    logLine("Không đăng ký được sự kiện nguồn; sẽ không ghi lại lệnh quạt sau khi thức dậy")
}

// Dry-run chạy ngoài launchd nên không mở XPC; chỉ tạo service và listener khi chạy thật.
// Giữ sống bằng biến toàn cục (listener.delegate là weak).
var service: DaemonService?
var listener: NSXPCListener?
if !dryRun {
    let newService = DaemonService(queue: queue, loop: loop, store: store, log: logLine)
    let newListener = NSXPCListener(machServiceName: XPCConstants.machServiceName)
    newListener.delegate = newService
    newListener.resume()
    service = newService
    listener = newListener
}

dispatchMain()
