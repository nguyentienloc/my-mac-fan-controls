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
                ModePicker(status: status)
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
