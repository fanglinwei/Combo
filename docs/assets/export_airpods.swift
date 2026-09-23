import AppKit

// Design asset only: use Apple's symbol without redrawing its product shape.
let names = ["airpods.pro", "airpodspro"]
guard let symbol = names.compactMap({ NSImage(systemSymbolName: $0, accessibilityDescription: nil) }).first else {
    fatalError("AirPods Pro symbol unavailable on this macOS version")
}
let configured = symbol.withSymbolConfiguration(.init(pointSize: 160, weight: .regular)) ?? symbol
let canvas = NSImage(size: NSSize(width: 256, height: 256))
canvas.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 256, height: 256).fill()
let ratio = min(224 / configured.size.width, 224 / configured.size.height)
let size = NSSize(width: configured.size.width * ratio, height: configured.size.height * ratio)
configured.draw(in: NSRect(x: (256-size.width)/2, y: (256-size.height)/2, width: size.width, height: size.height))
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: 256, height: 256).fill(using: .sourceIn)
canvas.unlockFocus()
guard let data = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Symbol render failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("Exported system AirPods Pro symbol")
