import SwiftUI
import AppKit

struct EnergyAppsSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: EnergyApps
    let openActivityMonitor: () -> Void
    @Environment(\.comboPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("使用大量能源的 App")).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.mutedText)
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
                    ForEach(Array(apps.prefix(EnergyApps.displayLimit))) { app in
                        Button(action: openActivityMonitor) {
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 29, height: 29).accessibilityHidden(true)
                                }
                                Text(app.name).font(.system(size: 12)).lineLimit(1).help(app.name)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(palette.mutedText)
                            }.frame(minHeight: 32)
                        }.buttonStyle(PanelRowButtonStyle()).pointerStyle(.link).accessibilityLabel(app.name + "，" + L("耗电应用"))
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
            HStack {
                Text(L("充电上限")).foregroundStyle(palette.mutedText)
                Spacer(minLength: 16)
                Text(expectedLimit.text).monospacedDigit()
                if eligible {
                    Button(L("立即充满电"), action: action).buttonStyle(PanelButtonStyle(prominent: true)).disabled(!enabled)
                }
            }.frame(minHeight: 38)
            if eligible {
                Text(L("临时解除手动上限。恢复由 macOS 管理，退出 Combo 不会取消。"))
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
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
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(L("能耗模式")).font(.system(size: 12)).foregroundStyle(palette.mutedText)
                Spacer(minLength: 16)
                if let source, let policy = control.policies[source] {
                    Picker(source.title, selection: Binding(get: { policy.mode }, set: { mode in
                        Task { await control.set(mode, source: source); refresh() }
                    })) {
                        ForEach(PowerMode.allCases.filter { policy.supportsHigh || $0 != .high }) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }.pickerStyle(.menu).labelsHidden().controlSize(.small).frame(maxWidth: 120).disabled(control.busy)
                }
            }.frame(minHeight: 38)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.separator).frame(height: 0.5) }
            if let source, control.policies[source] != nil {
                Text(L("更改需要管理员授权，仅影响\(source.title)时的设置。"))
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText)
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
            HStack(spacing: 13) {
                CategoryIcon(symbol: "battery.75percent", color: palette.iconGreen, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.batteryText).font(.system(size: 38, weight: .semibold)).monospacedDigit().tracking(-0.95)
                    Text(live ? battery.statusText : (snapshot.charging ? L("正在充电") : snapshot.plugged ? L("电源适配器") : L("正在使用电池")))
                        .font(.system(size: 11)).foregroundStyle(palette.mutedText).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(minHeight: 66).accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 7) {
                Text(L("健康与充电")).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.mutedText)
                DetailFacts(facts: [(L("电池健康"), live ? LKey(battery.health) : "—"),
                                    (L("最大容量"), live ? battery.maximumCapacity.map { "\($0)%" } ?? "—" : "—")])
                Rectangle().fill(palette.separator).frame(height: 0.5)
                ChargeFullSection(control: charge, eligible: battery.canRequestFullCharge(scene: store.scene),
                                  expectedLimit: live ? battery.chargeLimit : .unknown, action: { battery.requestFullCharge(scene: store.scene) })
            }
            situation
            if live {
                if battery.hasInternalBattery && battery.level != nil {
                    PowerModeSection(control: power, source: battery.onAC.map { $0 ? .adapter : .battery }) { battery.refreshBattery() }
                }
                EnergyAppsSection(control: battery.energyApps, openActivityMonitor: { store.openActivityMonitor() })
            }
            DetailFooter(title: L("电池设置")) { store.openSystemSettings("battery") }
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
