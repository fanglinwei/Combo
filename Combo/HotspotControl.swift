import Foundation
import Combine
import Darwin

struct HotspotPhone: Identifiable, Equatable {
    let id: String
    let name: String
    let battery: Int?
    let signal: Int?

    static func read(_ device: NSObject) -> HotspotPhone? {
        func value(_ key: String) -> Any? {
            device.responds(to: NSSelectorFromString(key)) ? device.value(forKey: key) : nil
        }
        guard let name = value("deviceName") as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        func integer(_ key: String, range: ClosedRange<Int>) -> Int? {
            guard let number = value(key) as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  number.doubleValue.rounded() == number.doubleValue,
                  range.contains(number.intValue) else { return nil }
            return number.intValue
        }
        let identifier = value("deviceIdentifier")
        // A missing identifier must not merge two phones that share a display name.
        let id = (identifier as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (identifier as? UUID)?.uuidString ?? String(describing: ObjectIdentifier(device))
        return HotspotPhone(id: id, name: name, battery: integer("batteryLife", range: 0...100),
                            signal: integer("signalStrength", range: 0...4))
    }
}

enum HotspotState: Equatable {
    case loading, unavailable, available([HotspotPhone])
}

@MainActor final class HotspotControl: NSObject, ObservableObject {
    @Published private(set) var state: HotspotState = .loading
    private var browsing: NSObject?
    private var deadline: Task<Void, Never>?
    private let sessionFactory: () -> NSObject?
    private let timeout: Duration
    // Keep the dynamically loaded framework alive for all sessions.
    private static let framework = dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY | RTLD_LOCAL)

    init(sessionFactory: (() -> NSObject?)? = nil, timeout: Duration = .seconds(10)) {
        self.sessionFactory = sessionFactory ?? Self.makeSession
        self.timeout = timeout
        super.init()
    }
    private static func makeSession() -> NSObject? {
        // ponytail: private ABI verified only on this build; re-verify before widening support.
        guard ProcessInfo.processInfo.operatingSystemVersionString.contains("26A428"), framework != nil,
              let type = NSClassFromString("SFRemoteHotspotSession") as? NSObject.Type else { return nil }
        return type.perform(NSSelectorFromString("new"))?.takeRetainedValue() as? NSObject
    }
    func start() {
        guard browsing == nil else { return }
        state = .loading
        guard let session = sessionFactory(),
              ["setDelegate:", "startBrowsing", "stopBrowsing"].allSatisfy({ session.responds(to: NSSelectorFromString($0)) }) else {
            state = .unavailable; return
        }
        browsing = session
        session.perform(NSSelectorFromString("setDelegate:"), with: self)
        session.perform(NSSelectorFromString("startBrowsing"))
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: self?.timeout ?? .seconds(10)) } catch { return }
            guard let self, self.browsing === session, self.state == .loading else { return }
            self.stop(); self.state = .unavailable
        }
    }
    func stop() {
        deadline?.cancel(); deadline = nil
        let previous = browsing
        browsing = nil
        previous?.perform(NSSelectorFromString("setDelegate:"), with: nil)
        previous?.perform(NSSelectorFromString("stopBrowsing"))
        state = .loading
    }
    @objc nonisolated func session(_ session: NSObject, updatedFoundDevices devices: [NSObject]) {
        var seen = Set<String>()
        let phones = devices.compactMap(HotspotPhone.read).filter { seen.insert($0.id).inserted }
        Task { @MainActor [weak self] in
            guard let self, self.browsing === session else { return }
            self.deadline?.cancel(); self.deadline = nil
            self.state = .available(phones)
        }
    }
}
