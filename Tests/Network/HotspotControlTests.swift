import Testing
import Foundation

@objcMembers private final class TestPhone: NSObject {
    var deviceIdentifier = UUID().uuidString
    var deviceName = "Phone"
    var batteryLife: Any = 75
    var signalStrength: Any = 4
}
@objcMembers private final class TestHotspotSession: NSObject {
    weak var delegate: NSObject?
    var starts = 0
    var stops = 0
    func startBrowsing() { starts += 1 }
    func stopBrowsing() { stops += 1 }
}
struct HotspotControlTests {
    @Test
    @MainActor
    func testFieldsLifecycleStaleCallbacksAndTimeout() async throws {
        let first = TestHotspotSession(), second = TestHotspotSession()
        var next: NSObject? = first
        let control = HotspotControl(sessionFactory: { next }, timeout: .milliseconds(60))
        defer { control.stop() }
        let phone = TestPhone()
        control.start(); control.start()
        #expect(first.starts == 1)
        control.session(first, updatedFoundDevices: [phone])
        try await Task.sleep(for: .milliseconds(10))
        guard case .available(let phones) = control.state else { throw NSError(domain: "HotspotControlTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing phone"]) }
        #expect(phones.count == 1 && phones[0].battery == 75 && phones[0].signal == 4)
        phone.batteryLife = 101; phone.signalStrength = "invalid"
        control.session(first, updatedFoundDevices: [phone, phone])
        try await Task.sleep(for: .milliseconds(10))
        guard case .available(let filtered) = control.state else { throw NSError(domain: "HotspotControlTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing phone"]) }
        #expect(filtered.count == 1 && filtered[0].battery == nil && filtered[0].signal == nil)
        control.session(first, updatedFoundDevices: [])
        try await Task.sleep(for: .milliseconds(10))
        #expect(control.state == .available([]))
        control.stop(); #expect(first.stops == 1 && first.delegate == nil)
        next = second; control.start()
        control.session(first, updatedFoundDevices: [phone])
        try await Task.sleep(for: .milliseconds(10))
        #expect(control.state == .loading)
        try await Task.sleep(for: .milliseconds(100))
        #expect(control.state == .unavailable && second.stops == 1)
        next = nil; control.start(); #expect(control.state == .unavailable)
        next = NSObject(); control.start(); #expect(control.state == .unavailable)
        control.stop()
    }
}
