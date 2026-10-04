import SwiftUI
import AppKit

struct EnergyAppsSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: EnergyApps
    let limit: Int
    let openActivityMonitor: () -> Void
    @Environment(\.comboPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("高耗能应用")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(L("耗电应用"), action: openActivityMonitor).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(palette.accent)
            }
            switch control.state {
            case .loading:
                Text(L("正在获取能耗信息…")).foregroundStyle(palette.mutedText)
            case .unavailable:
                Text(L("暂时无法获取能耗信息")).foregroundStyle(palette.mutedText)
            case .available(let apps):
                if apps.isEmpty {
                    Text(L("没有使用大量能耗的 App")).foregroundStyle(palette.mutedText)
                } else {
                    ForEach(Array(apps.prefix(EnergyApps.displayLimit(limit)))) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                            }
                            Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1).help(app.name)
                        }.frame(minHeight: 40).accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .font(.caption)
    }
}
struct ChargeFullSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: ChargeControl
    let eligible: Bool
    let expectedLimit: ChargeLimit
    let action: () -> Void
    @Environment(\.comboPalette) private var palette
    private var enabled: Bool {
        guard eligible, !control.busy, control.snapshot?.canRequest == true,
              case .value(let limit) = expectedLimit else { return false }
        return control.snapshot?.limit == limit
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("充电上限")).font(.system(size: 13, weight: .semibold))
            HStack {
                Text(L("当前上限")).foregroundStyle(palette.mutedText)
                Text(expectedLimit.text).fontWeight(.medium)
                Spacer(minLength: 4)
                Button(L("立即充满电"), action: action).buttonStyle(PanelButtonStyle(prominent: true)).disabled(!enabled)
            }.frame(minHeight: 40)
            Text(!control.busy && !enabled ? L("仅在接电且手动上限暂停充电时可用。")
                 : L("临时解除手动上限。恢复由 macOS 管理，退出 Combo 不会取消。"))
                .font(.system(size: 11)).foregroundStyle(palette.mutedText)
                .frame(minHeight: 28, alignment: .topLeading)
        }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
    }
}

struct PowerModeSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: PowerModeControl
    let source: PowerSource?
    let refresh: () -> Void
    @Environment(\.comboPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("能耗模式")).font(.system(size: 13, weight: .semibold))
            if let source, let policy = control.policies[source] {
                Text(source == .adapter ? L("连接电源时") : L("使用电池时")).font(.system(size: 12))
                Picker(source.title, selection: Binding(get: { policy.mode }, set: { mode in
                    Task { await control.set(mode, source: source); refresh() }
                })) {
                    ForEach(PowerMode.allCases.filter { policy.supportsHigh || $0 != .high }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.pickerStyle(.segmented).labelsHidden().disabled(control.busy)
                Text(L("更改需要管理员授权。")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
            } else {
                Text(control.busy ? L("正在读取能耗模式…") : L("能耗模式无法读取，请打开电池设置。"))
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
        }
    }
}

struct BatteryDetail: View {
    @ObservedObject var store: Store
    @ObservedObject private var battery: BatteryStore
    @ObservedObject private var charge: ChargeControl
    @ObservedObject private var power: PowerModeControl
    @Environment(\.comboPalette) private var palette
    init(store: Store) {
        self.store = store; battery = store.battery; charge = store.battery.chargeControl; power = store.battery.powerMode
    }
    var body: some View {
        let snapshot = store.snapshot
        let live = store.scene == .live
        VStack(alignment: .leading, spacing: PanelGeometry.groupSpacing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ComboIcon(snapshot: Snapshot(battery: snapshot.battery, charging: snapshot.charging, plugged: snapshot.plugged, symbol: ""), animate: false, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.batteryText).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit().tracking(-0.64)
                        Text(live ? battery.statusText : (snapshot.charging ? L("正在充电") : snapshot.plugged ? L("电源适配器") : L("正在使用电池")))
                            .font(.system(size: 12)).foregroundStyle(palette.mutedText).lineLimit(2)
                    }
                }
                BatteryLimitGauge(level: live ? battery.level : snapshot.battery, limit: live ? battery.chargeLimit : .unknown,
                                  blocked: live && battery.limitBlocked == true)
                Divider()
                DetailFacts(facts: [(L("电源"), live ? battery.sourceText : snapshot.plugged ? L("电源适配器") : L("电池")),
                                    (L("健康"), live ? LKey(battery.health) : "—"),
                                    (L("低电量模式"), live ? (battery.lowPowerMode ? L("开") : L("关")) : "—")])
            }.modifier(DetailWell())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("电池") + " " + snapshot.batteryText + "，" + (live ? battery.sourceText + "，" + battery.statusText
                                    + "，" + L("健康") + " " + LKey(battery.health) + "，" + L("低电量模式") + " " + (battery.lowPowerMode ? L("开") : L("关"))
                                    + "，" + L("充电上限") + " " + battery.chargeLimit.text : L("演示数据")))
            situation
            if live {
                if battery.hasInternalBattery && battery.level != nil {
                    ChargeFullSection(control: charge, eligible: battery.canRequestFullCharge(scene: store.scene),
                                      expectedLimit: battery.chargeLimit, action: { battery.requestFullCharge(scene: store.scene) })
                    PowerModeSection(control: power, source: battery.onAC.map { $0 ? .adapter : .battery }) { battery.refreshBattery() }
                }
                EnergyAppsSection(control: battery.energyApps, limit: battery.energyAppLimit, openActivityMonitor: { store.openActivityMonitor() })
            }
            DetailMore {
                Button(L("电池设置…")) { store.openSystemSettings("battery") }.buttonStyle(.plain)
                Text(L("充电上限与能耗模式说明")).fontWeight(.medium)
                Text(L("临时解除手动上限。恢复由 macOS 管理，退出 Combo 不会取消。"))
                Text(L("更改需要管理员授权，仅影响\(battery.onAC == true ? PowerSource.adapter.title : PowerSource.battery.title)时的设置。"))
            }
        }
    }
    @ViewBuilder private var situation: some View {
        if !store.message.isEmpty {
            DetailSituation(text: store.message.string, warning: true)
        }
        if store.scene != .live {
            DetailSituation(text: L("演示数据 · 不改变系统状态"), actionTitle: L("返回本机状态"), action: { store.scene = .live })
        } else if !battery.hasInternalBattery || battery.level == nil {
            DetailSituation(text: L("本机没有可读取的内置电池。"))
        } else {
            let rows = Self.operationFeedback(chargeBusy: charge.busy, chargeMessage: charge.message.string,
                                              powerBusy: power.busy, powerMessage: power.message.string)
            ForEach(rows.indices, id: \.self) { rows[$0] }
            if rows.isEmpty {
                if charge.snapshot?.supported != true {
                    DetailSituation(text: L("当前系统无法提供此操作。"), actionTitle: L("电池设置…"), action: { store.openSystemSettings("battery") })
                } else if case .unknown = battery.chargeLimit {
                    DetailSituation(text: L("无法读取充电上限，立即充满电不可用。"))
                }
            }
        }
    }
    /// Neither operation's persisted result can mask the other operation's progress or result.
    static func operationFeedback(chargeBusy: Bool, chargeMessage: String, powerBusy: Bool, powerMessage: String) -> [DetailSituation] {
        var rows: [DetailSituation] = []
        if chargeBusy || !chargeMessage.isEmpty {
            rows.append(DetailSituation(text: chargeMessage.isEmpty ? L("正在检查充电状态…") : chargeMessage, busy: chargeBusy))
        }
        if powerBusy || !powerMessage.isEmpty {
            rows.append(DetailSituation(text: powerMessage.isEmpty ? L("正在读取能耗模式…") : powerMessage, busy: powerBusy))
        }
        return rows
    }
}

struct BatteryLimitGauge: View {
    @Environment(\.comboPalette) private var palette
    let level: Double?
    let limit: ChargeLimit
    let blocked: Bool
    private var marker: Double? {
        guard let level, case .value(let limit) = limit, limit < 100, level < 1 else { return nil }
        return Double(limit) / 100
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 3)
                if let level { Capsule().fill(palette.accent).frame(width: proxy.size.width * min(1, max(0, level)), height: 3) }
                if let marker {
                    Rectangle().fill(Color.primary.opacity(0.45)).frame(width: 1.5, height: 9).offset(x: proxy.size.width * marker - 0.75)
                    if blocked {
                        Canvas { context, size in
                            let start = size.width * marker + 3
                            guard start < size.width else { return }
                            for x in stride(from: start, to: size.width, by: 5) {
                                var path = Path(); path.move(to: CGPoint(x: x, y: 3)); path.addLine(to: CGPoint(x: x + 2, y: 0))
                                context.stroke(path, with: .color(palette.mutedText), lineWidth: 1)
                            }
                        }.frame(height: 3)
                    }
                }
            }.frame(height: 9)
        }.frame(height: 9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("电量") + " " + (level.map { "\(Int(($0 * 100).rounded()))%" } ?? "—") + "，" + L("充电上限") + " " + limit.text)
    }
}
