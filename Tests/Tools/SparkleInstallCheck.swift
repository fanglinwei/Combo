import AppKit
import Sparkle

/// Automatically approves installation only for the disposable fixture bundle.
@MainActor final class FixtureDriver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("Fixture update found: \(appcastItem.versionString)")
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        fail(error)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        fail(error)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { print("Extracting fixture") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        print("PASS: signed fixture downloaded, verified, extracted and installed (relaunched=\(relaunched))")
        exit(0)
    }
    func dismissUpdateInstallation() {}
    private func fail(_ error: Error) {
        fputs("Fixture update failed: \(error as NSError)\n", stderr)
        exit(1)
    }
}

@main struct SparkleInstallCheck {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2,
              let host = Bundle(path: CommandLine.arguments[1]),
              host.bundleIdentifier == "local.combo.update-fixture",
              let feed = host.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.host == "127.0.0.1" else { throw Failure.fixture }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let driver = FixtureDriver()
        let updater = SPUUpdater(hostBundle: host, applicationBundle: Bundle.main, userDriver: driver, delegate: nil)
        try updater.start()
        updater.checkForUpdates()
        withExtendedLifetime((driver, updater)) { app.run() }
    }
    enum Failure: Error { case fixture }
}
