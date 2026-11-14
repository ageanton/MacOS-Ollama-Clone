set -eo pipefail
cat << 'EOF' > build/generate_icon.swift
import AppKit
import CoreGraphics

func renderMotifIcon(size: Int) -> Data? {
    let cgSize = CGSize(width: size, height: size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    let s = CGFloat(size)
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = rect.width * 0.225

    let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    ctx.saveGState()
    squircle.addClip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        CGColor(red: 0.14, green: 0.15, blue: 0.19, alpha: 1.0),
        CGColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: s * 0.5, y: s - inset),
            end: CGPoint(x: s * 0.5, y: inset),
            options: []
        )
    }

    // Subtle architectural grid lines inside icon
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.04))
    ctx.setLineWidth(max(1.0, s * 0.003))
    ctx.move(to: CGPoint(x: rect.minX, y: s * 0.5))
    ctx.addLine(to: CGPoint(x: rect.maxX, y: s * 0.5))
    ctx.move(to: CGPoint(x: s * 0.5, y: rect.minY))
    ctx.addLine(to: CGPoint(x: s * 0.5, y: rect.maxY))
    ctx.strokePath()

    // Geometric "M" Monogram in Alabaster Stone
    let mPath = CGMutablePath()
    let leftX = s * 0.29
    let rightX = s * 0.71
    let midX = s * 0.50
    let botY = s * 0.31
    let topY = s * 0.69
    let valleyY = s * 0.44

    mPath.move(to: CGPoint(x: leftX, y: botY))
    mPath.addLine(to: CGPoint(x: leftX, y: topY))
    mPath.addLine(to: CGPoint(x: midX, y: valleyY))
    mPath.addLine(to: CGPoint(x: rightX, y: topY))
    mPath.addLine(to: CGPoint(x: rightX, y: botY))

    ctx.setStrokeColor(CGColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 0.96))
    ctx.setLineWidth(s * 0.072)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(mPath)
    ctx.strokePath()

    ctx.restoreGState()

    // Specular inner border
    let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.006, dy: s * 0.006), xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(calibratedWhite: 1.0, alpha: 0.16).setStroke()
    borderPath.lineWidth = max(1.0, s * 0.012)
    borderPath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    if let png = renderMotifIcon(size: px) {
        try? png.write(to: URL(fileURLWithPath: "build/AppIcon.iconset/\(name)"))
    }
}
EOF
swift build/generate_icon.swift
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
ls -lh build/AppIcon.icns
