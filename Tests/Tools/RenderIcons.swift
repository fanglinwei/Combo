import AppKit

@main struct RenderIcons {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let scenes = Scene.allCases.filter { $0 != .live }
        let height = CGFloat((scenes.count + 3) / 4) * 220 + 100
        let sheet = NSImage(size: NSSize(width: 880, height: height))
        sheet.lockFocus()
        NSColor(srgbRed: 23/255, green: 24/255, blue: 27/255, alpha: 1).setFill()
        NSRect(x: 0,y: 0,width: 880,height: height).fill()
        for (i, scene) in scenes.enumerated() {
            let x = CGFloat(i % 4)*220
            let y = height-CGFloat(i / 4+1)*220
            let s = Snapshot.demo(scene).preferringBattery(threshold: 50)
            IconRenderer.image(s, animate: true, size: 140).draw(in: NSRect(x:x+40,y:y+42,width:140,height:140))
            let label = NSAttributedString(string: scene.rawValue, attributes: [.font:NSFont.systemFont(ofSize:16), .foregroundColor:NSColor.white])
            label.draw(at:NSPoint(x:x+(220-label.size().width)/2,y:y+12))
        }
        for (i,scene) in scenes.enumerated() {
            let x = CGFloat(i)*45+12
            IconRenderer.image(.demo(scene), animate:true, size:22).draw(in:NSRect(x:x,y:55,width:22,height:22))
            NSColor(srgbRed:238/255,green:238/255,blue:241/255,alpha:1).setFill()
            NSRect(x:x-6,y:8,width:36,height:32).fill()
            IconRenderer.image(.demo(scene), animate:true, size:22,dark:false).draw(in:NSRect(x:x,y:13,width:22,height:22))
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) else { fatalError("PNG export failed") }
        try png.write(to:URL(fileURLWithPath:"build/combo-priority-review.png"))
        print("Rendered \(scenes.count) demo states → build/combo-priority-review.png")
    }
}
