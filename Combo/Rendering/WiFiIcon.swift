import SwiftUI

enum WiFiGlyph {
    static let lineWidth: CGFloat = 4.6
    static let tip: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 46.082, y: 52.318))
        path.addQuadCurve(to: CGPoint(x: 53.918, y: 52.318), control: CGPoint(x: 50, y: 49.568))
        path.addQuadCurve(to: CGPoint(x: 54.241, y: 54.705), control: CGPoint(x: 54.788, y: 52.868))
        path.addLine(to: CGPoint(x: 51.6, y: 57.28))
        path.addQuadCurve(to: CGPoint(x: 48.4, y: 57.28), control: CGPoint(x: 50, y: 58.555))
        path.addLine(to: CGPoint(x: 45.759, y: 54.705))
        path.addQuadCurve(to: CGPoint(x: 46.082, y: 52.318), control: CGPoint(x: 45.212, y: 52.868))
        path.closeSubpath()
        return path
    }()
    static let bounds = CGRect(x: 33.685, y: 33.7, width: 32.63, height: 24.218)
    static func arcs(_ index: Int, open: Double = 1, retracting: Bool = false) -> [[CGPoint]] {
        let radius = index == 0 ? 12.434 : 20.624
        let centerY = index == 0 ? 57.072 : 56.624
        let angle = index == 0 ? 40.1 : 42.81
        let segments = retracting
            ? [(270-angle, 270-angle+angle*open), (270+angle-angle*open, 270+angle)]
            : [(270-angle, 270+angle)]
        return segments.map { start, end in
            (0...40).map { step in
                let theta = (start+(end-start)*Double(step)/40) * .pi/180
                let width = retracting ? 1 : open
                return CGPoint(x: 50+radius*cos(theta)*width, y: centerY-radius+(radius+radius*sin(theta))*width)
            }
        }
    }
}

struct WiFiIcon: View {
    var level = 3
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / WiFiGlyph.bounds.width, y: size.height / WiFiGlyph.bounds.height)
            context.translateBy(x: -WiFiGlyph.bounds.minX, y: -WiFiGlyph.bounds.minY)
            for index in 0..<2 {
                context.opacity = level >= index + 2 ? 1 : 0.25
                for points in WiFiGlyph.arcs(index) {
                    var path = Path(); path.addLines(points)
                    context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: WiFiGlyph.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
            context.opacity = level > 0 ? 1 : 0.25
            context.fill(Path(WiFiGlyph.tip), with: .foreground)
        }
        .frame(width: 16, height: 16 * WiFiGlyph.bounds.height / WiFiGlyph.bounds.width)
        .accessibilityHidden(true)
    }
}

// Coordinates and palette follow docs/assets/render_design.py, on a 100 × 100 canvas.
