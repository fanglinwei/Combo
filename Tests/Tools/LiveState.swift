import AppKit
import ApplicationServices
import Combine
@testable import Combo

@main struct LiveStateCheck {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let store = Store()
        try? await Task.sleep(for: .seconds(1))
        if let battery = store.live.battery { assert((0...1).contains(battery)) }
        if let volume = store.live.volume { assert((0...1).contains(volume)) }
        assert(!store.observation.isEmpty)
        assert(!store.checkingMenus)
        var iconUpdates = 0
        let iconObserver = store.objectWillChange.sink { iconUpdates += 1 }
        let originalThreshold = store.battery.displayThreshold
        store.battery.displayThreshold = originalThreshold == 50 ? 49 : 50
        let thresholdRedrewIcon = iconUpdates > 0
        store.battery.displayThreshold = originalThreshold
        iconObserver.cancel()
        assert(thresholdRedrewIcon, "Changing the battery threshold must redraw the menu bar icon")
        print("Battery: \(store.live.battery == nil ? "unavailable" : "valid")")
        print("Volume: \(store.live.volume == nil ? "unavailable" : "valid")")
        print("Network: \(store.live.network)")
        print("Observers: \(store.observation)")
        assert(!store.showMenuPermission, "permission guide must not interrupt startup")
        store.refreshMenuAccess()
        assert(store.menuAccessGranted == AXIsProcessTrusted())
        if !store.menuAccessGranted {
            store.checkMenus()
            assert(store.showMenuPermission, "denied menu check must show permission guide")
            assert(!store.checkingMenus, "denied menu check must not start an AX scan")
        }
        print("PASS: permission refresh and denied-access guidance (when untrusted)")
        if store.audio.selectedOutputID != 0 && store.audio.canMute {
            // Simulate the previous observed mute value, then read the real device without writing it.
            store.audio.muted.toggle()
            store.audio.refreshAudio()
            assert(store.snapshot.centerEvent == .volume, "A mute-only device change must trigger P4")
            store.clearVolumeHint()
        }
        // Change only the in-memory snapshot; never play audio or write system volume.
        let originalAudio = store.live
        store.live = Snapshot(symbol: "wifi", volume: 0.5, deviceKind: .bluetooth(.airPodsPro), playing: true)
        store.showVolumeHint()
        assert(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).priority == 4)
        store.live.muted = true
        store.showVolumeHint()
        assert(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).text == "0")
        store.live.muted = false
        store.showVolumeHint()
        assert(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).text == "50")
        store.live.volume = 0
        store.showVolumeHint()
        assert(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).text == "0")
        store.live.volume = 0.5; store.live.playing = false
        store.showVolumeHint()
        assert(store.snapshot.centerEvent == .volume, "Idle volume changes must also show P4 digits")
        assert(store.live.adjusting)
        try? await Task.sleep(for: .milliseconds(1100))
        store.showVolumeHint()
        try? await Task.sleep(for: .milliseconds(1100))
        assert(store.live.adjusting && store.snapshot.centerEvent == .volume, "second change must extend hint")
        store.live.deviceKind = .other
        try? await Task.sleep(for: .milliseconds(1100))
        assert(!store.live.adjusting && store.snapshot.centerEvent == nil, "hint must expire")
        assert(IconContent(store.snapshot).kind == .wifi, "Expiry must restore the latest resident state")
        store.live = originalAudio
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
        store.stop()
        print("PASS: live state, observer registration, renewed volume hint, same-value power requests and shutdown")
    }
}
