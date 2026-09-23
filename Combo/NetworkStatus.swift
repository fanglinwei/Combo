import Foundation
import SystemConfiguration
import Network

@MainActor final class NetworkStatus {
    var update: ((String, String) -> Void)?
    private let monitor = NWPathMonitor()
    private var config: SCDynamicStore?
    private var available: Bool?
    init() {
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        config = SCDynamicStoreCreate(nil, "Combo routes" as CFString, { _, _, info in
            guard let info else { return }
            let object = Unmanaged<NetworkStatus>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in object.refresh() }
        }, &context)
        if let config {
            SCDynamicStoreSetNotificationKeys(config, ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] as CFArray, ["Setup:/Network/Service/.*/Interface"] as CFArray)
            SCDynamicStoreSetDispatchQueue(config, .main)
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let available: Bool? = path.status == .requiresConnection ? nil : path.status == .satisfied
            Task { @MainActor in self?.available = available; self?.refresh() }
        }
        monitor.start(queue: DispatchQueue(label: "combo.paths"))
    }
    func refresh() {
        var kinds: [String] = []
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        if let config {
            for version in ["IPv4", "IPv6"] {
                guard let values = SCDynamicStoreCopyValue(config, "State:/Network/Global/\(version)" as CFString) as? [String: Any], let name = values[kSCDynamicStorePropNetPrimaryInterface as String] as? String else { continue }
                guard let interface = interfaces.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == name }) else { kinds.append("unknown"); continue }
                let type = SCNetworkInterfaceGetInterfaceType(interface)
                kinds.append(type == kSCNetworkInterfaceTypeIEEE80211 ? "wifi" : type == kSCNetworkInterfaceTypeEthernet ? "ethernet" : "unknown")
            }
        }
        let type = resolveTransport(pathAvailable: available, interfaces: kinds)
        let value: (String,String)
        switch type {
        case "offline": value = ("无可用路径", "exclamationmark")
        case "pending": value = ("等待连接", "minus")
        case "wifi": value = ("Wi-Fi", "wifi")
        case "ethernet": value = ("有线网络", "")
        default: value = ("连接类型不确定", "minus")
        }
        update?(value.0, value.1)
    }
    func stop() { monitor.cancel(); if let config { SCDynamicStoreSetDispatchQueue(config, nil) }; update = nil }
}
