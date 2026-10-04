import AppKit

@main struct RenderIcons {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        // Both sides of the charging gap retain semicircular caps, on track and progress.
        for dark in [true, false] {
            for battery in [0.0, 0.65, 0.8, 0.82, 1.0] {
                let image = IconRenderer.image(Snapshot(battery: battery, charging: true), animate: false, size: 400, dark: dark)
                let pixels = NSBitmapImageRep(data: image.tiffRepresentation!)!
                for (angle, direction) in [(300.0, 1.0), (346.0, -1.0)] {
                    let theta = angle * .pi / 180
                    func alpha(_ tangent: Double, _ radial: Double) -> Double {
                        let x = 50 + (36 + radial)*cos(theta) - direction*tangent*sin(theta)
                        let y = 44 + (36 + radial)*sin(theta) + direction*tangent*cos(theta)
                        let px = (50 + (x-50)*1.06) * Double(pixels.pixelsWide) / 100
                        let py = (50 + (y-45.5)*1.06) * Double(pixels.pixelsHigh) / 100
                        return pixels.colorAt(x: Int(px), y: Int(py))!.alphaComponent
                    }
                    assert(alpha(2, 0) > 0.9, "Charging cap must extend into the gap")
                    for radial in [-2.5, 2.5] {
                        assert(alpha(2, radial) < 0.1, "Charging cap corners must be rounded")
                    }
                }
            }
        }
        for dark in [true, false] {
            let foreground = dark ? [244,244,246] : [36,37,42]
            let track = dark ? [86,89,97] : [167,170,179]
            for charging in [false, true] {
                for battery in [0.19, 0.20, 0.21, 1.0] {
                    let result = IconRenderer.image(Snapshot(battery: battery, charging: charging, plugged: true, volume: 0.5), animate: false, size: 100, dark: dark)
                    let bitmap = NSBitmapImageRep(data: result.tiffRepresentation!)!
                    func check(_ x: Int, _ y: Int, _ rgb: [Int]) {
                        let px = (50 + (Double(x)-50)*1.06) * Double(bitmap.pixelsWide) / 100
                        let py = (50 + (Double(y)-45.5)*1.06) * Double(bitmap.pixelsHigh) / 100
                        let color = bitmap.colorAt(x: Int(px), y: Int(py))!.usingColorSpace(.sRGB)!
                        // Render the reference through the same destination color profile as the icon.
                        let swatch = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
                            NSColor(srgbRed: CGFloat(rgb[0])/255, green: CGFloat(rgb[1])/255, blue: CGFloat(rgb[2])/255, alpha: 1).setFill()
                            rect.fill()
                            return true
                        }
                        let expected = NSBitmapImageRep(data: swatch.tiffRepresentation!)!.colorAt(x: 0, y: 0)!.usingColorSpace(.sRGB)!
                        for (actual, target) in zip([color.redComponent, color.greenComponent, color.blueComponent], [expected.redComponent, expected.greenComponent, expected.blueComponent]) {
                            assert(abs(actual - target) < 3/255, "Ring color: charging=\(charging), battery=\(battery), dark=\(dark), point=\(x),\(y)")
                        }
                    }
                    check(15, 53, charging ? [40,205,80] : battery < 0.2 ? [255,59,65] : foreground)
                    check(50, 8, battery == 1 ? (charging ? [40,205,80] : foreground) : charging ? [15,58,35] : track)
                    check(31, 77, foreground)
                    check(69, 77, track)
                }
            }
        }
        let scenes = Scene.allCases.filter { $0 != .live }
        assert(scenes.count == 16)
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
        // Render edge cases at native size, including unknown values and three digits.
        for battery in [0.0, 0.12, 1.0] {
            let result = IconRenderer.image(Snapshot(battery:battery),animate:false,size:22)
            assert(result.size == NSSize(width:22,height:22))
        }
        print("PASS: 16 states and native-size boundary renders")
    }
}
