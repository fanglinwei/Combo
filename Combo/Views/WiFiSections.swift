import SwiftUI
import AppKit

struct HotspotStatusIcons: View {
    let signal: Int?
    let battery: Int?
    var body: some View {
        HStack(spacing: 7) {
            if let signal {
                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.secondary.opacity(index < signal ? 1 : 0.3))
                            .frame(width: 3, height: CGFloat(4 + index * 3))
                    }
                }.frame(height: 13)
            }
            if let battery {
                HStack(spacing: 1) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.secondary.opacity(0.8), lineWidth: 1)
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.secondary.opacity(0.25))
                                .frame(width: 21 * CGFloat(battery) / 100)
                            Spacer(minLength: 0)
                        }.frame(width: 21, height: 9)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        Text("\(battery)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.primary.opacity(0.85))
                    }.frame(width: 25, height: 13)
                    Capsule().fill(Color.secondary.opacity(0.8)).frame(width: 1.5, height: 5)
                }
            }
        }.fixedSize()
    }
}

struct PersonalHotspotSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: HotspotControl
    let openSettings: () -> Void
    @Environment(\.comboPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L("个人热点")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: openSettings) { Image(systemName: "arrow.up.forward") }
                    .buttonStyle(PanelIconButtonStyle()).accessibilityLabel(L("打开个人热点系统设置"))
                    .help(L("打开系统 Wi‑Fi 设置"))
            }
            switch control.state {
            case .loading:
                Text(L("正在查找个人热点…")).foregroundStyle(palette.mutedText)
            case .unavailable:
                HStack {
                    Text(L("暂时无法读取手机信息")).foregroundStyle(palette.mutedText)
                    Button(L("重试")) { control.start() }.buttonStyle(.plain)
                }
            case .available(let phones):
                if phones.isEmpty {
                    Text(L("未发现可用个人热点")).foregroundStyle(palette.mutedText)
                }
                ForEach(phones) { phone in
                    Button(action: openSettings) {
                        HStack(spacing: 9) {
                            Image(systemName: "personalhotspot")
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.08), in: Circle())
                            Text(phone.name).lineLimit(1).help(phone.name)
                            Spacer(minLength: 4)
                            HotspotStatusIcons(signal: phone.signal, battery: phone.battery)
                                .accessibilityHidden(true)
                        }
                    }.buttonStyle(PanelRowButtonStyle())
                        .accessibilityLabel(phone.name
                            + (phone.signal.map { L("，蜂窝信号等级 \($0)") } ?? "")
                            + (phone.battery.map { L("，电量 \($0)%") } ?? ""))
                        .accessibilityHint(L("打开系统 Wi‑Fi 设置，由你选择连接"))
                        .help(L("在系统 Wi‑Fi 设置中连接此手机"))
                }
            }
        }.font(.caption)
    }
}

struct WiFiSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var wifi: WiFiControl
    let hotspots: HotspotControl
    let connection: String
    let active: Bool
    let systemMessage: String
    let openSettings: () -> Void
    @Environment(\.comboPalette) private var palette
    private var known: [WiFiChoice] { wifi.networks.filter { !wifi.isConnected($0) && wifi.knownNames?.contains($0.name) == true } }
    private var others: [WiFiChoice] { wifi.networks.filter { !wifi.isConnected($0) && wifi.knownNames?.contains($0.name) != true } }
    private var name: String {
        if wifi.powerOn == false { return L("Wi‑Fi 已关闭") }
        if wifi.powerOn == nil { return L("Wi‑Fi 不可用") }
        return wifi.currentSSID ?? (wifi.nameAccess ? L("未连接或网络名称暂不可用") : L("名称不可用"))
    }
    private var status: String {
        if wifi.powerOn == false { return L("打开 Wi‑Fi 后可查看网络。") }
        if wifi.powerOn == nil { return L("当前系统未提供 Wi‑Fi 接口。") }
        if !wifi.nameAccess { return L("允许定位后显示网络名称") }
        return wifi.currentSSID == nil ? L("未连接") : L("已连接")
    }
    private var security: String {
        switch wifi.currentSecurity {
        case .wpa3Personal, .wpa3Enterprise: "WPA3"
        case .wpa3Transition: "WPA2/WPA3"
        case .wpa2Personal, .wpa2Enterprise: "WPA2"
        case .wpaPersonalMixed, .wpaEnterpriseMixed: "WPA/WPA2"
        case .wpaPersonal, .wpaEnterprise: "WPA"
        case .WEP, .dynamicWEP: "WEP"
        case .OWE, .oweTransition: "OWE"
        case .none: L("开放")
        default: "—"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PanelGeometry.groupSpacing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    WiFiIcon(level: WiFiChoice.signalLevel(wifi.currentRSSI) ?? 0).frame(width: 32, height: 32).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).help(name)
                        Text(status).font(.system(size: 12)).foregroundStyle(palette.mutedText)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: openSettings) { Image(systemName: "arrow.up.forward") }
                        .buttonStyle(PanelIconButtonStyle()).accessibilityLabel(L("打开系统 Wi‑Fi 设置"))
                        .help(L("打开系统 Wi‑Fi 设置"))
                }
                Divider()
                DetailFacts(facts: [(L("信号"), wifi.currentSSID == nil ? "—" : WiFiChoice.signalLevel(wifi.currentRSSI).map { "\($0)/3" } ?? "—"),
                                    (L("安全性"), wifi.currentSSID == nil ? "—" : security), (L("默认路径"), connection)])
            }.modifier(DetailWell()).accessibilityElement(children: .contain)
            situation
            if wifi.powerOn == true {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(L("已知网络")).font(.system(size: 13, weight: .semibold))
                        if wifi.hasScanned && wifi.knownNames == nil {
                            Spacer(minLength: 4)
                            Text(L("暂时无法区分已知网络。")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                        }
                    }
                    ForEach(known) { networkRow($0) }
                    if known.isEmpty { Text("—").font(.system(size: 11)).foregroundStyle(palette.mutedText).padding(.vertical, 6) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(L("附近网络")).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(wifi.hasScanned ? L("刷新网络") : L("查找网络")) { wifi.scan() }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(palette.accent).disabled(wifi.busy)
                    }
                    ForEach(others) { networkRow($0) }
                    if others.isEmpty {
                        Text(wifi.hasScanned ? L("未发现其他网络") : L("点击“查找网络”获取列表"))
                            .font(.system(size: 11)).foregroundStyle(palette.mutedText).padding(.vertical, 6)
                    }
                }
                PersonalHotspotSection(control: hotspots, openSettings: openSettings)
            }
            DetailMore {
                Button(L("Wi‑Fi 设置…"), action: openSettings).buttonStyle(.plain)
                Text(L("仅展示无线网络信息；请在系统 Wi‑Fi 设置中连接或开关 Wi‑Fi。"))
                if !wifi.nameAccess { Text(L("系统设置 → 隐私与安全性 → 定位服务 → Combo")) }
            }
        }
        .task(id: active) {
            guard active else { return }
            wifi.scan(requestAccess: false)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                if !wifi.busy { wifi.refresh() }
            }
        }
    }
    @ViewBuilder private var situation: some View {
        let rows = Self.feedback(wifi: wifi, systemMessage: systemMessage)
        ForEach(rows.indices, id: \.self) { rows[$0] }
    }
    /// Operation results and permission recovery remain visible independently.
    static func feedback(wifi: WiFiControl, systemMessage: String) -> [DetailSituation] {
        var rows: [DetailSituation] = []
        if !systemMessage.isEmpty {
            rows.append(DetailSituation(text: systemMessage, warning: true))
        }
        if wifi.busy {
            rows.append(DetailSituation(text: wifi.message.isEmpty ? L("正在处理 Wi‑Fi 操作") : wifi.message.string, busy: true))
            return rows
        }
        if !wifi.message.isEmpty {
            rows.append(DetailSituation(text: wifi.message.string, warning: wifi.scanFailed,
                                        actionTitle: wifi.scanFailed ? L("重试") : nil, action: wifi.scanFailed ? { wifi.scan() } : nil))
        } else if wifi.powerOn == nil {
            rows.append(DetailSituation(text: L("当前系统未提供 Wi‑Fi 接口。")))
        } else if let warning = WiFiChoice.warning(for: wifi.currentSecurity) {
            rows.append(DetailSituation(text: warning, warning: true))
        }
        if wifi.powerOn == true && !wifi.nameAccess {
            rows.append(DetailSituation(text: L("需要定位权限才能读取网络名称和附近网络。"),
                                        actionTitle: wifi.locationAuthorizationStatus == .notDetermined ? L("请求定位权限") : L("打开系统设置"), action: {
                if wifi.locationAuthorizationStatus == .notDetermined { wifi.requestLocationAccess() }
                else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
            }))
        }
        return rows
    }
    private func networkRow(_ choice: WiFiChoice) -> some View {
        Button(action: openSettings) {
            HStack(spacing: 9) {
                WiFiIcon(level: WiFiChoice.signalLevel(choice.network.rssiValue) ?? 0)
                    .frame(width: 28, height: 28).background(Color.primary.opacity(0.08), in: Circle()).accessibilityHidden(true)
                Text(choice.name).font(.system(size: 13, weight: .medium)).lineLimit(1).help(choice.name)
                Spacer(minLength: 4)
                if choice.secure { Image(systemName: "lock.fill").foregroundStyle(palette.mutedText) }
                Text(WiFiChoice.signalLevel(choice.network.rssiValue).map { "\($0)/3" } ?? "—").font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
        }.buttonStyle(PanelRowButtonStyle())
            .accessibilityLabel(L("\(choice.name)，\(choice.secure ? L("需要密码，") : "")\(WiFiChoice.signalLevel(choice.network.rssiValue).map { L("信号 \($0) 格") } ?? L("信号未知"))"))
            .accessibilityHint(L("打开系统 Wi‑Fi 设置，由你选择连接"))
            .help(L("在系统设置中连接"))
    }
}
