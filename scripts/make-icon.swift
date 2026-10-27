// Vẽ icon app vào một thư mục .iconset: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

/// Nền bo góc chuyển màu xanh dương → xanh ngọc, hình quạt trắng ở giữa.
func render(size: Int) -> Data {
    let side = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Lề 10% như icon macOS chuẩn, bo góc 22,5%
    let inset = side * 0.1
    let rect = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = side * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.01)
    shadow.set()
    color(0x2F80ED).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x2F80ED), ending: color(0x2BC0B4))!.draw(in: shape, angle: -45)

    let config = NSImage.SymbolConfiguration(pointSize: side * 0.40, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let fan = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let fanSize = fan.size
    fan.draw(in: NSRect(x: (side - fanSize.width) / 2, y: (side - fanSize.height) / 2,
                        width: fanSize.width, height: fanSize.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
