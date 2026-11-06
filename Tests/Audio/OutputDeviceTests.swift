import Testing
import AppKit
import CoreAudio

struct OutputDeviceTests {
    private func kind(_ transport: UInt32, _ name: String = "", _ classOfDevice: UInt32? = nil, _ model: String? = nil) -> OutputDeviceKind {
        OutputDeviceClassifier.classify(OutputSignals(transport: transport, name: name, model: model, classOfDevice: classOfDevice))
    }

    @Test
    @MainActor
    func testTransportGating() async throws {
        // 入口规则：只看默认输出设备的 transport。内置、显示器、USB 都不参与中央设备图标。
        #expect(kind(kAudioDeviceTransportTypeBluetooth) == .bluetooth(.unknown))
        #expect(kind(kAudioDeviceTransportTypeBluetoothLE) == .bluetooth(.unknown))
        #expect(kind(kAudioDeviceTransportTypeAirPlay) == .airPlay(.other))
        #expect(kind(kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(kind(kAudioDeviceTransportTypeHDMI) == .display)
        #expect(kind(kAudioDeviceTransportTypeDisplayPort) == .display)
        #expect(kind(kAudioDeviceTransportTypeUSB) == .other)
        #expect(kind(0) == .other)
    }

    @Test
    @MainActor
    func testDeviceNames() async throws {
        // 名称关键字
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "方林威的AirPods Pro") == .bluetooth(.airPodsPro))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "AirPods Max") == .bluetooth(.airPodsMax))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "轻舟已过万重山的AirPods") == .bluetooth(.airPods))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Beats Studio Pro") == .bluetooth(.beats))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Galaxy Buds2 Pro") == .bluetooth(.earbuds))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "JBL Flip 5 Speaker") == .bluetooth(.speaker))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "WH-1000XM5") == .bluetooth(.headphones))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "客厅的车载蓝牙") == .bluetooth(.car))
    }

    @Test
    @MainActor
    func testNameWordBoundaries() async throws {
        // 按键匹配：不能把 Carl's Headphones 当车机，也不能把 Rosebuds 当真无线
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Carl's Headphones") == .bluetooth(.headphones))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Oscar") == .bluetooth(.unknown))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Cardo Packtalk") == .bluetooth(.unknown))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Rosebuds") == .bluetooth(.unknown))
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Galaxy Buds2 Pro") == .bluetooth(.earbuds), "Generation suffixes must still match")
    }

    @Test
    @MainActor
    func testUnknownRenamedDevices() async throws {
        // 改名后既没有关键字也没有其它信号：走 unknown，不许猜。
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "我的耳机") == .bluetooth(.unknown))
    }

    @Test
    @MainActor
    func testClassOfDevice() async throws {
        // Class of Device：major 在 bit 8–12，minor 在 bit 2–7；minor 只在 major == 0x04 时有意义。
        #expect(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x06 << 2)) == .headphones)
        #expect(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x01 << 2)) == .headphones)
        #expect(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x05 << 2)) == .speaker)
        #expect(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x0a << 2)) == .speaker)
        #expect(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x08 << 2)) == .car)
        #expect(BluetoothFamily.matching(classOfDevice: (0x09 << 8) | (0x06 << 2)) == .hearingAid)
        #expect(BluetoothFamily.matching(classOfDevice: (0x01 << 8) | (0x06 << 2)) == nil, "Audio minor values outside Audio/Video must be ignored")
        #expect(BluetoothFamily.matching(classOfDevice: 0) == nil, "A zero class of device is not a category")
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "客厅", 0) == .bluetooth(.unknown), "A zero class of device must not fabricate a category")
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "", (0x04 << 8) | (0x0a << 2)) == .bluetooth(.speaker), "Class of device is a hint when the name says nothing")
        #expect(kind(kAudioDeviceTransportTypeBluetooth, "Bose Headphones", (0x04 << 8) | (0x05 << 2)) == .bluetooth(.speaker), "Structured category hints outrank generic name keywords")
    }

    @Test
    @MainActor
    func testAirPlayModels() async throws {
        // AirPlay 机型：modelID → 档位。ID 表来自 libirecovery（第三方维护，未实机验证）
        #expect(AirPlayFamily.matching(model: "AppleTV14,1") == .appleTV)
        #expect(AirPlayFamily.matching(model: "appletv6,2") == .appleTV)
        #expect(AirPlayFamily.matching(model: "AudioAccessory1,1") == .homePod)
        #expect(AirPlayFamily.matching(model: "AudioAccessory1,2") == .homePod)
        #expect(AirPlayFamily.matching(model: "AudioAccessory6,1") == .homePod)
        #expect(AirPlayFamily.matching(model: "AudioAccessory5,1") == .homePodMini)
        #expect(AirPlayFamily.matching(model: "AudioAccessory9,9") == .homePod, "A future HomePod must stay in the HomePod family")
        #expect(AirPlayFamily.matching(model: "AirPort10,115") == .other, "No evidence for AirPort identifiers: do not guess")
        #expect(AirPlayFamily.matching(model: "Sonos-Playbar") == .other)
        #expect(AirPlayFamily.matching(model: nil) == .other)
        #expect(AirPlayFamily.matching(model: "   ") == .other)
        #expect(kind(kAudioDeviceTransportTypeAirPlay, "", nil, "AppleTV14,1") == .airPlay(.appleTV), "A routed Apple TV must classify from its modelID")
        #expect(kind(kAudioDeviceTransportTypeAirPlay, "", nil, "AudioAccessory5,1") == .airPlay(.homePodMini))
        #expect(kind(kAudioDeviceTransportTypeAirPlay, "", nil, "Sonos-Playbar") == .airPlay(.other))
        #expect(kind(kAudioDeviceTransportTypeAirPlay) == .airPlay(.other), "Without a modelID AirPlay stays generic")
        #expect(OutputDeviceClassifier.glyph(for: .airPlay(.appleTV)) == .symbol("appletv"))
        #expect(OutputDeviceClassifier.glyph(for: .airPlay(.homePod)) == .symbol("homepod"))
        #expect(OutputDeviceClassifier.glyph(for: .airPlay(.homePodMini)) == .symbol("homepod.mini"))
        #expect(OutputDeviceClassifier.glyph(for: .airPlay(.other)) == .symbol("airplay.audio"))
    }

    @Test
    @MainActor
    func testRouteCacheIdentity() async throws {
        // 中央与输出列表共用同一份路由信息：只有被探测过的那台设备能拿到
        var route = AirPlayRoute()
        #expect(!route.hasProbed && route.info(for: 86) == nil)
        let request = route.begin(deviceID: 86, target: String(repeating: "a", count: 64))
        #expect(route.hasProbed && route.info(for: 86) == nil, "占位期间不得给出名称或机型，避免画出猜错的符号")
        route.record(AirPlayRoute.Info(name: "客厅", model: "AppleTV14,1", canSetVolume: false), for: request)
        #expect(route.name(for: 86) == "客厅" && route.model(for: 86) == "AppleTV14,1")
        #expect(route.info(for: 86)?.family == .appleTV && route.info(for: 86)?.canSetVolume == false)
        #expect(route.name(for: 72) == nil && route.model(for: 72) == nil, "其它输出设备不得拿到，否则列表与中央会各显示一套")
        route.record(AirPlayRoute.Info(name: "   ", model: "", canSetVolume: true), for: request)
        #expect(route.name(for: 86) == nil && route.model(for: 86) == nil, "空名称/空机型必须退回 CoreAudio 名称与统一符号")
        #expect(route.info(for: 86)?.canSetVolume == true)
        let replacement = route.begin(deviceID: 87, target: String(repeating: "b", count: 64))
        route.record(AirPlayRoute.Info(name: "stale", model: "AppleTV14,1"), for: request)
        #expect(route.info(for: 87) == nil, "An old request must not fill a new device cache")
        route.record(AirPlayRoute.Info(name: "书房", model: "AudioAccessory5,1"), for: replacement)
        #expect(route.name(for: 87) == "书房")
        route.clear()
        route.record(AirPlayRoute.Info(name: "stale"), for: replacement)
        #expect(route.info == nil, "Cleared caches must reject late replies")
        let sameDevice = route.begin(deviceID: 87, target: replacement.target)
        route.record(AirPlayRoute.Info(name: "stale"), for: replacement)
        #expect(route.info == nil && sameDevice != replacement, "Reused IDs and UIDs still need a new request serial")
        route.clear()
        #expect(!route.hasProbed && route.info(for: 86) == nil)
        #expect(kind(kAudioDeviceTransportTypeAirPlay, "", nil, route.model(for: 86)) == .airPlay(.other), "清空后必须回到统一符号")
    }

    @Test
    @MainActor
    func testNearbyDeviceFiltering() async throws {
        // 附近设备筛选：排除本机自己与当前已路由的那台，按名称去重
        let nearby = [DiscoveredAirPlay(id: "客厅", name: "客厅", model: "AppleTV14,1"),
                      DiscoveredAirPlay(id: "MacBook Air", name: "MacBook Air", model: "MacBookAir10,1"),
                      DiscoveredAirPlay(id: "客厅", name: "客厅", model: "AppleTV14,1"),
                      DiscoveredAirPlay(id: "", name: "", model: ""),
                      DiscoveredAirPlay(id: "书房", name: "书房", model: "AudioAccessory5,1")]
        let visible = AirPlayDiscovery.visible(nearby, selfName: "MacBook Air", routedName: "客厅")
        #expect(visible.map(\.name) == ["书房"], "附近列表应去掉本机与当前已路由的设备，并去重")
        #expect(visible.first?.family == .homePodMini)
        #expect(Set(AirPlayDiscovery.visible(nearby, selfName: "MacBook Air", routedName: nil).map(\.name)) == ["书房", "客厅"],
               "没有已路由设备时，客厅应作为附近设备出现")
    }

    @Test
    @MainActor
    func testRouteReplyContract() async throws {
        // helper `--route` 的 JSON 契约
        let reply = try JSONDecoder().decode(AirPlayRouteReply.self, from: Data(#"{"deviceID":86,"target":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","endpointID":"receiver-a","model":"AppleTV14,1","name":"客厅","canSetVolume":false}"#.utf8))
        #expect(reply.model == "AppleTV14,1" && reply.name == "客厅" && reply.canSetVolume == false)
        #expect(AirPlayFamily.matching(model: reply.model) == .appleTV)
        #expect((try? JSONDecoder().decode(AirPlayRouteReply.self, from: Data(#"{"model":""}"#.utf8))) == nil,
               "缺字段的回复必须解码失败，从而退回 CoreAudio 名称与统一符号")
    }

    @Test
    @MainActor
    func testCentralGlyphEligibility() async throws {
        // 只有蓝牙与 AirPlay 参与中央图标
        #expect(OutputDeviceKind.bluetooth(.speaker).showsDeviceGlyph)
        #expect(OutputDeviceKind.airPlay(.other).showsDeviceGlyph)
        for passive: OutputDeviceKind in [.builtIn, .display, .other] {
            #expect(!passive.showsDeviceGlyph, "Non-audio-route transports must keep the current center content")
        }
    }

    @Test
    @MainActor
    func testAirPodsControlEligibility() async throws {
        // 耳机专属控制只对 AirPods 家族开放
        #expect(OutputDeviceKind.bluetooth(.airPodsPro).isAirPods)
        #expect(OutputDeviceKind.bluetooth(.airPods).isAirPods)
        #expect(OutputDeviceKind.bluetooth(.airPodsMax).isAirPods)
        #expect(!OutputDeviceKind.bluetooth(.beats).isAirPods)
        #expect(!OutputDeviceKind.airPlay(.appleTV).isAirPods)
    }

    @Test
    @MainActor
    func testSystemGlyphResolution() async throws {
        // 每一档都有字形，而且字形必须能被系统解析——解析失败会退到 headphones，但不该发生。
        var names: [String] = []
        for family in BluetoothFamily.allCases {
            if case .symbol(let name) = OutputDeviceClassifier.glyph(for: .bluetooth(family)) { names.append(name) }
            else { Issue.record("Every Bluetooth family needs a symbol") }
        }
        for passive: OutputDeviceKind in [.builtIn, .display, .airPlay(.other), .other] {
            if case .symbol(let name) = OutputDeviceClassifier.glyph(for: passive) { names.append(name) }
            else { Issue.record("Non-Bluetooth categories need a list symbol") }
        }
        for name in names + ["headphones"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "SF Symbol \(name) must resolve")
        }
    }
}
