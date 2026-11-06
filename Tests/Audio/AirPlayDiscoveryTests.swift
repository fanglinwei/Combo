import Testing
import Combine
import Foundation
import Network
import dnssd

struct AirPlayDiscoveryTests {
    @Test
    @MainActor
    func testOptInLifecyclePermissionFailuresAndLateCallbacks() async throws {
        let suite = "Combo.AirPlayDiscoveryCheck.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var browsers: [NWBrowser] = []
        let discovery = AirPlayDiscovery(defaults: defaults, startBrowser: { browsers.append($0) })
        defer { discovery.setActive(false) }
        #expect(!discovery.hasRequested && discovery.state == .idle && discovery.askedAt == nil)
        discovery.setActive(true)
        discovery.setActive(true)
        #expect(browsers.isEmpty, "Opening the panel must not request local-network access")

        discovery.request()
        #expect(discovery.hasRequested && discovery.state == .searching && browsers.count == 1)
        let askedAt = discovery.askedAt
        #expect(askedAt != nil)
        let first = try #require(browsers.first)
        if case .bonjourWithTXTRecord(let type, _) = first.descriptor { #expect(type == "_airplay._tcp") }
        else { throw NSError(domain: "AirPlayDiscoveryTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Discovery needs AirPlay TXT metadata"]) }
        first.stateUpdateHandler?(.ready)
        #expect(discovery.state == .ready && discovery.askedAt == nil)
        var deviceUpdates = 0
        let subscription = discovery.$devices.sink { _ in deviceUpdates += 1 }
        defer { subscription.cancel() }

        discovery.setActive(false)
        #expect(discovery.state == .idle && discovery.devices.isEmpty && discovery.hasRequested)
        let afterStop = deviceUpdates
        first.stateUpdateHandler?(.ready)
        first.stateUpdateHandler?(.waiting(.posix(.ENETDOWN)))
        first.stateUpdateHandler?(.failed(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))))
        first.browseResultsChangedHandler?([], [])
        #expect(discovery.state == .idle && deviceUpdates == afterStop, "Stopped browsers must not publish late callbacks")

        discovery.setActive(true)
        #expect(browsers.count == 2 && discovery.state == .searching && discovery.askedAt == nil)
        let second = try #require(browsers.dropFirst(1).first)
        second.stateUpdateHandler?(.ready)
        let afterRestart = deviceUpdates
        first.stateUpdateHandler?(.cancelled)
        first.stateUpdateHandler?(.ready)
        first.stateUpdateHandler?(.waiting(.posix(.ENETDOWN)))
        first.stateUpdateHandler?(.failed(.posix(.ENETDOWN)))
        first.browseResultsChangedHandler?([], [])
        #expect(discovery.state == .ready && deviceUpdates == afterRestart, "An old browser must not erase a new session")
        second.browseResultsChangedHandler?([], [])
        #expect(deviceUpdates == afterRestart + 1, "Current result callbacks must still publish")

        second.stateUpdateHandler?(.waiting(.posix(.ENETDOWN)))
        #expect(discovery.state == .failed, "A connectivity error is not permission denial")
        second.stateUpdateHandler?(.ready)
        #expect(discovery.state == .ready, "Waiting browsers can recover without recreation")
        second.stateUpdateHandler?(.waiting(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))))
        #expect(discovery.state == .denied)
        second.stateUpdateHandler?(.ready)
        #expect(discovery.state == .ready)
        second.stateUpdateHandler?(.failed(.dns(DNSServiceErrorType(kDNSServiceErr_ServiceNotRunning))))
        #expect(discovery.state == .failed)
        second.stateUpdateHandler?(.ready)
        #expect(discovery.state == .failed, "A terminal browser must relinquish its session")
        discovery.setActive(true)
        #expect(browsers.count == 3 && discovery.state == .searching && discovery.askedAt == nil,
               "Terminal failures need a new browser, without a new permission grace period")

        let third = try #require(browsers.dropFirst(2).first)
        third.stateUpdateHandler?(.failed(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))))
        #expect(discovery.state == .denied)
        discovery.request()
        #expect(browsers.count == 4 && discovery.state == .searching && discovery.askedAt.map { value in askedAt.map { value >= $0 } ?? false } == true)
        let fourth = try #require(browsers.dropFirst(3).first)
        third.stateUpdateHandler?(.cancelled)
        #expect(discovery.state == .searching, "Retry must ignore cancellation from its predecessor")
        fourth.stateUpdateHandler?(.cancelled)
        #expect(discovery.state == .idle && discovery.devices.isEmpty)
        discovery.setActive(true)
        #expect(browsers.count == 5 && discovery.state == .searching)

        discovery.setActive(false)
        let lastAskedAt = discovery.askedAt
        discovery.request()
        #expect(browsers.count == 5 && discovery.state == .idle && discovery.askedAt == lastAskedAt,
               "An inactive request must not start browsing or create a permission grace period")
        var restoredBrowsers: [NWBrowser] = []
        let restored = AirPlayDiscovery(defaults: defaults, startBrowser: { restoredBrowsers.append($0) })
        defer { restored.setActive(false) }
        #expect(restored.hasRequested && restored.askedAt == nil)
        restored.setActive(true)
        #expect(restoredBrowsers.count == 1 && restored.state == .searching && restored.askedAt == nil,
               "The explicit opt-in survives relaunch; automatic resume must not suppress outside clicks")
        restored.setActive(false)
        subscription.cancel()
    }
}
