import AppKit
@testable import Combo

@main struct LiveStateCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let store = Store()
        defer { store.stop() }
        try? await Task.sleep(for: .seconds(1))
        if let battery = store.live.battery { assert((0...1).contains(battery)) }
        if let volume = store.live.volume { assert((0...1).contains(volume)) }
        assert(!store.observation.isEmpty)
        assert(!store.checkingMenus)
        print("Battery: \(store.live.battery == nil ? "unavailable" : "valid")")
        print("Volume: \(store.live.volume == nil ? "unavailable" : "valid")")
        print("Network: \(store.live.network)")
        print("Observers: \(store.observation)")
        assert(!store.showMenuPermission, "permission guide must not interrupt startup")
        print("PASS: real startup does not interrupt with menu permission guidance")
        if store.audio.selectedOutputID != 0 && store.audio.canMute {
            // Simulate the previous observed mute value, then read the real device without writing it.
            store.audio.muted.toggle()
            store.audio.refreshAudio()
            assert(store.snapshot.centerEvent == .volume, "A mute-only device change must trigger P4")
            store.clearVolumeHint()
        }
        // Volume checks no longer provide time for the live charge-limit read and its 2-second timeout.
        let deadline = ContinuousClock.now + .seconds(3)
        while store.battery.chargeLimit == .loading && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        assert(store.battery.chargeLimit != .loading, "charge-limit read must finish or time out")
        print("Battery detail: \(store.battery.sourceText); \(store.battery.statusText); limit \(store.battery.chargeLimit.text)")
        await store.battery.powerMode.refresh()
        assert(!store.battery.powerMode.busy)
        for (source, policy) in store.battery.powerMode.policies {
            print("Power policy: \(source.title) = \(policy.mode.title)")
            // Same-value requests must not ask for administrator authorization.
            await store.battery.powerMode.set(policy.mode, source: source)
            assert(!store.battery.powerMode.busy)
            assert(store.battery.powerMode.policies[source] == policy)
        }
        print("PASS: live state, observer registration, same-value power requests and shutdown")
    }
}
