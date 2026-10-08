import AppKit
import Sparkle

@main struct AppUpdaterCheck {
    @MainActor static func main() throws {
        let suite = "Combo.AppUpdaterCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.defaults }
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AppUpdater(isEnabled: false, defaults: defaults)
        coordinator.start()
        coordinator.checkForUpdates()
        coordinator.setAutomaticChecks(true)
        assert(!coordinator.isStarted && !coordinator.canCheckForUpdates)
        assert(!coordinator.automaticallyChecksForUpdates)
        assert(coordinator.lastSuccessfulCheck == nil)

        let driver = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        coordinator.updater(driver.updater, didAbortWithError: networkError)
        assert(coordinator.hasCheckError && coordinator.lastSuccessfulCheck == nil)
        let noUpdate = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))
        coordinator.updaterDidNotFindUpdate(driver.updater, error: noUpdate)
        guard let successfulCheck = coordinator.lastSuccessfulCheck else { throw Failure.date }
        assert(!coordinator.hasCheckError)
        coordinator.updater(driver.updater, didAbortWithError: networkError)
        assert(coordinator.hasCheckError && coordinator.lastSuccessfulCheck == successfulCheck,
               "A failed check must preserve the previous successful check time")
        coordinator.updater(driver.updater, didAbortWithError: noUpdate)
        assert(coordinator.lastSuccessfulCheck == successfulCheck)
        let reopened = AppUpdater(isEnabled: false, defaults: defaults)
        assert(reopened.lastSuccessfulCheck == successfulCheck)
        assert(coordinator.supportsGentleScheduledUpdateReminders)
        coordinator.standardUserDriverWillFinishUpdateSession()
        assert(coordinator.availableVersion == nil)
        print("PASS: development checks disabled; successful check time survives network failures and reopening")
    }
    enum Failure: Error { case defaults, date }
}
