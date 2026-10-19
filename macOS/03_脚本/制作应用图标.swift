import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3, let source = NSImage(contentsOfFile: arguments[1]) else { exit(1) }
let destination = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.12, green: 0.23, blue: 0.21, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pixels, height: pixels), xRadius: Double(pixels) * 0.22, yRadius: Double(pixels) * 0.22).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        let inset = Double(pixels) * 0.08
        source.draw(in: NSRect(x: inset, y: inset, width: Double(pixels) - 2 * inset, height: Double(pixels) - 2 * inset))
        NSGraphicsContext.restoreGraphicsState()
        if let data = bitmap.representation(using: .png, properties: [:]) {
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            try data.write(to: destination.appendingPathComponent(name))
        }
    }
}
