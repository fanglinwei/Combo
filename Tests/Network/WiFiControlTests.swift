import Testing
import CoreWLAN

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
    func testProjectionSecurityAndSignal() async throws {
        let connected = ScannedNetwork("Home", "aa", -80, .wpa2Personal)
        let stronger = ScannedNetwork("Home", "bb", -40, .wpa2Personal)
        let openTwin = ScannedNetwork("Home", "cc", -30, .none)
        let hidden = ScannedNetwork("", "dd", -20, .none)
        let rows = WiFiChoice.choices(from: [connected, stronger, openTwin, hidden], connectedBSSID: "AA")
        #expect(rows.count == 2, "Hidden SSIDs are omitted; open and secured names stay separate")
        #expect(rows.first(where: { $0.secure })?.network === connected, "Keep the associated BSSID, not the strongest sibling")
        #expect(Set(rows.map(\.id)).count == 2, "Security belongs to network identity")
        #expect(WiFiChoice.choices(from: [connected, stronger], connectedBSSID: nil).first?.network === stronger)
        #expect(WiFiChoice.warning(for: .WEP) != nil && WiFiChoice.warning(for: .wpaPersonal) != nil)
        #expect(WiFiChoice.warning(for: .wpa2Personal) == nil && WiFiChoice.warning(for: .wpa3Personal) == nil)
        #expect(WiFiChoice.warning(for: .unknown) == nil, "Unknown must not be called secure or weak")
        #expect(WiFiChoice.signalLevel(-45) == 3 && WiFiChoice.signalLevel(-65) == 2 && WiFiChoice.signalLevel(-85) == 1)
        #expect(WiFiChoice.signalLevel(0) == nil, "Unavailable RSSI is not maximum strength")
    }
}
