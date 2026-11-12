import SwiftUI

struct AudioBatterySummary: View {
    let device: AudioBatteryDevice
    var detailed = false
    var stale = false
    var reduceMotion = false

    var body: some View {
        VStack(spacing: detailed ? 20 : 18) {
            HStack(spacing: 34) {
                ForEach(device.gauges(stale: stale)) { gauge in
                    AudioBatteryGaugeView(gauge: gauge, diameter: detailed ? 64 : 44, reduceMotion: reduceMotion)
                }
            }.frame(maxWidth: .infinity)
            if detailed && stale {
                Text(L("电量暂不可用")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.top, detailed ? 10 : 5) // The charging bolt extends above the circle.
    }
}

struct AudioBatteryGaugeView: View {
    let gauge: AudioBatteryGauge
    let diameter: CGFloat
    var reduceMotion = false
    // Also used by offscreen visual tests; live input remains local to this control.
    var showsValue = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    @State private var toggled = false
    @FocusState private var focused: Bool

    private var numeric: Bool { showsValue || hovered || focused || toggled || gauge.percent == nil }
    private var color: Color {
        switch gauge.level {
        case .low: rgb(0xFF3B41)
        case .warning: rgb(scheme == .dark ? 0xFFD60A : 0x906600)
        case .normal: rgb(0x28CD50)
        case .unknown: rgb(scheme == .dark ? 0x565961 : 0xA7AAB3)
        }
    }
    private func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255,
              blue: Double(hex & 255) / 255, opacity: 1)
    }
    var body: some View {
        Button { toggled.toggle() } label: {
            ZStack {
                let lineWidth = diameter * 5.7 / 82
                // Match the reference's 36/82 radius, including its transparent margin.
                Circle().stroke(rgb(scheme == .dark ? 0x565961 : 0xA7AAB3), lineWidth: lineWidth)
                    .frame(width: diameter * 72 / 82, height: diameter * 72 / 82)
                if let percent = gauge.percent, percent > 0 {
                    Circle().trim(from: 0, to: Double(percent) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter * 72 / 82, height: diameter * 72 / 82)
                }
                if let image = AppIcons.image(gauge.icon, pointSize: 32) {
                    Image(nsImage: image).resizable().scaledToFit()
                        // The design's 75% mask contains a symbol fitted to 84/112 of its canvas.
                        .frame(width: diameter * 0.75 * 84 / 112, height: diameter * 0.75 * 84 / 112)
                        .opacity(numeric ? 0 : 1)
                }
                Text(gauge.value)
                    .font(.system(size: diameter * (gauge.value.count == 3 ? 26 : 31) / 82, weight: .medium, design: .rounded))
                    .monospacedDigit().opacity(numeric ? 1 : 0)
            }
            .foregroundStyle(rgb(scheme == .dark ? 0xF4F4F6 : 0x24252A))
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .top) {
                if gauge.charge == .charging || gauge.charge == .full {
                    chargingMark.offset(y: -diameter * 0.109)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain).focusable().focused($focused)
        .onHover { hovered = $0 }
        .onKeyPress(.space) { toggled.toggle(); return .handled }
        .overlay {
            if focused { Circle().stroke(.primary, lineWidth: contrast == .increased ? 3 : 2).padding(-4).allowsHitTesting(false) }
        }
        .animation(reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.1), value: numeric)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gauge.title)
        .accessibilityValue(gauge.accessibilityValue)
        .accessibilityHint(L("点击切换电量数字"))
        .help(gauge.title + " · " + gauge.accessibilityValue)
    }

    @ViewBuilder private var chargingMark: some View {
        if let image = AppIcons.image(.power(.charging), pointSize: 32) {
            let offsets: [CGSize] = [
                .init(width: -1, height: -1), .init(width: 0, height: -1), .init(width: 1, height: -1),
                .init(width: -1, height: 0), .init(width: 1, height: 0),
                .init(width: -1, height: 1), .init(width: 0, height: 1), .init(width: 1, height: 1)
            ]
            ZStack {
                ForEach(offsets.indices, id: \.self) { index in
                    Image(nsImage: image).resizable().scaledToFit().foregroundStyle(rgb(0x17151C))
                        .frame(width: diameter * 0.24 * 56 / 64, height: diameter * 0.24 * 56 / 64)
                        .offset(x: offsets[index].width * diameter * 0.0225, y: offsets[index].height * diameter * 0.0225)
                }
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: diameter * 0.24 * 56 / 64, height: diameter * 0.24 * 56 / 64)
                    .foregroundStyle(gauge.charge == .full ? rgb(0x28CD50) : .white)
            }
            .frame(width: diameter * 0.24, height: diameter * 0.34)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
