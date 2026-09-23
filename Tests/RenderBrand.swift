import AppKit

// Generate a raster master for the vector app mark in docs/assets/brand/combo-iris-app-icon.svg.
// AppKit renders at Retina resolution; 512 points produce a 1024-pixel master.
let size: CGFloat = 512
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let scale = NSAffineTransform()
scale.scale(by: size / 100)
scale.concat()
let iris = NSColor(srgbRed: 117/255, green: 97/255, blue: 201/255, alpha: 1)
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 100, height: 100), xRadius: 22, yRadius: 22)
iris.setFill()
bg.fill()
NSColor.white.setStroke()
func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: 100-y) }
func stroke(_ path: NSBezierPath) {
    path.lineWidth = 7
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}
let ring = NSBezierPath()
for angle in stride(from: 150.0, through: 390.0, by: 2.0) {
    let radians = angle * .pi / 180
    let p = point(50 + 34 * cos(radians), 48 + 34 * sin(radians))
    if angle == 150 { ring.move(to: p) } else { ring.line(to: p) }
}
stroke(ring)
let wifi = NSBezierPath()
wifi.move(to: point(38, 47))
wifi.curve(to: point(62, 47), controlPoint1: point(46, 39.67), controlPoint2: point(54, 39.67))
stroke(wifi)
let inner = NSBezierPath()
inner.move(to: point(44, 53))
inner.curve(to: point(56, 53), controlPoint1: point(48, 49.67), controlPoint2: point(52, 49.67))
stroke(inner)
NSColor.white.setFill()
for (x, y) in [(CGFloat(35), CGFloat(76)), (45, 80), (55, 80), (65, 76)] {
    NSBezierPath(ovalIn: NSRect(x: x - 3.5, y: 100 - y - 3.5, width: 7, height: 7)).fill()
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]),
      CommandLine.arguments.count == 2 else { fatalError("Unable to render Combo icon") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
