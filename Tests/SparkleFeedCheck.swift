import AppKit
import Sparkle

/// Run inside a disposable bundle whose Info.plist contains the feed and public key.
@main struct SparkleFeedCheck {
    @MainActor static func main() throws {
        let suite = "Combo.SparkleFeedCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.defaults }
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AppUpdater(isEnabled: false, defaults: defaults)
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: coordinator, userDriverDelegate: nil)
        try controller.updater.start()
        controller.updater.checkForUpdateInformation()
        let deadline = Date().addingTimeInterval(45)
        while coordinator.lastSuccessfulCheck == nil && !coordinator.hasCheckError && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        guard coordinator.lastSuccessfulCheck != nil, !coordinator.hasCheckError else { throw Failure.feed }
        print("PASS: Sparkle loaded the live HTTPS appcast and completed a successful check")
        withExtendedLifetime(controller) {}
    }
    enum Failure: Error { case defaults, feed }
}
