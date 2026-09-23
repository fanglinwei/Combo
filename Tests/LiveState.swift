import AppKit
import ApplicationServices

@main struct LiveStateCheck {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let store = Store()
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
        store.refreshMenuAccess()
        assert(store.menuAccessGranted == AXIsProcessTrusted())
        if !store.menuAccessGranted {
            store.checkMenus()
            assert(store.showMenuPermission, "denied menu check must show permission guide")
            assert(!store.checkingMenus, "denied menu check must not start an AX scan")
        }
        print("PASS: permission refresh and denied-access guidance (when untrusted)")
        store.showVolumeHint()
        assert(store.live.adjusting)
        try? await Task.sleep(for: .milliseconds(1100))
        store.showVolumeHint()
        try? await Task.sleep(for: .milliseconds(1100))
        assert(store.live.adjusting, "second change must extend hint")
        try? await Task.sleep(for: .milliseconds(1100))
        assert(!store.live.adjusting, "hint must expire")
        store.stop()
        print("PASS: live read-only state, observer registration, renewed volume hint and shutdown")
    }
}
