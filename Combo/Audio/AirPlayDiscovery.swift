import Combine
import Foundation
import Network
import dnssd

/// 只读发现的附近 AirPlay 设备。
///
/// 未路由的 AirPlay 设备不在 CoreAudio 设备表里（系统行为），所以只能靠 Bonjour 发现；
/// 这里**只发现、不建立路由**——建立路由需要 AVOutputDevice，而系统没给出可用的构造入口
/// （见 docs/engineering/audio.md「AirPlay 路由与附近发现」）。因此列表里这些设备标"未连接"，
/// 点按跳系统声音设置由用户选择。
struct DiscoveredAirPlay: Identifiable, Equatable {
    /// Bonjour 实例名（即房间/设备名，同一网络内唯一）。
    let id: String
    let name: String
    /// TXT 记录里的 `model=`（如 `AppleTV14,1`），用于选图标。
    let model: String

    var family: AirPlayFamily { AirPlayFamily.matching(model: model) }
}

/// 浏览 `_airplay._tcp`（AirPlay 2 设备；只播 `_raop._tcp` 的 AirPlay 1 老设备不在其中）。
///
/// 需要本地网络授权（Info.plist 的 `NSLocalNetworkUsageDescription` + `NSBonjourServices`）。
/// 只在用户主动发现后浏览；权限拒绝与网络故障分别呈现。
@MainActor final class AirPlayDiscovery: ObservableObject {
    enum State: Equatable { case idle, searching, ready, denied, failed }

    @Published private(set) var devices: [DiscoveredAirPlay] = []
    @Published private(set) var state: State = .idle
    private(set) var hasRequested: Bool
    private(set) var askedAt: TimeInterval?
    private var browser: NWBrowser?
    private var active = false
    private let defaults: UserDefaults
    private let startBrowser: (NWBrowser) -> Void

    init(defaults: UserDefaults = .standard, startBrowser: @escaping (NWBrowser) -> Void = { $0.start(queue: .main) }) {
        self.defaults = defaults
        self.startBrowser = startBrowser
        hasRequested = defaults.bool(forKey: "airPlayDiscoveryRequested")
    }

    /// 纯筛选：去掉本机自己、去掉当前已路由的那台、按名称去重排序。
    static func visible(_ found: [DiscoveredAirPlay], selfName: String, routedName: String?) -> [DiscoveredAirPlay] {
        var seen = Set<String>()
        return found
            .filter { !$0.name.isEmpty && $0.name != selfName && $0.name != routedName }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active && hasRequested { start() } else { stop() }
    }

    func request() {
        hasRequested = true
        defaults.set(true, forKey: "airPlayDiscoveryRequested")
        stop()
        guard active else { return }
        askedAt = ProcessInfo.processInfo.systemUptime
        start()
    }

    private func start() {
        guard browser == nil else { return }
        // 必须用 bonjourWithTXTRecord：普通 bonjour 描述符不带 TXT，就拿不到 `model=`
        // （机型 → 图标要靠它；未路由设备拿不到机型时退通用符号）。
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            // 浏览器始终在主队列回调；同步更新避免额外 Task 延迟。
            MainActor.assumeIsolated {
                guard let self, let browser, self.browser === browser else { return }
                switch state {
                case .ready:
                    self.askedAt = nil
                    self.state = .ready
                case .waiting(let error), .failed(let error):
                    self.devices = []
                    if case .failed = state {
                        self.browser = nil
                        browser.cancel()
                    }
                    self.state = error == .dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied)) ? .denied : .failed
                case .cancelled: self.stop()
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            MainActor.assumeIsolated {
                guard let self, let browser, self.browser === browser else { return }
                var found: [DiscoveredAirPlay] = []
                for result in results {
                    guard case .service(let name, _, _, _) = result.endpoint else { continue }
                    var model = ""
                    if case .bonjour(let record) = result.metadata { model = record["model"] ?? "" }
                    found.append(DiscoveredAirPlay(id: name, name: name, model: model))
                }
                self.devices = found
            }
        }
        self.browser = browser
        state = .searching
        startBrowser(browser)
    }

    private func stop() {
        let previous = browser
        browser = nil
        askedAt = nil
        previous?.cancel()
        devices = []
        state = .idle
    }
}
