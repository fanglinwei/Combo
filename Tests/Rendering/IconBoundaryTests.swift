import Testing
import AppKit

struct IconBoundaryTests {
    @Test
    @MainActor
    func testExpandedCenterGlyphSizes() throws {
        _ = NSApplication.shared
        let devices = BluetoothFamily.allCases.map { OutputDeviceKind.bluetooth($0) } + [
            .airPlay(.appleTV), .airPlay(.homePod), .airPlay(.homePodMini), .airPlay(.other)
        ]
        let contents = devices.map { device in
            var content = IconContent(kind: .headphones)
            content.glyph = OutputDeviceClassifier.glyph(for: device)
            return content
        } + [
            IconContent(kind: .wifi), IconContent(kind: .wifiOff), IconContent(kind: .warning),
            IconContent(kind: .connecting), IconContent(kind: .plugged), IconContent(kind: .unplugged),
            IconContent(kind: .unavailable), IconContent(kind: .battery, text: "9"),
            IconContent(kind: .battery, text: "82"), IconContent(kind: .battery, text: "100")
        ]
        for content in contents {
            for dark in [false, true] {
                for scale in [1, 2] {
                    let pixels = 22 * scale
                    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                    let frame = IconTransition.Frame(layers: [.init(content: content, emphasis: 1)], peripheral: 0, ringOpacity: 0)
                    IconRenderer.image(Snapshot(), animate: false, size: 22, dark: dark, transition: frame)
                        .draw(in: NSRect(x: 0, y: 0, width: 22, height: 22))
                    NSGraphicsContext.restoreGraphicsState()
                    var minX = pixels, minY = pixels, maxX = -1, maxY = -1
                    for y in 0..<pixels {
                        for x in 0..<pixels where (try #require(bitmap.colorAt(x: x, y: y))).alphaComponent > 0.05 {
                            minX = min(minX, x); maxX = max(maxX, x)
                            minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                    let longest = Double(max(maxX - minX + 1, maxY - minY + 1)) / Double(scale)
                    #expect(maxX - minX + 1 < pixels && maxY - minY + 1 < pixels,
                           "Expanded artwork must fit within the canvas: \(content), \(scale)x")
                    if content.kind == .headphones || content.kind == .unavailable {
                        #expect(minX > 0 && minY > 0 && maxX < pixels - 1 && maxY < pixels - 1,
                               "Enlarged device artwork must leave clearance on every edge: \(content), \(scale)x")
                        // The supplied system AirPods reference is about 34px wide on a 2x menu bar.
                        #expect((16...18).contains(longest), "Expanded device ink must match the system's 17pt size: \(content), \(scale)x")
                    }
                }
            }
        }
    }

    @Test
    @MainActor
    func testChargingGapHasRoundedCaps() throws {
        _ = NSApplication.shared
        // Both sides of the charging gap retain semicircular caps, on track and progress.
        for dark in [true, false] {
            for battery in [0.0, 0.65, 0.8, 0.82, 1.0] {
                let image = IconRenderer.image(Snapshot(battery: battery, charging: true), animate: false, size: 400, dark: dark)
                let imageData = try #require(image.tiffRepresentation)
                let pixels = try #require(NSBitmapImageRep(data: imageData))
                for (angle, direction) in [(300.0, 1.0), (346.0, -1.0)] {
                    let theta = angle * .pi / 180
                    func alpha(_ tangent: Double, _ radial: Double) throws -> Double {
                        let x = 50 + (36 + radial) * cos(theta) - direction * tangent * sin(theta)
                        let y = 44 + (36 + radial) * sin(theta) + direction * tangent * cos(theta)
                        let px = (50 + (x - 50) * 1.06) * Double(pixels.pixelsWide) / 100
                        let py = (50 + (y - 45.5) * 1.06) * Double(pixels.pixelsHigh) / 100
                        return try #require(pixels.colorAt(x: Int(px), y: Int(py))).alphaComponent
                    }
                    #expect(try alpha(2, 0) > 0.9, "Charging cap must extend into the gap")
                    for radial in [-2.5, 2.5] {
                        #expect(try alpha(2, radial) < 0.1, "Charging cap corners must be rounded")
                    }
                }
            }
        }
    }

    @Test
    @MainActor
    func testChargingAndLowBatteryRingColors() throws {
        _ = NSApplication.shared
        for dark in [true, false] {
            let foreground = dark ? [244, 244, 246] : [36, 37, 42]
            let track = dark ? [86, 89, 97] : [167, 170, 179]
            for charging in [false, true] {
                for battery in [0.19, 0.20, 0.21, 1.0] {
                    let result = IconRenderer.image(Snapshot(battery: battery, charging: charging, plugged: true, volume: 0.5), animate: false, size: 100, dark: dark)
                    let imageData = try #require(result.tiffRepresentation)
                    let bitmap = try #require(NSBitmapImageRep(data: imageData))
                    func check(_ x: Int, _ y: Int, _ rgb: [Int]) throws {
                        let px = (50 + (Double(x) - 50) * 1.06) * Double(bitmap.pixelsWide) / 100
                        let py = (50 + (Double(y) - 45.5) * 1.06) * Double(bitmap.pixelsHigh) / 100
                        let pixelColor = try #require(bitmap.colorAt(x: Int(px), y: Int(py)))
                        let color = try #require(pixelColor.usingColorSpace(.sRGB))
                        // Render the reference through the same destination color profile as the icon.
                        let swatch = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
                            NSColor(srgbRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255, blue: CGFloat(rgb[2]) / 255, alpha: 1).setFill()
                            rect.fill()
                            return true
                        }
                        let swatchData = try #require(swatch.tiffRepresentation)
                        let swatchBitmap = try #require(NSBitmapImageRep(data: swatchData))
                        let swatchColor = try #require(swatchBitmap.colorAt(x: 0, y: 0))
                        let expected = try #require(swatchColor.usingColorSpace(.sRGB))
                        for (actual, target) in zip([color.redComponent, color.greenComponent, color.blueComponent], [expected.redComponent, expected.greenComponent, expected.blueComponent]) {
                            #expect(abs(actual - target) < 3 / 255, "Ring color: charging=\(charging), battery=\(battery), dark=\(dark), point=\(x),\(y)")
                        }
                    }
                    try check(15, 53, charging ? [40, 205, 80] : battery < 0.2 ? [255, 59, 65] : foreground)
                    try check(50, 8, battery == 1 ? (charging ? [40, 205, 80] : foreground) : charging ? [15, 58, 35] : track)
                    try check(31, 77, foreground)
                    try check(69, 77, track)
                }
            }
        }
    }

    @Test
    @MainActor
    func testDemoSceneCountAndNativeSizeBoundaries() {
        _ = NSApplication.shared
        let scenes = Scene.allCases.filter { $0 != .live }
        #expect(scenes.count == 16)
        // Render edge cases at native size, including unknown values and three digits.
        for battery in [0.0, 0.12, 1.0] {
            let result = IconRenderer.image(Snapshot(battery: battery),animate: false, size: 22)
            #expect(result.size == NSSize(width: 22, height: 22))
        }
    }
}
