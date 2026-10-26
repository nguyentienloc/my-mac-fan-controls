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
