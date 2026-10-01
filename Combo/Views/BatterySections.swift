import SwiftUI
import Inject
import AppKit

struct EnergyAppsSection: View {
    @ObserveInjection var inject
    @ObservedObject var control: EnergyApps
    let limit: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("高耗能应用").font(.caption).foregroundStyle(.secondary)
            switch control.state {
            case .loading:
                Text("正在获取能耗信息…").foregroundStyle(.secondary)
            case .unavailable:
                Text("暂时无法获取能耗信息").foregroundStyle(.secondary)
            case .available(let apps):
                if apps.isEmpty {
                    Text("没有使用大量能耗的 App").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(apps.prefix(EnergyApps.displayLimit(limit)))) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                            }
                            Text(app.name).lineLimit(1).help(app.name)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .font(.caption)
    }
}
struct ChargeFullSection: View {
    @ObserveInjection var inject
    @ObservedObject var control: ChargeControl
    let eligible: Bool
    let expectedLimit: ChargeLimit
    let action: () -> Void
    private var enabled: Bool {
        guard eligible, !control.busy, control.snapshot?.canRequest == true,
              case .value(let limit) = expectedLimit else { return false }
        return control.snapshot?.limit == limit
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Button("立即充满电", action: action).disabled(!enabled)
                if control.busy { ProgressView().controlSize(.small).accessibilityLabel("正在检查充电状态") }
            }
            Text("临时解除手动充电上限；恢复由 macOS 管理，退出 Combo 不会取消。")
                .foregroundStyle(.secondary)
            if !control.message.isEmpty {
                Text(control.message).foregroundStyle(.secondary)
            } else if !control.busy && control.snapshot?.supported != true {
                Text("当前系统无法提供此操作，请使用下方电池设置入口。").foregroundStyle(.secondary)
            } else if !control.busy && !enabled {
                Text("仅在接电且手动上限暂停充电时可用。").foregroundStyle(.secondary)
            }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
struct PowerModeSection: View {
    @ObserveInjection var inject
    @ObservedObject var control: PowerModeControl
    let source: PowerSource?
    let refresh: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let source, let policy = control.policies[source] {
                Picker("能耗模式 · \(source.title)", selection: Binding(get: { policy.mode }, set: { mode in
                    Task { await control.set(mode, source: source); refresh() }
                })) {
                    ForEach(PowerMode.allCases.filter { policy.supportsHigh || $0 != .high }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.disabled(control.busy)
                Text("更改需要管理员授权，仅影响\(source.title)时的设置。")
                    .foregroundStyle(.secondary)
            } else {
                Text(control.busy ? "正在读取能耗模式…" : "能耗模式无法读取，请打开电池设置。")
                    .foregroundStyle(.secondary)
            }
            if !control.message.isEmpty {
                Text(control.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.caption)
    }
}

