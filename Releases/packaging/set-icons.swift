import AppKit

guard CommandLine.arguments.count == 3 else {
    fatalError("Expected assets directory and destination directory")
}
let assets = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
for (name, icon) in [("安装指南.html", "guide"), ("允许任意来源.command", "terminal"), ("清除下载隔离.command", "terminal")] {
    guard let image = NSImage(contentsOf: assets.appendingPathComponent("\(icon).png")),
          NSWorkspace.shared.setIcon(image, forFile: destination.appendingPathComponent(name).path, options: []) else {
        fatalError("Cannot set custom icon for \(name)")
    }
    var file = destination.appendingPathComponent(name)
    var values = URLResourceValues()
    values.hasHiddenExtension = true
    try file.setResourceValues(values)
}
