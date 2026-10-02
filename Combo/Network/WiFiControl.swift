import AppKit
import CoreLocation
import CoreWLAN
import LocalAuthentication
import Security

struct WiFiChoice: Identifiable {
    let network: CWNetwork
    let name: String
    var id: String { "\(security.rawValue):\(name)" }
    var security: CWSecurity {
        [.wpa3Transition, .wpa3Personal, .wpa3Enterprise, .oweTransition, .OWE,
         .wpa2Personal, .wpa2Enterprise, .wpaPersonalMixed, .wpaEnterpriseMixed,
         .wpaPersonal, .wpaEnterprise, .dynamicWEP, .WEP, .none]
            .first(where: network.supportsSecurity) ?? .unknown
    }
    var secure: Bool { ![.none, .OWE, .oweTransition, .unknown].contains(security) }
    var requiresSystemJoin: Bool {
        [.wpa3Enterprise, .wpa2Enterprise, .wpaEnterpriseMixed, .wpaEnterprise, .dynamicWEP, .unknown].contains(security)
    }
    static func warning(for security: CWSecurity) -> String? {
        switch security {
        case .WEP, .dynamicWEP, .wpaPersonal, .wpaEnterprise, .wpaPersonalMixed, .wpaEnterpriseMixed:
            return L("低安全性：此网络支持旧式加密。")
        case .none: return L("开放网络：无线连接未加密。")
        default: return nil
        }
    }
    static func signalLevel(_ rssi: Int) -> Int? {
        guard rssi < 0 else { return nil }
        return rssi >= -60 ? 3 : rssi >= -75 ? 2 : 1
    }
    static func choices(from found: [CWNetwork], connectedBSSID: String?) -> [WiFiChoice] {
        var best: [String: WiFiChoice] = [:]
        func connected(_ network: CWNetwork) -> Bool {
            guard let bssid = network.bssid, let connectedBSSID else { return false }
            return bssid.caseInsensitiveCompare(connectedBSSID) == .orderedSame
        }
        for network in found {
            guard let name = network.ssid, !name.isEmpty else { continue }
            let choice = WiFiChoice(network: network, name: name)
            if let previous = best[choice.id] {
                if connected(previous.network) { continue }
                if !connected(network) && network.rssiValue <= previous.network.rssiValue { continue }
            }
            best[choice.id] = choice
        }
        return best.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

enum WiFiPasswordLookup: Equatable {
    case found(String), unavailable, cancelled

    static func find(ssid: Data, lookup: (CWKeychainDomain, Data) -> (OSStatus, String?) = { domain, ssid in
        var password: NSString?
        let status = CWKeychainFindWiFiPassword(domain, ssid, &password)
        return (status, password as String?)
    }) -> Self {
        guard !ssid.isEmpty else { return .unavailable }
        for domain in [CWKeychainDomain.user, .system] {
            let (status, password) = lookup(domain, ssid)
            if status == errSecSuccess {
                return password.flatMap { $0.isEmpty ? nil : .found($0) } ?? .unavailable
            }
            if status == errSecUserCanceled || status == errSecAuthFailed { return .cancelled }
            // Only absence permits another domain; access failures must not cause another prompt.
            if status != errSecItemNotFound { return .unavailable }
        }
        return .unavailable
    }
}

@MainActor final class WiFiControl: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var powerOn: Bool?
    @Published var networks: [WiFiChoice] = []
    @Published var busy = false
    @Published private(set) var connecting = false
    @Published var message: LocalizedText = ""
    @Published var currentSSID: String?
    @Published var currentBSSID: String?
    @Published var currentRSSI = 0
    @Published var currentSecurity: CWSecurity = .unknown
    @Published var knownNames: Set<String>?
    @Published var hasScanned = false
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var passwordRequest: WiFiChoice?
    @Published private(set) var systemAccessDeclined = false
    @Published var useSystemPasswords: Bool {
        didSet {
            defaults.set(useSystemPasswords, forKey: "wifiUseSystemPasswords")
            passwordRequestGeneration += 1
        }
    }
    private let defaults: UserDefaults
    private let systemPassword: (Data) -> WiFiPasswordLookup
    private let associate: (CWNetwork, String?) throws -> Void
    private var passwordRequestGeneration = 0
    private let location = CLLocationManager()
    private var interface: CWInterface? { CWWiFiClient.shared().interface() }
    private var keychainService: String { "\(Bundle.main.bundleIdentifier ?? "local.combo.preview").wifi" }
    private var scanAfterAuthorization = false

    init(defaults: UserDefaults = .standard,
         systemPassword: @escaping (Data) -> WiFiPasswordLookup = { WiFiPasswordLookup.find(ssid: $0) },
         associate: @escaping (CWNetwork, String?) throws -> Void = { network, password in
             guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
                 throw NSError(domain: "Combo.WiFi", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Wi‑Fi 已关闭或接口不可用。")])
             }
             try interface.associate(to: network, password: password)
         }) {
        self.defaults = defaults; self.systemPassword = systemPassword; self.associate = associate
        useSystemPasswords = defaults.object(forKey: "wifiUseSystemPasswords") as? Bool ?? true
        super.init(); location.delegate = self
        locationAuthorizationStatus = location.authorizationStatus
    }

    func allowSystemPasswordRequests() {
        systemAccessDeclined = false
        useSystemPasswords = true
    }

    func join(_ choice: WiFiChoice) {
        guard !busy, powerOn == true else { return }
        passwordRequest = nil; message = ""
        guard choice.secure, !choice.requiresSystemJoin, knownNames?.contains(choice.name) == true,
              useSystemPasswords, !systemAccessDeclined,
              let ssid = choice.network.ssidData, !ssid.isEmpty else {
            passwordRequest = choice
            return
        }
        busy = true; message = "正在获取所选网络的密码；macOS 可能请求钥匙串授权…"
        let generation = passwordRequestGeneration, lookup = systemPassword
        Task.detached { [weak self] in
            let result = lookup(ssid)
            await self?.finishPasswordLookup(result, choice: choice, generation: generation)
        }
    }

    private func finishPasswordLookup(_ result: WiFiPasswordLookup, choice: WiFiChoice, generation: Int) {
        busy = false
        guard generation == passwordRequestGeneration, useSystemPasswords, powerOn == true else {
            passwordRequest = choice; message = "授权设置或 Wi‑Fi 状态已改变，未继续连接。"
            return
        }
        switch result {
        case .found(let secret):
            startConnection(choice, secret: secret, passwordToSave: nil)
        case .cancelled:
            systemAccessDeclined = true; passwordRequest = choice
            message = "未获授权，未切换网络。本次运行不再请求；可手动输入，或在 Combo 设置中重新允许请求。"
        case .unavailable:
            passwordRequest = choice
            message = "未能获取系统保存的密码，请手动输入，或使用 Combo 已记住的密码。"
        }
    }
    var nameAccess: Bool { locationAuthorizationStatus == .authorizedAlways }
    func requestLocationAccess() {
        guard locationAuthorizationStatus == .notDetermined else { return }
        location.requestWhenInUseAuthorization()
    }
    func refresh() {
        locationAuthorizationStatus = location.authorizationStatus
        let interface = interface
        powerOn = interface?.powerOn()
        currentSSID = nameAccess && powerOn == true ? interface?.ssid() : nil
        currentBSSID = nameAccess && powerOn == true ? interface?.bssid() : nil
        currentRSSI = currentSSID != nil ? interface?.rssiValue() ?? 0 : 0
        currentSecurity = currentSSID != nil ? interface?.security() ?? .unknown : .unknown
        if !nameAccess || powerOn != true { networks = []; knownNames = nil; hasScanned = false }
    }
    func isConnected(_ choice: WiFiChoice) -> Bool {
        guard let bssid = choice.network.bssid, let currentBSSID else { return false }
        return bssid.caseInsensitiveCompare(currentBSSID) == .orderedSame
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            locationAuthorizationStatus = manager.authorizationStatus
            refresh()
            if scanAfterAuthorization && nameAccess { scanAfterAuthorization = false; scan() }
        }
    }

    func setPower(_ on: Bool) {
        guard let interface, !busy else { return }
        busy = true
        Task.detached { [weak self] in
            let result = Result { try interface.setPower(on) }
            await self?.finishPower(result, on: on)
        }
    }

    func scan(requestAccess: Bool = true) {
        guard !busy else { return }
        refresh()
        guard let interface, powerOn == true, !busy else { return }
        switch locationAuthorizationStatus {
        case .notDetermined:
            guard requestAccess else { return }
            scanAfterAuthorization = true
            requestLocationAccess()
            message = "请允许定位以显示附近网络；授权后会自动查找。"
            return
        case .authorizedAlways, .authorizedWhenInUse: break
        default:
            scanAfterAuthorization = false
            message = "无法读取网络名称。请在系统设置中允许 Combo 使用定位，或打开 Wi‑Fi 设置。"
            return
        }
        busy = true; message = "正在查找网络…"
        Task.detached { [weak self] in
            let result = Result { try interface.scanForNetworks(withSSID: nil) }
            let known = interface.configuration().map { Set(($0.networkProfiles.array as? [CWNetworkProfile] ?? []).compactMap(\.ssid)) }
            await self?.finishScan(result, known: known)
        }
    }

    func connect(_ choice: WiFiChoice, password: String, remember: Bool) {
        guard powerOn == true, !busy else { return }
        guard !choice.requiresSystemJoin else { message = "此网络需要使用系统 Wi‑Fi 设置连接。"; return }
        let secret = choice.secure ? (password.isEmpty ? savedPassword(for: choice.id) : password) : nil
        guard !choice.secure || secret?.isEmpty == false else { message = "请输入网络密码。"; return }
        startConnection(choice, secret: secret, passwordToSave: remember && !password.isEmpty ? password : nil)
    }

    private func startConnection(_ choice: WiFiChoice, secret: String?, passwordToSave: String?) {
        busy = true; connecting = true; message = "正在连接 \(choice.name)…"
        let associate = associate
        Task.detached { [weak self] in
            let result = Result { try associate(choice.network, secret) }
            await self?.finishConnection(result, choice: choice, passwordToSave: passwordToSave)
        }
    }

    private func finishPower(_ result: Result<Void, Error>, on: Bool) {
        busy = false; refresh()
        if case .failure(let error) = result { message = "Wi‑Fi 开关失败：\(error.localizedDescription)" }
        else { message = ""; if on { scan(requestAccess: false) } }
    }
    private func finishScan(_ result: Result<Set<CWNetwork>, Error>, known: Set<String>?) {
        busy = false; refresh()
        guard powerOn == true, nameAccess else { return }
        switch result {
        case .success(let found):
            networks = WiFiChoice.choices(from: Array(found), connectedBSSID: currentBSSID)
            knownNames = known; hasScanned = true
            message = networks.isEmpty ? "未发现可显示的网络；可在系统 Wi‑Fi 设置中查看。" : ""
        case .failure(let error):
            networks = []; knownNames = nil; hasScanned = false
            message = "查找网络失败：\(error.localizedDescription)"
        }
    }
    private func finishConnection(_ result: Result<Void, Error>, choice: WiFiChoice, passwordToSave: String?) {
        busy = false
        defer { connecting = false }
        switch result {
        case .success:
            let saved = !choice.secure || passwordToSave.map { savePassword($0, for: choice.id) } ?? true
            passwordRequest = nil
            message = saved ? "已连接 \(choice.name)" : "已连接，但无法把密码存入钥匙串。"
            refresh()
        case .failure(let error):
            passwordRequest = choice
            message = "连接失败：\(error.localizedDescription)；可重新输入密码。"
        }
    }

    func hasSavedPassword(for choice: WiFiChoice) -> Bool { savedPassword(for: choice.id) != nil }
    func deletePassword(for choice: WiFiChoice) {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: choice.id] as CFDictionary)
        message = status == errSecSuccess || status == errSecItemNotFound
            ? "已删除 \(choice.name) 在 Combo 钥匙串中的密码。" : "无法删除密码，请重试。"
    }
    private func savedPassword(for name: String) -> String? {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService,
                                      kSecAttrAccount: name, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
                                      kSecUseAuthenticationContext: context]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    @discardableResult private func savePassword(_ password: String, for name: String) -> Bool {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: name]
        let data = Data(password.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData] = data
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
