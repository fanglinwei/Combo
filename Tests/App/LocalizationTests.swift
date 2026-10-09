import Testing
import Foundation
@testable import ComboTestHost

extension IntegrationTests {
    struct LocalizationTests {
        @Test
        @MainActor
        func testLanguageMatching() throws {
            #expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-Hans-CN", "en-US"]) == "zh-Hans")
            #expect(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-CN"]) == "en")
            for language in ["zh-Hant-TW", "zh-HK", "zh", "zh-Hans"] {
                #expect(AppLanguage.system.resolved(preferredLanguages: [language]) == "zh-Hans")
            }
            #expect(AppLanguage.system.resolved(preferredLanguages: ["ja-JP", "fr-FR"]) == "en")
            #expect(AppLanguage.system.resolved(preferredLanguages: []) == "en")
            #expect(AppLanguage.english.resolved(preferredLanguages: ["zh-CN"]) == "en")
            #expect(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en-US"]) == "zh-Hans")
        }

        @Test
        @MainActor
        func testPreferencePersistenceAndFallback() throws {
            let suite = "Combo.LocalizationCheck.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preference = Localization(defaults: defaults)
            #expect(preference.selection == .system)
            preference.selection = .english
            #expect(Localization(defaults: defaults).selection == .english)
            preference.selection = .simplifiedChinese
            #expect(preference.language == "zh-Hans")
            defaults.set("unsupported", forKey: Localization.preferenceKey)
            preference.refresh()
            #expect(preference.selection == .system)
        }

        @Test
        @MainActor
        func testLiveMessagesInterpolationAndRegion() throws {
            let shared = Localization.shared
            shared.selection = .simplifiedChinese
            let name = "电池 %@ 100%"
            let message: LocalizedText = "正在连接 \(name)…"
            let device: LocalizedText = "\(name)"
            let number = 80
            let battery: LocalizedText = "电量 \(number)%"
            #expect(message.string == "正在连接 电池 %@ 100%…")
            #expect(battery.string == "电量 80%")
            #expect(L("设置…") == "设置…")
            // Existing settings feedback must resolve again after a language change.
            let loginFeedback: LocalizedText = "请在系统设置的登录项中允许 Combo。"
            let settingsErrors: [String: LocalizedText] = [
                "wifi": "无法打开系统设置，请手动进入对应页面。",
                "menu": "无法打开菜单栏设置，请手动进入系统设置。",
                "sound": "无法打开系统声音设置，请手动进入系统设置。"
            ]
            #expect(loginFeedback.string == "请在系统设置的登录项中允许 Combo。")
            #expect(settingsErrors["wifi"]?.string == "无法打开系统设置，请手动进入对应页面。")
            let region = Locale.autoupdatingCurrent.identifier
            shared.selection = .english
            #expect(L("设置…") == "Settings…")
            #expect(loginFeedback.string == "Allow Combo in Login Items in System Settings.")
            #expect(settingsErrors["wifi"]?.string == "Could not open System Settings. Navigate to the relevant page manually.")
            #expect(settingsErrors["menu"]?.string == "Could not open Menu Bar Settings. Open System Settings manually.")
            #expect(settingsErrors["sound"]?.string == "Could not open System Sound Settings. Open System Settings manually.")
            #expect(message.string == "Connecting to 电池 %@ 100%…")
            #expect(battery.string == "Battery 80%")
            #expect(device.string == name, "External names must stay verbatim even when they match a translation key")
            let parts: [LocalizedText] = [message, battery]
            let combined = LocalizedText.joined(parts, separator: "\n")
            #expect(combined.string == "Connecting to 电池 %@ 100%…\nBattery 80%")
            shared.selection = .simplifiedChinese
            #expect(combined.string == "正在连接 电池 %@ 100%…\n电量 80%")
            #expect(loginFeedback.string == "请在系统设置的登录项中允许 Combo。")
            #expect(settingsErrors["menu"]?.string == "无法打开菜单栏设置，请手动进入系统设置。")
            #expect(settingsErrors["sound"]?.string == "无法打开系统声音设置，请手动进入系统设置。")
            #expect(Locale.autoupdatingCurrent.identifier == region, "Language changes must preserve the system region")
        }

        @Test
        @MainActor
        func testBilingualResourcesAndPermissionDescriptions() throws {
            func strings(_ language: String, table: String) throws -> [String: String] {
                let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
                let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent(table + ".strings"))
                return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            }
            let chinese = try strings("zh-Hans", table: "Localizable")
            let english = try strings("en", table: "Localizable")
            #expect(chinese.count > 450 && Set(chinese.keys) == Set(english.keys))
            // 中文表的值约定就是 key 本身。漏写中文、把英文值抄进来，都会在这里失败——
            // 只校验英文那一侧是抓不到这种错的（key 集合仍然是齐的）。
            for (key, value) in chinese where key.contains(where: { "\u{3400}"..."\u{9fff}" ~= String($0) }) {
                #expect(value.contains(where: { "\u{3400}"..."\u{9fff}" ~= String($0) }), "Untranslated Chinese entry: \(key) → \(value)")
            }
            let placeholders = try NSRegularExpression(pattern: "%(@|lld|d|%)")
            func formats(_ text: String) -> [String] {
                placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .map { (text as NSString).substring(with: $0.range) }
            }
            for (key, value) in english {
                #expect(!value.isEmpty && formats(key) == formats(value), "Invalid placeholders for \(key)")
                #expect(!value.contains(where: { "\u{3400}"..."\u{9fff}" ~= String($0) }), "Untranslated English entry: \(key)")
                let englishPath = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
                let englishBundle = try #require(Bundle(path: englishPath))
                let resolved = String(localized: String.LocalizationValue(key), bundle: englishBundle)
                if formats(key).isEmpty { #expect(resolved == value, "Unresolvable translation: \(key)") }
            }
            for language in ["en", "zh-Hans"] {
                let info = try strings(language, table: "InfoPlist")
                #expect(Set(info.keys) == ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription", "NSBluetoothAlwaysUsageDescription", "NSLocalNetworkUsageDescription"])
            }
        }
    }
}
