import Foundation

struct IconPreviewVariant {
    let titleKey: String
    let snapshot: Snapshot
    var detailKey: String? = nil
    var title: String { LKey(titleKey) }
    var detail: String? { detailKey.map(LKey) }
}

struct IconPreviewScene: Identifiable {
    let titleKey: String
    let conditionKey: String
    let descriptionKey: String
    var variants: [IconPreviewVariant]
    var id: String { titleKey }
    var title: String { LKey(titleKey) }
    var condition: String { LKey(conditionKey) }
    var detail: String { LKey(descriptionKey) }
}

enum IconPreviewGroup: String, CaseIterable, Identifiable {
    case network = "网络", devices = "音频设备", power = "电量与供电", audio = "音量与播放"
    var id: String { rawValue }
    var title: String { LKey(rawValue) }

    static var sceneCount: Int { allCases.reduce(0) { $0 + $1.scenes.count } }

    var scenes: [IconPreviewScene] {
        func scene(_ title: String, _ condition: String, _ description: String, _ configure: (inout Snapshot) -> Void = { _ in }) -> IconPreviewScene {
            var snapshot = Snapshot.demo(.wired)
            configure(&snapshot)
            return IconPreviewScene(titleKey: title, conditionKey: condition, descriptionKey: description,
                                    variants: [IconPreviewVariant(titleKey: "默认", snapshot: snapshot)])
        }
        func device(_ title: String, _ condition: String, _ description: String, _ kind: OutputDeviceKind,
                    families: [(String, AudioIconFamily)] = []) -> [IconPreviewScene] {
            let models: [(String, AudioIconFamily?)] = families.isEmpty
                ? [(title, nil)] : families.map { ($0.0, $0.1) }
            return models.map { name, family in
                scene(name, condition, description) {
                    $0.deviceKind = kind
                    $0.audioIconFamily = family
                    $0.output = LocalizedText { LKey(name) }
                }
            }
        }
        switch self {
        case .network:
            return [
                scene("Wi-Fi 正常", "Wi-Fi 连接", "已识别为 Wi-Fi 连接；中央不区分信号强弱。") { $0.symbol = "wifi"; $0.network = "Wi-Fi" },
                scene("Wi-Fi 正在连接", "Wi-Fi 连接", "连接中使用原有 Wi-Fi 放大与脉冲，连接完成后恢复当前中央内容。") {
                    $0.symbol = "wifi"; $0.network = "Wi-Fi 正在连接"; $0.wifiConnecting = true
                },
                scene("Wi-Fi 已关闭", "无线接口已关闭", "Wi-Fi 已关闭时，中央显示带斜线的 Wi-Fi。") { $0.symbol = "wifi.slash"; $0.network = "Wi-Fi 已关闭" },
                scene("无可用网络路径", "没有可用网络路径", "系统未报告可用网络路径，中央显示 Wi-Fi 与感叹号。") { $0.symbol = "exclamationmark"; $0.network = "无可用路径" },
                scene("等待识别", "读取中或类型不确定", "仍在读取，或连接类型不确定时，中央显示短横线。") { $0.symbol = "minus"; $0.network = "正在读取" }
            ]
        case .devices:
            return [
                device("AirPods Pro", "蓝牙 · 默认输出", "当前默认输出为 AirPods Pro。", .bluetooth(.airPodsPro),
                       families: [("AirPods Pro 2", .airPodsPro2), ("AirPods Pro 1", .airPodsPro1), ("AirPods Pro 3", .airPodsPro3)]),
                device("AirPods", "蓝牙 · 默认输出", "当前默认输出为 AirPods。", .bluetooth(.airPods),
                       families: [("AirPods 1/2", .airPods), ("AirPods 3", .airPods3), ("AirPods 4", .airPods4)]),
                device("AirPods Max", "蓝牙 · 默认输出", "当前默认输出为 AirPods Max。", .bluetooth(.airPodsMax)),
                device("Beats 耳机", "蓝牙 · 默认输出", "预览 Beats 耳机与音箱的对应型号图标。", .bluetooth(.beats),
                       families: [("Beats 头戴式", .beatsHeadphones), ("Powerbeats Pro", .powerbeatsPro),
                                  ("Powerbeats Pro 2", .powerbeatsPro2), ("Beats Fit Pro", .beatsFitPro),
                                  ("Beats Studio Buds", .beatsStudioBuds), ("Beats Studio Buds +", .beatsStudioBudsPlus),
                                  ("Beats Solo Buds", .beatsSoloBuds), ("Beats 颈挂式", .beatsEarphones),
                                  ("Powerbeats", .powerbeats), ("Powerbeats 3", .powerbeats3), ("Beats Pill", .beatsPill)]),
                device("通用蓝牙耳机", "通用或未识别的耳机", "当前默认输出为蓝牙耳机，或蓝牙设备型号未知。", .bluetooth(.headphones)),
                device("入耳式耳机", "蓝牙 · 默认输出", "预览通用真无线、入耳式、无柄式与骨传导耳机图标。", .bluetooth(.earbuds),
                       families: [("通用真无线", .earbuds), ("通用入耳式", .inEar),
                                  ("通用无柄式", .stemless), ("通用骨传导", .boneConduction)]),
                device("蓝牙音箱", "蓝牙 · 默认输出", "当前默认输出被识别为蓝牙音箱。", .bluetooth(.speaker)),
                device("车载音频", "蓝牙 · 默认输出", "当前默认输出被识别为蓝牙车载音频。", .bluetooth(.car)),
                device("助听设备", "蓝牙 · 默认输出", "当前默认输出被识别为蓝牙助听设备。", .bluetooth(.hearingAid)),
                device("Apple TV", "AirPlay · 默认输出", "当前默认 AirPlay 输出为 Apple TV。", .airPlay(.appleTV)),
                device("HomePod", "AirPlay · 默认输出", "当前默认 AirPlay 输出为 HomePod。", .airPlay(.homePod)),
                device("HomePod mini", "AirPlay · 默认输出", "当前默认 AirPlay 输出为 HomePod mini。", .airPlay(.homePodMini)),
                device("通用 AirPlay", "其他或未识别的接收端", "当前默认输出为第三方或型号未知的 AirPlay 设备。", .airPlay(.other))
            ].flatMap { $0 }
        case .power:
            var charging = scene("充电", "正在充电", "正在充电时始终显示绿色电量弧和闪电。") { $0.charging = true; $0.plugged = true }
            let levels: [(String, Double?, String)] = [
                ("正常 50%", 0.5, "正在充电；绿色电量弧，右上角显示闪电。"),
                ("低电量 12%", 0.12, "低电量充电中；电量弧仍为绿色，并显示闪电。"),
                ("0%", 0, "电量为 0% 且正在充电；保留绿色底轨与闪电。"),
                ("100%", 1, "电量为 100% 且仍在充电；显示绿色满弧与闪电。"),
                ("未知", nil, "正在充电但电量未知；保留绿色底轨与闪电。")
            ]
            charging.variants = levels.map { title, level, description in
                    var snapshot = charging.variants[0].snapshot
                    snapshot.battery = level
                    return IconPreviewVariant(titleKey: title, snapshot: snapshot, detailKey: description)
                }
            return [
                scene("正常电量", "未充电 · 示例 50%", "中央显示电量时，外圈与数字对应剩余电量；此处为 50%。") { $0.battery = 0.5 },
                scene("低电量", "未充电 · 低于 20%", "示例电量 12%；未充电时，短红弧与数字共同提示低电量。") { $0.battery = 0.12 },
                scene("0% 空环", "已读到电量 0%", "电量为 0%；外圈保留底轨，中央显示 0。") { $0.battery = 0 },
                scene("100% 满环", "电量达到 100%", "完整电量弧，中央保留三位数 100。") { $0.battery = 1 },
                scene("电量未知", "暂未获取电量", "未获取电量时，保留底轨，中央显示 —。") { $0.battery = nil },
                charging,
                scene("插入电源提示", "刚接入电源", "接入电源时短暂显示插头与勾，随后恢复。此处定格展示提示。") { $0.plugged = true; $0.charging = true; $0.centerEvent = .power },
                scene("拔出电源提示", "刚断开电源", "断开电源时短暂显示插头与叉，随后恢复。此处定格展示提示。") { $0.centerEvent = .power }
            ]
        case .audio:
            var playing = scene("播放音柱", "正在播放且已开启音柱", "媒体正在播放，且已开启播放音柱。") {
                $0.playing = true
                $0.deviceKind = .bluetooth(.airPodsPro)
                $0.audioIconFamily = .airPodsPro2
                $0.output = "AirPods Pro（示例）"
            }
            var reduced = playing.variants[0].snapshot
            reduced.reducedMotion = true
            playing.variants = [IconPreviewVariant(titleKey: "动态", snapshot: playing.variants[0].snapshot, detailKey: "按固定节奏播放，不读取真实声音；系统减少动态效果时自动静止。"),
                                IconPreviewVariant(titleKey: "减少动态效果", snapshot: reduced, detailKey: "保留静态高低音柱，表示正在播放。")]
            var adjusting = scene("调整音量提示", "刚调整系统音量", "调节音量时，中央短暂显示百分比。") { $0.adjusting = true; $0.centerEvent = .volume; $0.volume = 0.75 }
            let normal = adjusting.variants[0].snapshot
            var muted = normal
            muted.volume = 0
            muted.muted = true
            var unknown = normal
            unknown.volume = nil
            adjusting.variants = [IconPreviewVariant(titleKey: "正常 75%", snapshot: normal, detailKey: "中央临时显示音量；播放中也会切回音量点，约 2 秒后恢复。此处定格展示。"),
                                  IconPreviewVariant(titleKey: "静音 / 0%", snapshot: muted, detailKey: "调整到静音或 0 时，中央临时显示 0，底部显示静音符号。此处定格展示。"),
                                  IconPreviewVariant(titleKey: "未知", snapshot: unknown, detailKey: "音量值未知时，中央与底部均显示短横线。此处定格展示提示。")]
            return [
                scene("静音", "系统静音或音量为 0", "系统静音或音量为 0 时，底部显示静音符号。") { $0.muted = true; $0.volume = 0 },
                scene("音量 1 档", "大于 0% 至 25%", "示例音量 25%；底部亮起 1 个圆点。") { $0.volume = 0.25 },
                scene("音量 2 档", "大于 25% 至 50%", "示例音量 50%；底部亮起 2 个圆点。") { $0.volume = 0.5 },
                scene("音量 3 档", "大于 50% 至 75%", "示例音量 75%；底部亮起 3 个圆点。") { $0.volume = 0.75 },
                scene("音量 4 档", "大于 75% 至 100%", "示例音量 100%；底部亮起 4 个圆点。") { $0.volume = 1 },
                scene("由设备控制", "系统音量未知", "系统无法读取音量时，底部显示短横线。") { $0.volume = nil },
                playing, adjusting
            ]
        }
    }

    var note: String {
        switch self {
        case .network: L("有线网络不显示专属图形，中央会显示电量或音频设备。")
        case .devices: L("仅当前默认蓝牙或 AirPlay 输出显示设备图形；有线输出没有专属中央图形。")
        case .power: L("低电量界限为 20%。充电时保留绿色电量弧，插拔电源提示在此定格显示。")
        case .audio: L("暂停后恢复音量圆点或静音符号。播放音柱固定循环，不录音。")
        }
    }
}
