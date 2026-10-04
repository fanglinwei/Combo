import Foundation
import Combine

@main struct LocalizationCheck {
    static func main() throws {
        assert(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-Hans-CN", "en-US"]) == "zh-Hans")
        assert(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-CN"]) == "en")
        for language in ["zh-Hant-TW", "zh-HK", "zh", "zh-Hans"] {
            assert(AppLanguage.system.resolved(preferredLanguages: [language]) == "zh-Hans")
        }
        assert(AppLanguage.system.resolved(preferredLanguages: ["ja-JP", "fr-FR"]) == "en")
        assert(AppLanguage.system.resolved(preferredLanguages: []) == "en")
        assert(AppLanguage.english.resolved(preferredLanguages: ["zh-CN"]) == "en")
        assert(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en-US"]) == "zh-Hans")

        let suite = "Combo.LocalizationCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = Localization(defaults: defaults)
        assert(preference.selection == .system)
        preference.selection = .english
        assert(Localization(defaults: defaults).selection == .english)
        preference.selection = .simplifiedChinese
        assert(preference.language == "zh-Hans")
        defaults.set("unsupported", forKey: Localization.preferenceKey)
        preference.refresh()
        assert(preference.selection == .system)

        // This executable runs in its own test bundle; never change Combo's preferences.
        let shared = Localization.shared
        defer { UserDefaults.standard.removeObject(forKey: Localization.preferenceKey) }
        shared.selection = .simplifiedChinese
        let name = "电池 %@ 100%"
        let message: LocalizedText = "正在连接 \(name)…"
        let device: LocalizedText = "\(name)"
        let number = 80
        let battery: LocalizedText = "电量 \(number)%"
        assert(message.string == "正在连接 电池 %@ 100%…")
        assert(battery.string == "电量 80%")
        assert(L("设置…") == "设置…")
        // Existing settings feedback must resolve again after a language change.
        let loginFeedback: LocalizedText = "请在系统设置的登录项中允许 Combo。"
        let settingsErrors: [String: LocalizedText] = [
            "wifi": "无法打开系统设置，请手动进入对应页面。",
            "menu": "无法打开菜单栏设置，请手动进入系统设置。",
            "sound": "无法打开系统声音设置，请手动进入系统设置。"
        ]
        assert(loginFeedback.string == "请在系统设置的登录项中允许 Combo。")
        assert(settingsErrors["wifi"]?.string == "无法打开系统设置，请手动进入对应页面。")
        let region = Locale.autoupdatingCurrent.identifier
        shared.selection = .english
        assert(L("设置…") == "Settings…")
        assert(loginFeedback.string == "Allow Combo in Login Items in System Settings.")
        assert(settingsErrors["wifi"]?.string == "Could not open System Settings. Navigate to the relevant page manually.")
        assert(settingsErrors["menu"]?.string == "Could not open Menu Bar Settings. Open System Settings manually.")
        assert(settingsErrors["sound"]?.string == "Could not open System Sound Settings. Open System Settings manually.")
        assert(message.string == "Connecting to 电池 %@ 100%…")
        assert(battery.string == "Battery 80%")
        assert(device.string == name, "External names must stay verbatim even when they match a translation key")
        let parts: [LocalizedText] = [message, battery]
        let combined = LocalizedText.joined(parts, separator: "\n")
        assert(combined.string == "Connecting to 电池 %@ 100%…\nBattery 80%")
        shared.selection = .simplifiedChinese
        assert(combined.string == "正在连接 电池 %@ 100%…\n电量 80%")
        assert(loginFeedback.string == "请在系统设置的登录项中允许 Combo。")
        assert(settingsErrors["menu"]?.string == "无法打开菜单栏设置，请手动进入系统设置。")
        assert(settingsErrors["sound"]?.string == "无法打开系统声音设置，请手动进入系统设置。")
        assert(Locale.autoupdatingCurrent.identifier == region, "Language changes must preserve the system region")

        func strings(_ language: String, table: String) throws -> [String: String] {
            let path = Bundle.main.path(forResource: language, ofType: "lproj")!
            let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent(table + ".strings"))
            return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        }
        let chinese = try strings("zh-Hans", table: "Localizable")
        let english = try strings("en", table: "Localizable")
        assert(chinese.count > 450 && Set(chinese.keys) == Set(english.keys))
        // 中文表的值约定就是 key 本身。漏写中文、把英文值抄进来，都会在这里失败——
        // 只校验英文那一侧是抓不到这种错的（key 集合仍然是齐的）。
        for (key, value) in chinese where key.contains(where: { "\u{3400}"..."\u{9fff}" ~= String($0) }) {
            assert(value.contains(where: { "\u{3400}"..."\u{9fff}" ~= String($0) }), "Untranslated Chinese entry: \(key) → \(value)")
        }
        let placeholders = try NSRegularExpression(pattern: "%(@|lld|d|%)")
        func formats(_ text: String) -> [String] {
            placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }
        }
        for (key, value) in english {
            assert(!value.isEmpty && formats(key) == formats(value), "Invalid placeholders for \(key)")
            assert(!value.contains(where: { "\u{3400}"..."\u{9fff}" ~= String($0) }), "Untranslated English entry: \(key)")
            let resolved = String(localized: String.LocalizationValue(key), bundle: Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)!)
            if formats(key).isEmpty { assert(resolved == value, "Unresolvable translation: \(key)") }
        }
        for language in ["en", "zh-Hans"] {
            let info = try strings(language, table: "InfoPlist")
            assert(Set(info.keys) == ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription", "NSBluetoothAlwaysUsageDescription", "NSLocalNetworkUsageDescription"])
        }
        print("PASS: language matching, persistence, invalid preference fallback, live messages and stored settings feedback, verbatim names, interpolation, unchanged region, \(english.count) bilingual entries and permission descriptions")
    }
}
