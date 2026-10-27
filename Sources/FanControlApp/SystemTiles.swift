import SwiftUI
import Shared
import SystemStats

/// Tiêu đề nhỏ viết hoa của từng khối trong popover.
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Thẻ số liệu: nhãn nhỏ, số lớn, dòng phụ.
struct StatTile<Detail: View>: View {
    let title: String
    let symbol: String
    let value: String
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            detail()
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Lưới 2×2: CPU/GPU, RAM, ổ đĩa, mạng.
struct SystemTiles: View {
    let system: SystemSnapshot?
    let temperature: Double?

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            StatTile(title: "CPU/GPU", symbol: "thermometer.medium", value: Format.temperature(temperature)) {
                Text("CPU \(Format.percent(system?.cpuPercent))")
            }
            StatTile(title: "RAM", symbol: "memorychip",
                     value: system.map { Format.memory($0.memoryUsed) } ?? "--") {
                if let system {
                    // Một Text duy nhất: nội suy Text đã tô màu (không dùng Text + Text vì đã deprecated)
                    Text("/ \(Format.memory(system.memoryTotal)) · \(Text(system.memoryPressure.label).foregroundStyle(system.memoryPressure.color))")
                } else {
                    Text("--")
                }
            }
            StatTile(title: "Ổ đĩa", symbol: "internaldrive",
                     value: system?.diskFree.map { Format.disk($0) } ?? "--") {
                Text("trống / \(system?.diskTotal.map { Format.disk($0) } ?? "--")")
            }
            StatTile(title: "Mạng", symbol: "arrow.up.arrow.down",
                     value: "↓ \(Format.rate(system?.downloadBytesPerSecond))") {
                Text("↑ \(Format.rate(system?.uploadBytesPerSecond))")
            }
        }
    }
}

extension MemoryPressure {
    var label: String {
        switch self {
        case .normal: return "bình thường"
        case .warning: return "cao"
        case .critical: return "nguy hiểm"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
