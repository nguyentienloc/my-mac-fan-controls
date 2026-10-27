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
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }
}
