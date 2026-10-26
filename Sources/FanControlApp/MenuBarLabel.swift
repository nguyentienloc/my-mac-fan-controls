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
