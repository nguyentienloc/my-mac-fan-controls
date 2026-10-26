import Charts
import SwiftUI
import Shared

struct PresetEditor: View {
    @Binding var draft: Preset
    let original: Preset?
    let currentTemp: Double?
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSave: () -> Void

    private var readOnly: Bool { draft.isBuiltIn }

    private var validationError: String? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Tên không được để trống" }
        return draft.kind == .curve ? draft.curve.validate()?.message : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if readOnly {
                    Text(draft.name).font(.title2.bold())
                    Text("Có sẵn – chỉ đọc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Tên chế độ", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .frame(maxWidth: 260)
                }
                Spacer()
                Button("Nhân bản", action: onDuplicate)
                    .disabled(draft.kind != .curve)
                if !readOnly {
                    Button("Xóa", role: .destructive, action: onDelete)
                }
            }

            switch draft.kind {
            case .auto:
                Text("macOS tự điều khiển quạt theo đường cong mặc định của Apple.")
                    .foregroundStyle(.secondary)
            case .max:
                Text("Quạt luôn chạy ở tốc độ tối đa.")
                    .foregroundStyle(.secondary)
            case .curve:
                HStack(alignment: .top, spacing: 16) {
                    CurveChart(points: $draft.curve.points, currentTemp: currentTemp, editable: !readOnly)
                        .frame(minHeight: 260)
                    PointTable(points: $draft.curve.points, editable: !readOnly)
                        .frame(width: 200)
                }
            }

            Spacer(minLength: 0)

            if !readOnly && draft.kind == .curve {
                HStack {
                    if let validationError {
                        Label(validationError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Lưu", action: onSave)
                        .keyboardShortcut("s")
                        .buttonStyle(.borderedProminent)
                        .disabled(validationError != nil || draft == original)
                }
            }
        }
        .padding()
    }
}

struct CurveChart: View {
    @Binding var points: [CurvePoint]
    let currentTemp: Double?
    let editable: Bool
    @State private var dragIndex: Int?

    private static let hitRadius: CGFloat = 20

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Nhiệt độ", point.temp), y: .value("Tốc độ", point.percent))
                PointMark(x: .value("Nhiệt độ", point.temp), y: .value("Tốc độ", point.percent))
                    .symbolSize(editable ? 120 : 60)
            }
            if let currentTemp {
                let x = min(max(currentTemp, FanCurve.validTempRange.lowerBound), FanCurve.validTempRange.upperBound)
                RuleMark(x: .value("Hiện tại", x))
                    .foregroundStyle(.orange)
                    .annotation(position: .top, alignment: .leading) {
                        Text(Format.temperature(currentTemp))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
            }
        }
        .chartXScale(domain: FanCurve.validTempRange)
        .chartYScale(domain: FanCurve.validPercentRange)
        .chartXAxisLabel("Nhiệt độ (°C)")
        .chartYAxisLabel("Tốc độ (%)")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(proxy: proxy, geometry: geometry))
                    .allowsHitTesting(editable)
            }
        }
    }

    private func dragGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let plotFrame = proxy.plotFrame else { return }
                let origin = geometry[plotFrame].origin
                if dragIndex == nil {
                    let start = CGPoint(x: value.startLocation.x - origin.x, y: value.startLocation.y - origin.y)
                    dragIndex = nearestIndex(to: start, proxy: proxy)
                }
                guard let index = dragIndex,
                      let temp: Double = proxy.value(atX: value.location.x - origin.x),
                      let percent: Double = proxy.value(atY: value.location.y - origin.y) else { return }
                let lower = index > 0 ? points[index - 1].temp + 1 : FanCurve.validTempRange.lowerBound
                let upper = index < points.count - 1 ? points[index + 1].temp - 1 : FanCurve.validTempRange.upperBound
                points[index].temp = min(max(temp.rounded(), lower), upper)
                points[index].percent = min(max(percent.rounded(), 0), 100)
            }
            .onEnded { _ in dragIndex = nil }
    }

    /// Điểm gần nhất trong bán kính `hitRadius` quanh vị trí bắt đầu kéo.
    private func nearestIndex(to location: CGPoint, proxy: ChartProxy) -> Int? {
        let distances = points.enumerated().compactMap { index, point -> (Int, CGFloat)? in
            guard let x = proxy.position(forX: point.temp), let y = proxy.position(forY: point.percent) else { return nil }
            return (index, hypot(x - location.x, y - location.y))
        }
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= Self.hitRadius else { return nil }
        return nearest.0
    }
}

struct PointTable: View {
    @Binding var points: [CurvePoint]
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Nhiệt độ (°C)").bold()
                    Text("Tốc độ (%)").bold()
                }
                ForEach(points.indices, id: \.self) { index in
                    GridRow {
                        TextField("", value: $points[index].temp, format: .number)
                            .frame(width: 80)
                        TextField("", value: $points[index].percent, format: .number)
                            .frame(width: 80)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(!editable)

            if editable {
                HStack {
                    Button("Thêm điểm", action: addPoint)
                        .disabled((points.last?.temp ?? 0) >= FanCurve.validTempRange.upperBound)
                    Button("Xóa điểm cuối") { points.removeLast() }
                        .disabled(points.count <= 2)
                }
            }
        }
    }

    private func addPoint() {
        let last = points.last ?? CurvePoint(temp: 50, percent: 0)
        points.append(CurvePoint(temp: min(last.temp + 5, FanCurve.validTempRange.upperBound), percent: last.percent))
    }
}
