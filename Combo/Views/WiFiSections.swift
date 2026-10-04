import SwiftUI
import AppKit

struct WiFiPasswordSettings: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var wifi: WiFiControl
    @State private var showExplanation = false
    @Environment(\.comboPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsToggleRow(title: L("使用系统保存的 Wi‑Fi 密码"), isOn: $wifi.useSystemPasswords)
            Text(L("连接已知网络时使用；macOS 可能另行请求授权。"))
                .font(.system(size: 12)).foregroundStyle(palette.mutedText)
            DisclosureGroup(L("密码与隐私说明"), isExpanded: $showExplanation) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("开启此开关不代表已获系统授权。下次点击已知网络时，macOS 可能询问是否允许访问该密码；可选择允许一次、始终允许或拒绝。"))
                    Text(L("拒绝或取消后，本次运行不再请求。关闭开关会停止后续读取，但不会撤销 macOS 已授予的访问权限；如需撤销，可在“钥匙串访问”中管理对应项目。"))
                    Text(L("不授权也可手动输入密码。默认在连接成功后保存到本机的 Combo 钥匙串项目；可取消“在本机记住密码”，也可在连接表单删除 Combo 已存密码。密码不会上传服务器。"))
                    Text(L("只读取你点击的已知网络密码，不读取其他钥匙串项目，不另存系统密码，不上传网络名称或密码。"))
                }.font(.caption).padding(.top, 6)
            }
            Text(L("关闭后停止后续读取，不撤销系统已授予的权限。"))
                .font(.system(size: 12)).foregroundStyle(palette.mutedText)
            if wifi.systemAccessDeclined {
                Text(L("本次运行已停止请求系统密码。"))
                    .font(.system(size: 12)).foregroundStyle(palette.mutedText)
                Button(L("允许下次请求授权")) { wifi.allowSystemPasswordRequests() }.disabled(wifi.busy)
                Text(L("此按钮只恢复请求资格；请回到 Wi‑Fi 面板点击要连接的已知网络。"))
                    .font(.caption).foregroundStyle(palette.mutedText)
            }
        }
    }
}

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
    @Environment(\.panelReduceMotion) private var reduceMotion
    private var selected: WiFiChoice? { wifi.passwordRequest }
    @State private var password = ""
    @State private var remember = true
    @State private var useSavedPassword = false
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
                    Toggle("Wi‑Fi", isOn: Binding(get: { wifi.powerOn ?? false }, set: { wifi.setPower($0) }))
                        .toggleStyle(.switch).labelsHidden().disabled(wifi.powerOn == nil || wifi.busy)
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
                Text(L("密码与钥匙串授权（在 Combo 设置中）"))
                Text(L("重新允许请求会启用“使用系统保存的 Wi‑Fi 密码”。"))
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
        .onChange(of: wifi.powerOn) { _, value in if value != true { clearSelection() } }
        .onChange(of: wifi.networks.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected.id) { clearSelection() }
        }
        .onChange(of: wifi.passwordRequest?.id) { _, _ in resetInput() }
        .onAppear { resetInput() }
        .onDisappear { password = "" }
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
            rows.append(DetailSituation(text: wifi.message.string, warning: wifi.scanFailed || wifi.passwordRequest != nil,
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
        if wifi.systemAccessDeclined {
            rows.append(DetailSituation(text: L("本次运行不再请求系统密码。") + " " + L("重新允许请求会启用“使用系统保存的 Wi‑Fi 密码”。"),
                                        actionTitle: L("重新允许请求"), action: { wifi.allowSystemPasswordRequests() }))
        }
        return rows
    }
    private func clearSelection() { wifi.passwordRequest = nil; resetInput() }
    private func resetInput() {
        password = ""; remember = true
        useSavedPassword = selected.map { $0.secure && !$0.requiresSystemJoin && wifi.hasSavedPassword(for: $0) } ?? false
    }
    private func networkRow(_ choice: WiFiChoice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { clearSelection(); wifi.join(choice) } label: {
                HStack(spacing: 9) {
                    WiFiIcon(level: WiFiChoice.signalLevel(choice.network.rssiValue) ?? 0)
                        .frame(width: 28, height: 28).background(Color.primary.opacity(0.08), in: Circle()).accessibilityHidden(true)
                    Text(choice.name).font(.system(size: 13, weight: .medium)).lineLimit(1).help(choice.name)
                    Spacer(minLength: 4)
                    if choice.secure { Image(systemName: "lock.fill").foregroundStyle(palette.mutedText) }
                    Text(WiFiChoice.signalLevel(choice.network.rssiValue).map { "\($0)/3" } ?? "—").font(.system(size: 11)).foregroundStyle(palette.mutedText)
                }
            }.buttonStyle(PanelRowButtonStyle()).disabled(wifi.busy || wifi.powerOn != true)
                .accessibilityLabel(L("\(choice.name)，\(choice.secure ? L("需要密码，") : "")\(WiFiChoice.signalLevel(choice.network.rssiValue).map { L("信号 \($0) 格") } ?? L("信号未知"))"))
            if selected?.id == choice.id { connectionForm(choice) }
        }.animation(reduceMotion ? nil : Motion.animation(Motion.detailResize), value: selected?.id == choice.id)
    }
    private func connectionForm(_ selected: WiFiChoice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("连接到 \(selected.name)")).font(.system(size: 13, weight: .semibold))
            if selected.requiresSystemJoin {
                Text(L("此网络的认证需要在系统 Wi‑Fi 设置中完成。")).foregroundStyle(palette.mutedText)
                Button(L("在系统设置中连接"), action: openSettings).buttonStyle(PanelButtonStyle(prominent: true))
            } else {
                if let warning = WiFiChoice.warning(for: selected.security) {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if selected.secure {
                    if useSavedPassword {
                        Text(L("使用 Combo 记住的密码")).foregroundStyle(palette.mutedText)
                        Button(L("改用其他密码")) { useSavedPassword = false }.buttonStyle(PanelButtonStyle())
                    } else {
                        SecureField(L("网络密码"), text: $password).textFieldStyle(.roundedBorder)
                            .onSubmit { if !password.isEmpty && !wifi.busy { wifi.connect(selected, password: password, remember: remember) } }
                        Toggle(L("连接成功后在本机记住密码"), isOn: $remember)
                        Text(L("仅存入本机 Combo 钥匙串，不上传服务器。")).foregroundStyle(palette.mutedText)
                    }
                }
                HStack {
                    Button(L("连接")) { wifi.connect(selected, password: password, remember: remember) }
                        .buttonStyle(PanelButtonStyle(prominent: true))
                        .disabled(wifi.busy || (selected.secure && !useSavedPassword && password.isEmpty))
                    if useSavedPassword {
                        Button(L("删除已存密码")) { wifi.deletePassword(for: selected); useSavedPassword = wifi.hasSavedPassword(for: selected) }
                            .buttonStyle(PanelButtonStyle())
                    }
                }
            }
            Button(L("取消")) { clearSelection() }.buttonStyle(PanelButtonStyle()).keyboardShortcut(.cancelAction).disabled(wifi.busy)
        }.font(.system(size: 11)).padding(12).modifier(DetailFloating()).disabled(wifi.busy)
    }
}
