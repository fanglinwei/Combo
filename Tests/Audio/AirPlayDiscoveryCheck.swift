import Combine
import Foundation
import Network
import dnssd

@main struct AirPlayDiscoveryCheck {
    @MainActor static func main() {
        let suite = "Combo.AirPlayDiscoveryCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var browsers: [NWBrowser] = []
        let discovery = AirPlayDiscovery(defaults: defaults, startBrowser: { browsers.append($0) })
        assert(!discovery.hasRequested && discovery.state == .idle && discovery.askedAt == nil)
        discovery.setActive(true)
        discovery.setActive(true)
        assert(browsers.isEmpty, "Opening the panel must not request local-network access")

        discovery.request()
        assert(discovery.hasRequested && discovery.state == .searching && browsers.count == 1)
        let askedAt = discovery.askedAt
        assert(askedAt != nil)
        let first = browsers[0]
        if case .bonjourWithTXTRecord(let type, _) = first.descriptor { assert(type == "_airplay._tcp") }
        else { assertionFailure("Discovery needs AirPlay TXT metadata") }
        first.stateUpdateHandler?(.ready)
        assert(discovery.state == .ready && discovery.askedAt == nil)
        var deviceUpdates = 0
        let subscription = discovery.$devices.sink { _ in deviceUpdates += 1 }

        discovery.setActive(false)
        assert(discovery.state == .idle && discovery.devices.isEmpty && discovery.hasRequested)
        let afterStop = deviceUpdates
        first.stateUpdateHandler?(.ready)
        first.stateUpdateHandler?(.waiting(.posix(.ENETDOWN)))
        first.stateUpdateHandler?(.failed(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))))
        first.browseResultsChangedHandler?([], [])
        assert(discovery.state == .idle && deviceUpdates == afterStop, "Stopped browsers must not publish late callbacks")

        discovery.setActive(true)
        assert(browsers.count == 2 && discovery.state == .searching && discovery.askedAt == nil)
        let second = browsers[1]
        second.stateUpdateHandler?(.ready)
        let afterRestart = deviceUpdates
        first.stateUpdateHandler?(.cancelled)
        first.stateUpdateHandler?(.ready)
        first.stateUpdateHandler?(.waiting(.posix(.ENETDOWN)))
        first.stateUpdateHandler?(.failed(.posix(.ENETDOWN)))
        first.browseResultsChangedHandler?([], [])
        assert(discovery.state == .ready && deviceUpdates == afterRestart, "An old browser must not erase a new session")
        second.browseResultsChangedHandler?([], [])
        assert(deviceUpdates == afterRestart + 1, "Current result callbacks must still publish")

        second.stateUpdateHandler?(.waiting(.posix(.ENETDOWN)))
        assert(discovery.state == .failed, "A connectivity error is not permission denial")
        second.stateUpdateHandler?(.ready)
        assert(discovery.state == .ready, "Waiting browsers can recover without recreation")
        second.stateUpdateHandler?(.waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))))
        assert(discovery.state == .denied)
        second.stateUpdateHandler?(.ready)
        assert(discovery.state == .ready)
        second.stateUpdateHandler?(.failed(.dns(DNSServiceErrorType(kDNSServiceErr_ServiceNotRunning))))
        assert(discovery.state == .failed)
        second.stateUpdateHandler?(.ready)
        assert(discovery.state == .failed, "A terminal browser must relinquish its session")
        discovery.setActive(true)
        assert(browsers.count == 3 && discovery.state == .searching && discovery.askedAt == nil,
               "Terminal failures need a new browser, without a new permission grace period")

        let third = browsers[2]
        third.stateUpdateHandler?(.failed(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))))
        assert(discovery.state == .denied)
        discovery.request()
        assert(browsers.count == 4 && discovery.state == .searching && discovery.askedAt.map { value in askedAt.map { value >= $0 } ?? false } == true)
        let fourth = browsers[3]
        third.stateUpdateHandler?(.cancelled)
        assert(discovery.state == .searching, "Retry must ignore cancellation from its predecessor")
        fourth.stateUpdateHandler?(.cancelled)
        assert(discovery.state == .idle && discovery.devices.isEmpty)
        discovery.setActive(true)
        assert(browsers.count == 5 && discovery.state == .searching)

        discovery.setActive(false)
        let lastAskedAt = discovery.askedAt
        discovery.request()
        assert(browsers.count == 5 && discovery.state == .idle && discovery.askedAt == lastAskedAt,
               "An inactive request must not start browsing or create a permission grace period")
        var restoredBrowsers: [NWBrowser] = []
        let restored = AirPlayDiscovery(defaults: defaults, startBrowser: { restoredBrowsers.append($0) })
        assert(restored.hasRequested && restored.askedAt == nil)
        restored.setActive(true)
        assert(restoredBrowsers.count == 1 && restored.state == .searching && restored.askedAt == nil,
               "The explicit opt-in survives relaunch; automatic resume must not suppress outside clicks")
        restored.setActive(false)
        subscription.cancel()
        print("AirPlay discovery checks passed")
    }
}
