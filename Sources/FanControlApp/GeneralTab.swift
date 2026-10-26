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
