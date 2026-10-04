import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let white = NSColor(calibratedWhite: 1, alpha: 1)
let ink = NSColor(calibratedRed: 0.23, green: 0.26, blue: 0.3, alpha: 1)
let edge = NSColor(calibratedRed: 0.66, green: 0.7, blue: 0.75, alpha: 1)

func stroke(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

for name in ["guide", "terminal"] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon canvas") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: 2, y: 2)
    context.cgContext.translateBy(x: 76.8, y: 76.8)
    context.cgContext.scaleBy(x: 0.7, y: 0.7)

    let shape: NSBezierPath
    if name == "guide" {
        shape = NSBezierPath()
        shape.move(to: NSPoint(x: 110, y: 52))
        shape.line(to: NSPoint(x: 402, y: 52))
        shape.line(to: NSPoint(x: 402, y: 380))
        shape.line(to: NSPoint(x: 322, y: 460))
        shape.line(to: NSPoint(x: 110, y: 460))
        shape.close()
    } else {
        shape = NSBezierPath(roundedRect: NSRect(x: 50, y: 95, width: 412, height: 322), xRadius: 18, yRadius: 18)
    }
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.1, alpha: 0.16)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: -5)
    shadow.set()
    (name == "guide" ? white : ink).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.lineWidth = 3
    edge.setStroke()
    shape.stroke()

    if name == "guide" {
        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 322, y: 460))
        fold.line(to: NSPoint(x: 322, y: 380))
        fold.line(to: NSPoint(x: 402, y: 380))
        fold.close()
        NSColor(calibratedWhite: 0.9, alpha: 1).setFill()
        fold.fill()
        stroke([NSPoint(x: 322, y: 460), NSPoint(x: 322, y: 380), NSPoint(x: 402, y: 380)], color: edge, width: 3)
        stroke([NSPoint(x: 157, y: 345), NSPoint(x: 290, y: 345)], color: ink.withAlphaComponent(0.7), width: 15)
        for y in [280.0, 240.0, 200.0] {
            stroke([NSPoint(x: 157, y: y), NSPoint(x: 355, y: y)], color: edge, width: 9)
        }
        stroke([NSPoint(x: 157, y: 160), NSPoint(x: 290, y: 160)], color: edge, width: 9)
    } else {
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSRect(x: 50, y: 355, width: 412, height: 62).fill()
        NSGraphicsContext.restoreGraphicsState()
        for x in [83.0, 109.0, 135.0] {
            edge.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: 380, width: 12, height: 12)).fill()
        }
        stroke([NSPoint(x: 120, y: 294), NSPoint(x: 176, y: 242), NSPoint(x: 120, y: 190)], color: white, width: 18)
        stroke([NSPoint(x: 217, y: 190), NSPoint(x: 294, y: 190)], color: white, width: 18)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try png.write(to: output.appendingPathComponent("\(name).png"))
}
