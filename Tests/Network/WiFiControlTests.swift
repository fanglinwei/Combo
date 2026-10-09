import Testing
import CoreWLAN
import Security

// Hardware results are the boundary; projection and security rules are production code.
private final class ScannedNetwork: CWNetwork {
    let label: String
    let address: String
    let strength: Int
    let protection: CWSecurity
    init(_ label: String, _ address: String, _ strength: Int, _ protection: CWSecurity) {
        self.label = label; self.address = address; self.strength = strength; self.protection = protection
        super.init()
    }
    required init?(coder: NSCoder) { return nil }
    override var ssid: String? { label }
    override var ssidData: Data? { Data(label.utf8) }
    override var bssid: String? { address }
    override var rssiValue: Int { strength }
    override func supportsSecurity(_ security: CWSecurity) -> Bool { security == protection }
}

struct WiFiControlTests {
    @Test
    @MainActor
    func testProjectionSecuritySignalAndKeychainLookup() async throws {
        let connected = ScannedNetwork("Home", "aa", -80, .wpa2Personal)
        let stronger = ScannedNetwork("Home", "bb", -40, .wpa2Personal)
        let openTwin = ScannedNetwork("Home", "cc", -30, .none)
        let hidden = ScannedNetwork("", "dd", -20, .none)
        let rows = WiFiChoice.choices(from: [connected, stronger, openTwin, hidden], connectedBSSID: "AA")
        #expect(rows.count == 2, "Hidden SSIDs are omitted; open and secured names stay separate")
        #expect(rows.first(where: { $0.secure })?.network === connected, "Keep the associated BSSID, not the strongest sibling")
        #expect(Set(rows.map(\.id)).count == 2, "Security belongs to network and credential identity")
        #expect(WiFiChoice.choices(from: [connected, stronger], connectedBSSID: nil).first?.network === stronger)
        #expect(WiFiChoice.warning(for: .WEP) != nil && WiFiChoice.warning(for: .wpaPersonal) != nil)
        #expect(WiFiChoice.warning(for: .wpa2Personal) == nil && WiFiChoice.warning(for: .wpa3Personal) == nil)
        #expect(WiFiChoice.warning(for: .unknown) == nil, "Unknown must not be called secure or weak")
        #expect(WiFiChoice.signalLevel(-45) == 3 && WiFiChoice.signalLevel(-65) == 2 && WiFiChoice.signalLevel(-85) == 1)
        #expect(WiFiChoice.signalLevel(0) == nil, "Unavailable RSSI is not maximum strength")
        #expect(WiFiChoice(network: ScannedNetwork("Office", "ee", -50, .wpa2Enterprise), name: "Office").requiresSystemJoin)
        let ssid = Data("Keychain test".utf8)
        var domains: [CWKeychainDomain] = []
        let found = WiFiPasswordLookup.find(ssid: ssid) { domain, data in
            #expect(data == ssid, "Only the selected SSID may be queried")
            domains.append(domain)
            return domain == .user ? (errSecItemNotFound, nil) : (errSecSuccess, "test-secret")
        }
        #expect(found == .found("test-secret") && domains == [.user, .system])
        for status in [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed] {
            domains = []
            let result = WiFiPasswordLookup.find(ssid: ssid) { domain, _ in domains.append(domain); return (status, nil) }
            #expect(domains == [.user], "Do not trigger another prompt after cancellation or access failure")
            #expect(result == (status == errSecInteractionNotAllowed ? .unavailable : .cancelled))
        }
        #expect(WiFiPasswordLookup.find(ssid: ssid) { _, _ in (errSecSuccess, "") } == .unavailable)
        #expect(WiFiPasswordLookup.find(ssid: Data()) { _, _ in Issue.record("Empty SSID must not access keychain"); return (errSecItemNotFound, nil) } == .unavailable)
    }

    @Test
    @MainActor
    func testPasswordAuthorizationAssociationAndPersistence() async throws {
        let suite = "wifi-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let choice = WiFiChoice(network: ScannedNetwork(suite, "ff", -50, .wpa2Personal), name: suite)
        var reads = 0, joins = 0
        let control = WiFiControl(defaults: defaults, systemPassword: { _ in reads += 1; return .found("test-secret") }, associate: { _, password in
            #expect(password == "test-secret"); joins += 1
        })
        func settle(_ control: WiFiControl) async throws {
            for _ in 0..<200 {
                if !control.busy { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw NSError(domain: "WiFiControlTests.wait", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wi-Fi operation did not settle"])
        }
        control.powerOn = true; control.knownNames = [suite]
        control.join(choice); control.join(choice)
        #expect(control.isRequestingSystemPassword, "Keychain authorization must protect the panel while lookup is pending")
        try await settle(control)
        #expect(!control.isRequestingSystemPassword, "Network association is not a permission prompt")
        #expect(reads == 1 && joins == 1 && !control.connecting, "Single click workflow must reject duplicate actions")
        #expect(control.passwordRequest == nil && !control.hasSavedPassword(for: choice), "System password must not be copied into Combo storage")

        var cancelledReads = 0
        let cancelled = WiFiControl(defaults: defaults, systemPassword: { _ in cancelledReads += 1; return .cancelled }, associate: { _, _ in Issue.record("Cancelled authorization must not connect"); throw NSError(domain: "WiFiControlTests.associate", code: 1) })
        cancelled.powerOn = true; cancelled.knownNames = [suite]
        cancelled.join(choice); try await settle(cancelled)
        #expect(!cancelled.isRequestingSystemPassword, "Cancellation must release panel protection")
        #expect(cancelled.passwordRequest?.id == choice.id && cancelled.systemAccessDeclined)
        #expect(!cancelled.busy && !cancelled.connecting)
        cancelled.join(choice); try await settle(cancelled)
        #expect(cancelledReads == 1, "Do not repeat a declined prompt during this run")
        cancelled.allowSystemPasswordRequests()
        #expect(!cancelled.systemAccessDeclined)
        let stale = WiFiControl(defaults: defaults, systemPassword: { _ in .found("discard-this-secret") }, associate: { _, _ in Issue.record("Changed preference must invalidate pending lookup"); throw NSError(domain: "WiFiControlTests.associate", code: 1) })
        stale.powerOn = true; stale.knownNames = [suite]
        stale.join(choice); stale.useSystemPasswords = false; stale.useSystemPasswords = true
        try await settle(stale)
        #expect(stale.passwordRequest?.id == choice.id && !stale.connecting)
        cancelled.useSystemPasswords = false
        #expect(!WiFiControl(defaults: defaults).useSystemPasswords, "Preference must persist")
        let manual = WiFiControl(defaults: defaults, systemPassword: { _ in Issue.record("Disabled preference must not read system passwords"); return .unavailable }, associate: { _, password in
            #expect(password == "manual-test-secret")
        })
        manual.powerOn = true; manual.knownNames = [suite]
        manual.join(choice)
        #expect(manual.passwordRequest?.id == choice.id && !manual.busy)
        manual.connect(choice, password: "manual-test-secret", remember: false)
        try await settle(manual)
        #expect(!manual.hasSavedPassword(for: choice), "Unchecked remember must not store a manual password")
        // Only this random test account is written, then deleted; no real Wi-Fi credentials are used.
        defer { manual.deletePassword(for: choice) }
        manual.powerOn = true
        manual.connect(choice, password: "manual-test-secret", remember: true)
        try await settle(manual)
        #expect(manual.hasSavedPassword(for: choice), "Remembered manual password must be saved after success")
        manual.powerOn = true
        manual.connect(choice, password: "", remember: false)
        try await settle(manual)
        manual.deletePassword(for: choice)
        #expect(!manual.hasSavedPassword(for: choice), "User can remove Combo's saved password")
        let failed = WiFiControl(defaults: defaults, associate: { _, _ in throw NSError(domain: "Test", code: 1) })
        failed.powerOn = true
        failed.connect(choice, password: "failed-test-secret", remember: true)
        try await settle(failed)
        #expect(!failed.hasSavedPassword(for: choice) && failed.passwordRequest?.id == choice.id && !failed.connecting)
    }
}
