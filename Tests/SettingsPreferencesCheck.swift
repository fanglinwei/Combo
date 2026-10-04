import AppKit
import SwiftUI
@testable import Combo

@main struct SettingsPreferencesCheck {
    @MainActor static func main() throws {
        let suite = "Combo.SettingsPreferencesCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.defaults }
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = BatteryStore(defaults: defaults)
        assert(fresh.displayEnabled && fresh.displayThreshold == 20)
        for threshold in [0, 1, 20, 50, 100] {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(threshold, forKey: "batteryDisplayThreshold")
            let battery = BatteryStore(defaults: defaults)
            assert(battery.displayThreshold == threshold, "Existing thresholds must survive migration")
            let expected = threshold == 0 ? 20 : threshold
            battery.displayEnabled = false
            let reopened = BatteryStore(defaults: defaults)
            assert(!reopened.displayEnabled && reopened.lastDisplayThreshold == expected)
            reopened.displayEnabled = true
            assert(reopened.displayThreshold == expected, "Re-enabling must restore the last positive threshold")
            reopened.displayThreshold = 37
            reopened.displayEnabled = false
            let later = BatteryStore(defaults: defaults)
            later.displayEnabled = true
            assert(later.displayThreshold == 37)
        }

        for hasBattery in [true, false] {
            defaults.removePersistentDomain(forName: suite)
            let setup = MenuBarSetup(defaults: defaults, hasInternalBattery: hasBattery)
            assert(!setup.hasBaseline && setup.states.isEmpty && setup.failedKeys.isEmpty)
            assert(!setup.recordBaseline(["wifi": true]), "Incomplete reads must not establish a baseline")
            assert(defaults.dictionary(forKey: "menuSetupBaseline") == nil)
            let baseline = hasBattery ? ["wifi": false, "sound": true, "battery": false] : ["wifi": false, "sound": true]
            assert(setup.recordBaseline(baseline))
            assert(setup.hasBaseline && setup.recordedAt != nil)
            assert(setup.recordBaseline(["wifi": true, "sound": false, "battery": true]))
            assert(setup.baseline == baseline, "The first complete baseline must never be overwritten")
            let reopened = MenuBarSetup(defaults: defaults, hasInternalBattery: hasBattery)
            assert(reopened.baseline == baseline && reopened.hasBaseline)
            assert(reopened.states.isEmpty, "A baseline is not a current detection result")
            let keys = Set(reopened.supportedKeys)
            let changed = Dictionary(uniqueKeysWithValues: baseline.map { ($0.key, !$0.value) })
            assert(menuBarRestoreKeys(original: baseline, current: changed, keys: keys) == keys.sorted())
            assert(menuBarRestoreKeys(original: baseline, current: ["sound": false], keys: ["sound"]) == ["sound"],
                   "Retrying Sound must not require or modify already restored items")
            assert(menuBarRestoreKeys(original: baseline, current: baseline, keys: keys) == [])
            assert(menuBarRestoreKeys(original: baseline, current: [:], keys: keys) == nil)
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let previousGuide = UserDefaults.standard.object(forKey: OnboardingState.completedKey)
        UserDefaults.standard.set(true, forKey: OnboardingState.completedKey)
        defer { UserDefaults.standard.set(previousGuide, forKey: OnboardingState.completedKey) }
        let store = Store()
        store.stop()
        let delegate = AppDelegate(store: store)
        delegate.openSettings()
        guard let window = NSApp.windows.first(where: { $0.contentView is NSHostingView<SettingsView> }) else { throw Failure.window }
        assert(window.frame.size == NSSize(width: 850, height: 690) && window.minSize == NSSize(width: 780, height: 620))
        window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
        store.scene = .music
        let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: other))
        assert(store.scene == .music, "Closing another window must not end the settings demo")
        window.close()
        assert(store.scene == .live, "Closing Settings must end its menu bar demo")
        delegate.openSettings()
        assert(store.scene == .live, "Reopening Settings must keep live data")
        window.close()
        store.stop()
        try checkThresholdInput(store: store)
        print("PASS: threshold drafts, invalid submit/blur, valid submit/blur, 20% fresh default, existing threshold migration, off/on across restart, complete applicable baseline, preserved records and isolated retry planning and settings demo cleanup")
    }

    /// Exercise the actual SwiftUI text field through its AppKit field editor.
    @MainActor private static func checkThresholdInput(store: Store) throws {
        let defaults = UserDefaults.standard
        let keys = ["batteryDisplayThreshold", "batteryLastDisplayThreshold"]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) } }
        store.battery.displayThreshold = 20
        let hosting = NSHostingView(rootView: SettingsView(store: store, page: .integration) { _ in })
        let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: 850, height: 1100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        settle()
        hosting.layoutSubtreeIfNeeded()
        guard let field = editableField(in: hosting) else { throw Failure.field }

        func enter(_ text: String) throws -> NSTextView {
            guard window.makeFirstResponder(field) else { throw Failure.field }
            settle()
            guard let editor = field.currentEditor() as? NSTextView else { throw Failure.field }
            editor.selectAll(nil)
            for character in text {
                editor.insertText(String(character), replacementRange: editor.selectedRange())
                settle()
            }
            return editor
        }

        let invalid = try enter("101")
        assert(store.battery.displayThreshold == 20, "Valid prefixes must remain drafts")
        invalid.insertNewline(nil)
        settle()
        window.makeFirstResponder(nil)
        settle()
        assert(field.stringValue == "101", "Keep invalid input so the user can correct it")
        assert(store.battery.displayThreshold == 20 && store.battery.lastDisplayThreshold == 20)
        assert(defaults.integer(forKey: "batteryDisplayThreshold") == 20)
        store.battery.displayEnabled = false
        store.battery.displayEnabled = true
        assert(store.battery.displayThreshold == 20, "Invalid input must not change the remembered threshold")
        settle()

        let valid = try enter("37")
        assert(store.battery.displayThreshold == 20, "Do not save while typing")
        valid.insertNewline(nil)
        settle()
        assert(store.battery.displayThreshold == 37 && store.battery.lastDisplayThreshold == 37)
        window.makeFirstResponder(nil)
        settle()
        _ = try enter("64")
        assert(store.battery.displayThreshold == 37)
        window.makeFirstResponder(nil)
        settle()
        assert(store.battery.displayThreshold == 64 && defaults.integer(forKey: "batteryDisplayThreshold") == 64,
               "Leaving a valid field must commit the complete draft")
    }

    @MainActor private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor private static func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for child in view.subviews {
            if let field = editableField(in: child) { return field }
        }
        return nil
    }

    enum Failure: Error { case defaults, window, field }
}
