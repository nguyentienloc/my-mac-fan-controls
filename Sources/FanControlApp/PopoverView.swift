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
