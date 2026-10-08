import AppKit
import Combine
import Sparkle

/// One updater owns Sparkle's scheduler and the application-wide update reminder.
@MainActor final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()
    static let successfulCheckKey = "lastSuccessfulUpdateCheck"
    #if DEBUG
    nonisolated static let updatesEnabled = false
    #else
    nonisolated static let updatesEnabled = true
    #endif

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastSuccessfulCheck: Date?
    @Published private(set) var hasCheckError = false
    @Published private(set) var isStarted = false
    let isEnabled: Bool
    private let defaults: UserDefaults
    private var observations: [NSKeyValueObservation] = []
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    init(isEnabled: Bool = AppUpdater.updatesEnabled, defaults: UserDefaults = .standard) {
        self.isEnabled = isEnabled
        self.defaults = defaults
        automaticallyChecksForUpdates = defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        lastSuccessfulCheck = defaults.object(forKey: Self.successfulCheckKey) as? Date
        super.init()
    }

    func start() {
        guard isEnabled, !isStarted else { return }
        do {
            try controller.updater.start()
            isStarted = true
            observations = [
                controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                    // Sparkle invokes these KVO notifications on the main thread.
                    MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
                },
                controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                    MainActor.assumeIsolated { self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates }
                }
            ]
        } catch {
            hasCheckError = true
        }
    }

    func checkForUpdates() {
        guard isStarted, canCheckForUpdates else { return }
        hasCheckError = false
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isStarted else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    private func recordSuccessfulCheck() {
        let date = Date()
        lastSuccessfulCheck = date
        defaults.set(date, forKey: Self.successfulCheckKey)
        hasCheckError = false
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordSuccessfulCheck()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        // A valid, empty stable feed also means that no compatible update is available.
        recordSuccessfulCheck()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        guard error.domain != SUSparkleErrorDomain || error.code != SUError.noUpdateError.rawValue else { return }
        hasCheckError = true
    }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { availableVersion = update.displayVersionString }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { availableVersion = nil }
    }
}
