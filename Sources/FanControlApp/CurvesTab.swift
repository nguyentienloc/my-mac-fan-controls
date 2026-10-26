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
            // Khôi phục trình sửa khi danh sách preset quay lại sau lỗi thoáng qua
            if draft == nil { draft = selectedPreset }
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
            if await model.deletePreset(id) { selectedID = Preset.balancedID }
        }
    }

    private func save() {
        guard let preset = draft else { return }
        Task { await model.savePreset(preset) }
    }
}
