import Foundation

@objcMembers final class TestPhone: NSObject {
    var deviceIdentifier = UUID().uuidString
    var deviceName = "Phone"
    var batteryLife: Any = 75
    var signalStrength: Any = 4
}
@objcMembers final class TestHotspotSession: NSObject {
    weak var delegate: NSObject?
    var starts = 0
    var stops = 0
    func startBrowsing() { starts += 1 }
    func stopBrowsing() { stops += 1 }
}
@main struct HotspotControlCheck {
    @MainActor static func main() async throws {
        let first = TestHotspotSession(), second = TestHotspotSession()
        var next: NSObject? = first
        let control = HotspotControl(sessionFactory: { next }, timeout: .milliseconds(60))
        let phone = TestPhone()
        control.start(); control.start()
        assert(first.starts == 1)
        control.session(first, updatedFoundDevices: [phone])
        try await Task.sleep(for: .milliseconds(10))
        guard case .available(let phones) = control.state else { fatalError("missing phone") }
        assert(phones.count == 1 && phones[0].battery == 75 && phones[0].signal == 4)
        phone.batteryLife = 101; phone.signalStrength = "invalid"
        control.session(first, updatedFoundDevices: [phone, phone])
        try await Task.sleep(for: .milliseconds(10))
        guard case .available(let filtered) = control.state else { fatalError("missing phone") }
        assert(filtered.count == 1 && filtered[0].battery == nil && filtered[0].signal == nil)
        control.session(first, updatedFoundDevices: [])
        try await Task.sleep(for: .milliseconds(10))
        assert(control.state == .available([]))
        control.stop(); assert(first.stops == 1 && first.delegate == nil)
        next = second; control.start()
        control.session(first, updatedFoundDevices: [phone])
        try await Task.sleep(for: .milliseconds(10))
        assert(control.state == .loading)
        try await Task.sleep(for: .milliseconds(100))
        assert(control.state == .unavailable && second.stops == 1)
        next = nil; control.start(); assert(control.state == .unavailable)
        next = NSObject(); control.start(); assert(control.state == .unavailable)
        control.stop()
        print("Hotspots: fields, malformed values, duplicates, removal, lifecycle, late callbacks, timeout and missing capability passed")
    }
}
