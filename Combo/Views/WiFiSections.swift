import SwiftUI
import Inject
import AppKit

struct WiFiPasswordSettings: View {
    @ObserveInjection var inject
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var wifi: WiFiControl
    @State private var showExplanation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(L("使用系统保存的 Wi‑Fi 密码"), isOn: $wifi.useSystemPasswords)
            Text(L("仅在你点击已知网络时，读取该网络的密码用于 Wi‑Fi 切换；不读取其他钥匙串项目，不另存系统密码，不上传网络名称或密码。"))
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(L("钥匙串授权与隐私"), isExpanded: $showExplanation) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("开启此开关不代表已获系统授权。下次点击已知网络时，macOS 可能询问是否允许访问该密码；可选择允许一次、始终允许或拒绝。"))
                    Text(L("拒绝或取消后，本次运行不再请求。关闭开关会停止后续读取，但不会撤销 macOS 已授予的访问权限；如需撤销，可在“钥匙串访问”中管理对应项目。"))
                    Text(L("不授权也可手动输入密码。默认在连接成功后保存到本机的 Combo 钥匙串项目；可取消“在本机记住密码”，也可在连接表单删除 Combo 已存密码。密码不会上传服务器。"))
                    Button(L("允许下次请求授权")) { wifi.allowSystemPasswordRequests() }
                        .disabled(wifi.busy)
                    Text(L("此按钮只恢复请求资格；请回到 Wi‑Fi 面板点击要连接的已知网络。"))
                        .foregroundStyle(.secondary)
                }.font(.caption).padding(.top, 6)
            }
            if wifi.systemAccessDeclined {
                Text(L("本次运行已停止请求系统密码。可展开上方授权入口，重新允许下次请求。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct HotspotStatusIcons: View {
    @ObserveInjection var inject
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
    @ObserveInjection var inject
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: HotspotControl
    let openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L("个人热点")).foregroundStyle(.secondary)
                Spacer()
                Button(action: openSettings) { Image(systemName: "arrow.up.forward") }
                    .buttonStyle(.plain).accessibilityLabel(L("打开个人热点系统设置"))
                    .help(L("打开系统 Wi‑Fi 设置"))
            }
            switch control.state {
            case .loading:
                Text(L("正在查找个人热点…")).foregroundStyle(.secondary)
            case .unavailable:
                HStack {
                    Text(L("暂时无法读取手机信息")).foregroundStyle(.secondary)
                    Button(L("重试")) { control.start() }.buttonStyle(.plain)
                }
            case .available(let phones):
                if phones.isEmpty {
                    Text(L("未发现可用个人热点")).foregroundStyle(.secondary)
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
                        }.padding(.vertical, 2).contentShape(Rectangle())
                    }.buttonStyle(.plain)
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
    @ObserveInjection var inject
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var wifi: WiFiControl
    let hotspots: HotspotControl
    let connection: String
    let active: Bool
    let openSettings: () -> Void
    private var selected: WiFiChoice? { wifi.passwordRequest }
    @State private var password = ""
    @State private var remember = true
    @State private var otherExpanded = false
    @State private var useSavedPassword = false
    private var known: [WiFiChoice] { wifi.networks.filter { !wifi.isConnected($0) && wifi.knownNames?.contains($0.name) == true } }
    private var others: [WiFiChoice] { wifi.networks.filter { !wifi.isConnected($0) && wifi.knownNames?.contains($0.name) != true } }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label { Text("Wi‑Fi") } icon: { WiFiIcon() }.font(.headline)
                Spacer()
                if wifi.busy { ProgressView().controlSize(.small).accessibilityLabel(L("正在处理 Wi‑Fi 操作")) }
                Toggle("Wi‑Fi", isOn: Binding(get: { wifi.powerOn ?? false }, set: { wifi.setPower($0) }))
                    .toggleStyle(.switch).labelsHidden().disabled(wifi.powerOn == nil || wifi.busy)
            }
            if wifi.powerOn == true {
                if let name = wifi.currentSSID {
                    networkLabel(name, rssi: wifi.currentRSSI, secure: false, connected: true)
                    if let warning = WiFiChoice.warning(for: wifi.currentSecurity) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text(wifi.nameAccess ? L("未连接或网络名称暂不可用") : L("允许定位后显示网络名称"))
                        .font(.caption).foregroundStyle(.secondary)
                    if !wifi.nameAccess {
                        if wifi.locationAuthorizationStatus == .notDetermined {
                            Button(L("请求定位权限")) { wifi.requestLocationAccess() }.font(.caption)
                        } else {
                            Text(L("系统设置 → 隐私与安全性 → 定位服务 → Combo"))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(L("打开系统设置")) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                            }.font(.caption)
                        }
                    }
                }
                Divider()
                PersonalHotspotSection(control: hotspots, openSettings: openSettings)
                if !known.isEmpty {
                    Divider()
                    Text(L("已知网络")).font(.caption).foregroundStyle(.secondary)
                    ForEach(known) { networkRow($0) }
                }
                Divider()
                DisclosureGroup(isExpanded: $otherExpanded) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(others) { networkRow($0) }
                        if others.isEmpty {
                            Text(wifi.hasScanned ? L("未发现其他网络") : L("点击“查找网络”获取列表"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 5)
                } label: {
                    Text(wifi.knownNames == nil ? L("附近网络") : L("其他网络")).font(.caption)
                }
                HStack {
                    Button(wifi.hasScanned ? L("刷新网络") : L("查找网络")) { wifi.scan() }.disabled(wifi.busy)
                    Spacer()
                    Text(L("默认路径：\(connection)")).foregroundStyle(.secondary)
                }.font(.caption)
                if wifi.hasScanned && wifi.knownNames == nil {
                    Text(L("暂时无法区分已知网络。")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(wifi.powerOn == false ? L("Wi‑Fi 已关闭") : L("Wi‑Fi 接口不可用")).font(.caption).foregroundStyle(.secondary)
            }
            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("连接 \(selected.name)")).font(.caption).fontWeight(.semibold)
                    if selected.requiresSystemJoin {
                        Text(L("此网络的认证需要在系统 Wi‑Fi 设置中完成。")).font(.caption).foregroundStyle(.secondary)
                        Button(L("在系统设置中连接"), action: openSettings).font(.caption)
                    } else {
                        if let warning = WiFiChoice.warning(for: selected.security) {
                            Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                        if selected.secure {
                            if useSavedPassword {
                                Text(L("使用 Combo 记住的密码")).font(.caption).foregroundStyle(.secondary)
                                Button(L("改用其他密码")) { useSavedPassword = false }.font(.caption)
                            } else {
                                SecureField(L("网络密码"), text: $password).textFieldStyle(.roundedBorder)
                                    .onSubmit { if !password.isEmpty && !wifi.busy { wifi.connect(selected, password: password, remember: remember) } }
                                Toggle(L("连接成功后在本机记住密码"), isOn: $remember).font(.caption)
                                Text(L("仅存入本机 Combo 钥匙串，不上传服务器。")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button(L("连接")) { wifi.connect(selected, password: password, remember: remember) }
                                .disabled(wifi.busy || (selected.secure && !useSavedPassword && password.isEmpty))
                            if useSavedPassword {
                                Button(L("删除已存密码")) { wifi.deletePassword(for: selected); useSavedPassword = wifi.hasSavedPassword(for: selected) }
                            }
                        }.font(.caption)
                    }
                    Button(L("取消")) { clearSelection() }.font(.caption).keyboardShortcut(.cancelAction).disabled(wifi.busy)
                }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).disabled(wifi.busy)
            }
            if !wifi.message.isEmpty { Text(wifi.message.string).font(.caption).foregroundStyle(.secondary) }
            Divider()
            Button(L("Wi‑Fi 设置…"), action: openSettings).buttonStyle(.plain).font(.caption)
        }.task(id: active) {
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
    private func clearSelection() { wifi.passwordRequest = nil; resetInput() }
    private func resetInput() {
        password = ""; remember = true
        useSavedPassword = selected.map { $0.secure && !$0.requiresSystemJoin && wifi.hasSavedPassword(for: $0) } ?? false
    }
    private func networkRow(_ choice: WiFiChoice) -> some View {
        Button {
            clearSelection(); wifi.join(choice)
        } label: {
            networkLabel(choice.name, rssi: choice.network.rssiValue, secure: choice.secure, connected: false)
        }.buttonStyle(.plain).disabled(wifi.busy || wifi.powerOn != true)
    }
    private func networkLabel(_ name: String, rssi: Int, secure: Bool, connected: Bool) -> some View {
        let level = WiFiChoice.signalLevel(rssi)
        return HStack(spacing: 9) {
            WiFiIcon(level: level ?? 0)
                .frame(width: 28, height: 28)
                .foregroundStyle(connected ? Color.white : Color.primary)
                .background(connected ? Color.blue : Color.primary.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            Text(name).lineLimit(1).help(name)
            Spacer(minLength: 4)
            if connected { Text(L("已连接")).foregroundStyle(.secondary) }
            if secure { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
        }.font(.caption).padding(.vertical, 2).contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(name)，\(connected ? L("已连接，") : "")\(secure ? L("需要密码，") : "")\(level.map { L("信号 \($0) 格") } ?? L("信号未知"))"))
    }
}
