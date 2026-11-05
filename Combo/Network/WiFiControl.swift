import AppKit
import CoreLocation
import CoreWLAN

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

@MainActor final class WiFiControl: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var powerOn: Bool?
    @Published var networks: [WiFiChoice] = []
    @Published var busy = false
    @Published var message: LocalizedText = ""
    @Published var currentSSID: String?
    @Published var currentBSSID: String?
    @Published var currentRSSI = 0
    @Published var currentSecurity: CWSecurity = .unknown
    @Published var knownNames: Set<String>?
    @Published var hasScanned = false
    @Published private(set) var scanFailed = false
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private let location = CLLocationManager()
    private var interface: CWInterface? { CWWiFiClient.shared().interface() }
    private var scanAfterAuthorization = false

    init(observesLocationAuthorization: Bool = true) {
        super.init()
        if observesLocationAuthorization { location.delegate = self }
        locationAuthorizationStatus = location.authorizationStatus
    }

    var nameAccess: Bool { locationAuthorizationStatus == .authorizedAlways }
    /// 只有本次主动请求且尚未作答时保护面板；未请求的 notDetermined 不算。
    var locationAskedAt: TimeInterval?
    var isRequestingLocation: Bool { locationAskedAt != nil && location.authorizationStatus == .notDetermined }
    func requestLocationAccess() {
        guard locationAuthorizationStatus == .notDetermined else { return }
        locationAskedAt = ProcessInfo.processInfo.systemUptime
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

    private func finishScan(_ result: Result<Set<CWNetwork>, Error>, known: Set<String>?) {
        busy = false; refresh()
        guard powerOn == true, nameAccess else { return }
        switch result {
        case .success(let found):
            scanFailed = false
            networks = WiFiChoice.choices(from: Array(found), connectedBSSID: currentBSSID)
            knownNames = known; hasScanned = true
            message = networks.isEmpty ? "未发现可显示的网络；可在系统 Wi‑Fi 设置中查看。" : ""
        case .failure(let error):
            scanFailed = true
            networks = []; knownNames = nil; hasScanned = false
            message = "查找网络失败：\(error.localizedDescription)"
        }
    }
}
