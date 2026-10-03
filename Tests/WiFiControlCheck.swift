import CoreWLAN
import Security

// Hardware results are the boundary; projection and security rules are production code.
final class ScannedNetwork: CWNetwork {
    let label: String
    let address: String
    let strength: Int
    let protection: CWSecurity
    init(_ label: String, _ address: String, _ strength: Int, _ protection: CWSecurity) {
        self.label = label; self.address = address; self.strength = strength; self.protection = protection
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("unused") }
    override var ssid: String? { label }
    override var ssidData: Data? { Data(label.utf8) }
    override var bssid: String? { address }
    override var rssiValue: Int { strength }
    override func supportsSecurity(_ security: CWSecurity) -> Bool { security == protection }
}

@main struct WiFiControlCheck {
    @MainActor static func main() async throws {
        let connected = ScannedNetwork("Home", "aa", -80, .wpa2Personal)
        let stronger = ScannedNetwork("Home", "bb", -40, .wpa2Personal)
        let openTwin = ScannedNetwork("Home", "cc", -30, .none)
        let hidden = ScannedNetwork("", "dd", -20, .none)
        let rows = WiFiChoice.choices(from: [connected, stronger, openTwin, hidden], connectedBSSID: "AA")
        assert(rows.count == 2, "Hidden SSIDs are omitted; open and secured names stay separate")
        assert(rows.first(where: { $0.secure })?.network === connected, "Keep the associated BSSID, not the strongest sibling")
        assert(Set(rows.map(\.id)).count == 2, "Security belongs to network and credential identity")
        assert(WiFiChoice.choices(from: [connected, stronger], connectedBSSID: nil).first?.network === stronger)
        assert(WiFiChoice.warning(for: .WEP) != nil && WiFiChoice.warning(for: .wpaPersonal) != nil)
        assert(WiFiChoice.warning(for: .wpa2Personal) == nil && WiFiChoice.warning(for: .wpa3Personal) == nil)
        assert(WiFiChoice.warning(for: .unknown) == nil, "Unknown must not be called secure or weak")
        assert(WiFiChoice.signalLevel(-45) == 3 && WiFiChoice.signalLevel(-65) == 2 && WiFiChoice.signalLevel(-85) == 1)
        assert(WiFiChoice.signalLevel(0) == nil, "Unavailable RSSI is not maximum strength")
        assert(WiFiChoice(network: ScannedNetwork("Office", "ee", -50, .wpa2Enterprise), name: "Office").requiresSystemJoin)
        let ssid = Data("Keychain test".utf8)
        var domains: [CWKeychainDomain] = []
        let found = WiFiPasswordLookup.find(ssid: ssid) { domain, data in
            assert(data == ssid, "Only the selected SSID may be queried")
            domains.append(domain)
            return domain == .user ? (errSecItemNotFound, nil) : (errSecSuccess, "test-secret")
        }
        assert(found == .found("test-secret") && domains == [.user, .system])
        for status in [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed] {
            domains = []
            let result = WiFiPasswordLookup.find(ssid: ssid) { domain, _ in domains.append(domain); return (status, nil) }
            assert(domains == [.user], "Do not trigger another prompt after cancellation or access failure")
            assert(result == (status == errSecInteractionNotAllowed ? .unavailable : .cancelled))
        }
        assert(WiFiPasswordLookup.find(ssid: ssid) { _, _ in (errSecSuccess, "") } == .unavailable)
        assert(WiFiPasswordLookup.find(ssid: Data()) { _, _ in fatalError("Empty SSID must not access keychain") } == .unavailable)

        let suite = "wifi-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let choice = WiFiChoice(network: ScannedNetwork(suite, "ff", -50, .wpa2Personal), name: suite)
        var reads = 0, joins = 0
        let control = WiFiControl(defaults: defaults, systemPassword: { _ in reads += 1; return .found("test-secret") }, associate: { _, password in
            assert(password == "test-secret"); joins += 1
        })
        func settle(_ control: WiFiControl) async throws {
            for _ in 0..<200 {
                if !control.busy { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            fatalError("Wi-Fi operation did not settle")
        }
        control.powerOn = true; control.knownNames = [suite]
        control.join(choice); control.join(choice)
        assert(control.isRequestingSystemPassword, "Keychain authorization must protect the panel while lookup is pending")
        try await settle(control)
        assert(!control.isRequestingSystemPassword, "Network association is not a permission prompt")
        assert(reads == 1 && joins == 1 && !control.connecting, "Single click workflow must reject duplicate actions")
        assert(control.passwordRequest == nil && !control.hasSavedPassword(for: choice), "System password must not be copied into Combo storage")

        var cancelledReads = 0
        let cancelled = WiFiControl(defaults: defaults, systemPassword: { _ in cancelledReads += 1; return .cancelled }, associate: { _, _ in fatalError("Cancelled authorization must not connect") })
        cancelled.powerOn = true; cancelled.knownNames = [suite]
        cancelled.join(choice); try await settle(cancelled)
        assert(!cancelled.isRequestingSystemPassword, "Cancellation must release panel protection")
        assert(cancelled.passwordRequest?.id == choice.id && cancelled.systemAccessDeclined)
        assert(!cancelled.busy && !cancelled.connecting)
        cancelled.join(choice); try await settle(cancelled)
        assert(cancelledReads == 1, "Do not repeat a declined prompt during this run")
        cancelled.allowSystemPasswordRequests()
        assert(!cancelled.systemAccessDeclined)
        let stale = WiFiControl(defaults: defaults, systemPassword: { _ in .found("discard-this-secret") }, associate: { _, _ in fatalError("Changed preference must invalidate pending lookup") })
        stale.powerOn = true; stale.knownNames = [suite]
        stale.join(choice); stale.useSystemPasswords = false; stale.useSystemPasswords = true
        try await settle(stale)
        assert(stale.passwordRequest?.id == choice.id && !stale.connecting)
        cancelled.useSystemPasswords = false
        assert(!WiFiControl(defaults: defaults).useSystemPasswords, "Preference must persist")
        let manual = WiFiControl(defaults: defaults, systemPassword: { _ in fatalError("Disabled preference must not read system passwords") }, associate: { _, password in
            assert(password == "manual-test-secret")
        })
        manual.powerOn = true; manual.knownNames = [suite]
        manual.join(choice)
        assert(manual.passwordRequest?.id == choice.id && !manual.busy)
        manual.connect(choice, password: "manual-test-secret", remember: false)
        try await settle(manual)
        assert(!manual.hasSavedPassword(for: choice), "Unchecked remember must not store a manual password")
        // Only this random test account is written, then deleted; no real Wi-Fi credentials are used.
        defer { manual.deletePassword(for: choice) }
        manual.powerOn = true
        manual.connect(choice, password: "manual-test-secret", remember: true)
        try await settle(manual)
        assert(manual.hasSavedPassword(for: choice), "Remembered manual password must be saved after success")
        manual.powerOn = true
        manual.connect(choice, password: "", remember: false)
        try await settle(manual)
        manual.deletePassword(for: choice)
        assert(!manual.hasSavedPassword(for: choice), "User can remove Combo's saved password")
        let failed = WiFiControl(defaults: defaults, associate: { _, _ in throw NSError(domain: "Test", code: 1) })
        failed.powerOn = true
        failed.connect(choice, password: "failed-test-secret", remember: true)
        try await settle(failed)
        assert(!failed.hasSavedPassword(for: choice) && failed.passwordRequest?.id == choice.id && !failed.connecting)
        print("Wi-Fi system password: targeted lookup, cancellation, no duplicate prompts, local-copy exclusion and preferences passed")
        print("Wi-Fi projection, security and signal checks passed")
    }
}
