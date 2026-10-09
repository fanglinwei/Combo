import AppKit
import CoreAudio

@main struct OutputDeviceCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared

        func kind(_ transport: UInt32, _ name: String = "", _ classOfDevice: UInt32? = nil, _ model: String? = nil) -> OutputDeviceKind {
            OutputDeviceClassifier.classify(OutputSignals(transport: transport, name: name, model: model, classOfDevice: classOfDevice))
        }

        // 入口规则：只看默认输出设备的 transport。内置、显示器、USB 都不参与中央设备图标。
        assert(kind(kAudioDeviceTransportTypeBluetooth) == .bluetooth(.unknown))
        assert(kind(kAudioDeviceTransportTypeBluetoothLE) == .bluetooth(.unknown))
        assert(kind(kAudioDeviceTransportTypeAirPlay) == .airPlay(.other))
        assert(kind(kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        assert(kind(kAudioDeviceTransportTypeHDMI) == .display)
        assert(kind(kAudioDeviceTransportTypeDisplayPort) == .display)
        assert(kind(kAudioDeviceTransportTypeUSB) == .other)
        assert(kind(0) == .other)

        // 名称关键字
        assert(kind(kAudioDeviceTransportTypeBluetooth, "方林威的AirPods Pro") == .bluetooth(.airPodsPro))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "AirPods Max") == .bluetooth(.airPodsMax))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "轻舟已过万重山的AirPods") == .bluetooth(.airPods))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Beats Studio Pro") == .bluetooth(.beats))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Galaxy Buds2 Pro") == .bluetooth(.earbuds))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "JBL Flip 5 Speaker") == .bluetooth(.speaker))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "WH-1000XM5") == .bluetooth(.headphones))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "客厅的车载蓝牙") == .bluetooth(.car))
        // 按键匹配：不能把 Carl's Headphones 当车机，也不能把 Rosebuds 当真无线
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Carl's Headphones") == .bluetooth(.headphones))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Oscar") == .bluetooth(.unknown))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Cardo Packtalk") == .bluetooth(.unknown))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Rosebuds") == .bluetooth(.unknown))
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Galaxy Buds2 Pro") == .bluetooth(.earbuds), "Generation suffixes must still match")
        // 改名后既没有关键字也没有其它信号：走 unknown，不许猜。
        assert(kind(kAudioDeviceTransportTypeBluetooth, "我的耳机") == .bluetooth(.unknown))

        // Class of Device：major 在 bit 8–12，minor 在 bit 2–7；minor 只在 major == 0x04 时有意义。
        assert(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x06 << 2)) == .headphones)
        assert(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x01 << 2)) == .headphones)
        assert(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x05 << 2)) == .speaker)
        assert(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x0a << 2)) == .speaker)
        assert(BluetoothFamily.matching(classOfDevice: (0x04 << 8) | (0x08 << 2)) == .car)
        assert(BluetoothFamily.matching(classOfDevice: (0x09 << 8) | (0x06 << 2)) == .hearingAid)
        assert(BluetoothFamily.matching(classOfDevice: (0x01 << 8) | (0x06 << 2)) == nil, "Audio minor values outside Audio/Video must be ignored")
        assert(BluetoothFamily.matching(classOfDevice: 0) == nil, "A zero class of device is not a category")
        assert(kind(kAudioDeviceTransportTypeBluetooth, "客厅", 0) == .bluetooth(.unknown), "A zero class of device must not fabricate a category")
        assert(kind(kAudioDeviceTransportTypeBluetooth, "", (0x04 << 8) | (0x0a << 2)) == .bluetooth(.speaker), "Class of device is a hint when the name says nothing")
        assert(kind(kAudioDeviceTransportTypeBluetooth, "Bose Headphones", (0x04 << 8) | (0x05 << 2)) == .bluetooth(.speaker), "Structured category hints outrank generic name keywords")

        // AirPlay 机型：modelID → 档位。ID 表来自 libirecovery（第三方维护，未实机验证）
        assert(AirPlayFamily.matching(model: "AppleTV14,1") == .appleTV)
        assert(AirPlayFamily.matching(model: "appletv6,2") == .appleTV)
        assert(AirPlayFamily.matching(model: "AudioAccessory1,1") == .homePod)
        assert(AirPlayFamily.matching(model: "AudioAccessory1,2") == .homePod)
        assert(AirPlayFamily.matching(model: "AudioAccessory6,1") == .homePod)
        assert(AirPlayFamily.matching(model: "AudioAccessory5,1") == .homePodMini)
        assert(AirPlayFamily.matching(model: "AudioAccessory9,9") == .homePod, "A future HomePod must stay in the HomePod family")
        assert(AirPlayFamily.matching(model: "AirPort10,115") == .other, "No evidence for AirPort identifiers: do not guess")
        assert(AirPlayFamily.matching(model: "Sonos-Playbar") == .other)
        assert(AirPlayFamily.matching(model: nil) == .other)
        assert(AirPlayFamily.matching(model: "   ") == .other)
        assert(kind(kAudioDeviceTransportTypeAirPlay, "", nil, "AppleTV14,1") == .airPlay(.appleTV), "A routed Apple TV must classify from its modelID")
        assert(kind(kAudioDeviceTransportTypeAirPlay, "", nil, "AudioAccessory5,1") == .airPlay(.homePodMini))
        assert(kind(kAudioDeviceTransportTypeAirPlay, "", nil, "Sonos-Playbar") == .airPlay(.other))
        assert(kind(kAudioDeviceTransportTypeAirPlay) == .airPlay(.other), "Without a modelID AirPlay stays generic")
        assert(OutputDeviceClassifier.glyph(for: .airPlay(.appleTV)) == .symbol("appletv"))
        assert(OutputDeviceClassifier.glyph(for: .airPlay(.homePod)) == .symbol("homepod"))
        assert(OutputDeviceClassifier.glyph(for: .airPlay(.homePodMini)) == .symbol("homepod.mini"))
        assert(OutputDeviceClassifier.glyph(for: .airPlay(.other)) == .symbol("airplay.audio"))

        // 中央与输出列表共用同一份路由信息：只有被探测过的那台设备能拿到
        var route = AirPlayRoute()
        assert(!route.hasProbed && route.info(for: 86) == nil)
        let request = route.begin(deviceID: 86, target: String(repeating: "a", count: 64))
        assert(route.hasProbed && route.info(for: 86) == nil, "占位期间不得给出名称或机型，避免画出猜错的符号")
        route.record(AirPlayRoute.Info(name: "客厅", model: "AppleTV14,1", canSetVolume: false), for: request)
        assert(route.name(for: 86) == "客厅" && route.model(for: 86) == "AppleTV14,1")
        assert(route.info(for: 86)?.family == .appleTV && route.info(for: 86)?.canSetVolume == false)
        assert(route.name(for: 72) == nil && route.model(for: 72) == nil, "其它输出设备不得拿到，否则列表与中央会各显示一套")
        route.record(AirPlayRoute.Info(name: "   ", model: "", canSetVolume: true), for: request)
        assert(route.name(for: 86) == nil && route.model(for: 86) == nil, "空名称/空机型必须退回 CoreAudio 名称与统一符号")
        assert(route.info(for: 86)?.canSetVolume == true)
        let replacement = route.begin(deviceID: 87, target: String(repeating: "b", count: 64))
        route.record(AirPlayRoute.Info(name: "stale", model: "AppleTV14,1"), for: request)
        assert(route.info(for: 87) == nil, "An old request must not fill a new device cache")
        route.record(AirPlayRoute.Info(name: "书房", model: "AudioAccessory5,1"), for: replacement)
        assert(route.name(for: 87) == "书房")
        route.clear()
        route.record(AirPlayRoute.Info(name: "stale"), for: replacement)
        assert(route.info == nil, "Cleared caches must reject late replies")
        let sameDevice = route.begin(deviceID: 87, target: replacement.target)
        route.record(AirPlayRoute.Info(name: "stale"), for: replacement)
        assert(route.info == nil && sameDevice != replacement, "Reused IDs and UIDs still need a new request serial")
        route.clear()
        assert(!route.hasProbed && route.info(for: 86) == nil)
        assert(kind(kAudioDeviceTransportTypeAirPlay, "", nil, route.model(for: 86)) == .airPlay(.other), "清空后必须回到统一符号")

        // 附近设备筛选：排除本机自己与当前已路由的那台，按名称去重
        let nearby = [DiscoveredAirPlay(id: "客厅", name: "客厅", model: "AppleTV14,1"),
                      DiscoveredAirPlay(id: "MacBook Air", name: "MacBook Air", model: "MacBookAir10,1"),
                      DiscoveredAirPlay(id: "客厅", name: "客厅", model: "AppleTV14,1"),
                      DiscoveredAirPlay(id: "", name: "", model: ""),
                      DiscoveredAirPlay(id: "书房", name: "书房", model: "AudioAccessory5,1")]
        let visible = AirPlayDiscovery.visible(nearby, selfName: "MacBook Air", routedName: "客厅")
        assert(visible.map(\.name) == ["书房"], "附近列表应去掉本机与当前已路由的设备，并去重")
        assert(visible.first?.family == .homePodMini)
        assert(Set(AirPlayDiscovery.visible(nearby, selfName: "MacBook Air", routedName: nil).map(\.name)) == ["书房", "客厅"],
               "没有已路由设备时，客厅应作为附近设备出现")

        // helper `--route` 的 JSON 契约
        let reply = try JSONDecoder().decode(AirPlayRouteReply.self, from: Data(#"{"deviceID":86,"target":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","endpointID":"receiver-a","model":"AppleTV14,1","name":"客厅","canSetVolume":false}"#.utf8))
        assert(reply.model == "AppleTV14,1" && reply.name == "客厅" && reply.canSetVolume == false)
        assert(AirPlayFamily.matching(model: reply.model) == .appleTV)
        assert((try? JSONDecoder().decode(AirPlayRouteReply.self, from: Data(#"{"model":""}"#.utf8))) == nil,
               "缺字段的回复必须解码失败，从而退回 CoreAudio 名称与统一符号")

        // 只有蓝牙与 AirPlay 参与中央图标
        assert(OutputDeviceKind.bluetooth(.speaker).showsDeviceGlyph)
        assert(OutputDeviceKind.airPlay(.other).showsDeviceGlyph)
        for passive: OutputDeviceKind in [.builtIn, .display, .other] {
            assert(!passive.showsDeviceGlyph, "Non-audio-route transports must keep the current center content")
        }

        // 耳机专属控制只对 AirPods 家族开放
        assert(OutputDeviceKind.bluetooth(.airPodsPro).isAirPods)
        assert(OutputDeviceKind.bluetooth(.airPods).isAirPods)
        assert(OutputDeviceKind.bluetooth(.airPodsMax).isAirPods)
        assert(!OutputDeviceKind.bluetooth(.beats).isAirPods)
        assert(!OutputDeviceKind.airPlay(.appleTV).isAirPods)

        // 每一档都有字形，而且字形必须能被系统解析——解析失败会退到 headphones，但不该发生。
        var names: [String] = []
        for family in BluetoothFamily.allCases {
            if case .symbol(let name) = OutputDeviceClassifier.glyph(for: .bluetooth(family)) { names.append(name) }
            else { assertionFailure("Every Bluetooth family needs a symbol") }
        }
        for passive: OutputDeviceKind in [.builtIn, .display, .airPlay(.other), .other] {
            if case .symbol(let name) = OutputDeviceClassifier.glyph(for: passive) { names.append(name) }
            else { assertionFailure("Non-Bluetooth categories need a list symbol") }
        }
        for name in names + ["headphones"] {
            assert(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "SF Symbol \(name) must resolve")
        }
        print("PASS: output device classification, class-of-device gating and glyph resolution")
    }
}
