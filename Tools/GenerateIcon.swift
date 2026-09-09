import AppKit

// Reproducible app icon drawn with native paths. Run from the project root.
let output = URL(fileURLWithPath: "build/Koe.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let n = CGFloat(pixels)
        NSColor(srgbRed: 0.02, green: 0.43, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.07, y: n * 0.07, width: n * 0.86, height: n * 0.86),
                     xRadius: n * 0.21, yRadius: n * 0.21).fill()
        NSColor.white.setStroke()
        for (index, height) in [0.19, 0.37, 0.53, 0.29, 0.43].enumerated() {
            let x = n * (0.29 + CGFloat(index) * 0.105)
            let path = NSBezierPath()
            path.lineWidth = n * 0.047
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: x, y: n * (0.5 - height / 2)))
            path.line(to: NSPoint(x: x, y: n * (0.5 + height / 2)))
            path.stroke()
        }
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try representation.representation(using: .png, properties: [:])!.write(to: file)
    }
}
