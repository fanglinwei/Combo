import Testing
import AppKit
import Sparkle

struct AppUpdaterTests {
    @Test
    @MainActor
    func testDisabledUpdaterErrorRecoveryAndPreferencePersistence() throws {
        let suite = "Combo.AppUpdaterCheck.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AppUpdater(isEnabled: false, defaults: defaults)
        coordinator.start()
        coordinator.checkForUpdates()
        coordinator.setAutomaticChecks(true)
        #expect(!coordinator.isStarted && !coordinator.canCheckForUpdates)
        #expect(coordinator.automaticallyChecksForUpdates, "Fresh installs default to automatic checks")
        #expect(coordinator.lastSuccessfulCheck == nil)

        let driver = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        coordinator.updater(driver.updater, didAbortWithError: networkError)
        #expect(coordinator.hasCheckError && coordinator.lastSuccessfulCheck == nil)
        let noUpdate = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))
        coordinator.updaterDidNotFindUpdate(driver.updater, error: noUpdate)
        let successfulCheck = try #require(coordinator.lastSuccessfulCheck)
        #expect(!coordinator.hasCheckError)
        coordinator.updater(driver.updater, didAbortWithError: networkError)
        #expect(coordinator.hasCheckError && coordinator.lastSuccessfulCheck == successfulCheck,
               "A failed check must preserve the previous successful check time")
        coordinator.updater(driver.updater, didAbortWithError: noUpdate)
        #expect(coordinator.lastSuccessfulCheck == successfulCheck)
        defaults.set(false, forKey: "SUEnableAutomaticChecks")
        let reopened = AppUpdater(isEnabled: false, defaults: defaults)
        #expect(reopened.lastSuccessfulCheck == successfulCheck)
        #expect(!reopened.automaticallyChecksForUpdates, "A saved opt-out survives reopening")
        #expect(coordinator.supportsGentleScheduledUpdateReminders)
        coordinator.standardUserDriverWillFinishUpdateSession()
        #expect(coordinator.availableVersion == nil)
    }
}
