import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
    func resolved(preferredLanguages: [String]) -> String {
        guard self == .system else { return rawValue }
        for identifier in preferredLanguages {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "zh": return "zh-Hans"
            case "en": return "en"
            default: continue
            }
        }
        return "en"
    }
}

final class Localization: ObservableObject {
    static let shared = Localization()
    static let preferenceKey = "appLanguage"
    @Published private(set) var language: String
    private let defaults: UserDefaults
    private var changes: [AnyCancellable] = []
    var selection: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: Self.preferenceKey); refresh() }
    }
    var bundle: Bundle {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let choice = AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        language = choice.resolved(preferredLanguages: Locale.preferredLanguages)
        for name in [UserDefaults.didChangeNotification, NSLocale.currentLocaleDidChangeNotification] {
            changes.append(NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() })
        }
    }
    func refresh() {
        let resolved = selection.resolved(preferredLanguages: Locale.preferredLanguages)
        if language != resolved { language = resolved }
    }
}

func L(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: Localization.shared.bundle, locale: .autoupdatingCurrent)
}

// Stored messages keep their key and arguments so existing feedback also switches language.
struct LocalizedText: ExpressibleByStringInterpolation {
    typealias StringInterpolation = String.LocalizationValue.StringInterpolation
    private let resolve: () -> String
    init(stringLiteral value: String) { self.init { L(String.LocalizationValue(value)) } }
    init(stringInterpolation: StringInterpolation) {
        let value = String.LocalizationValue(stringInterpolation: stringInterpolation)
        self.init { L(value) }
    }
    init(_ resolve: @escaping () -> String) { self.resolve = resolve }
    var string: String { resolve() }
    var isEmpty: Bool { string.isEmpty }
    static func joined(_ values: [LocalizedText], separator: String) -> LocalizedText {
        LocalizedText { values.map(\.string).joined(separator: separator) }
    }
}

func LKey(_ key: String) -> String { L(String.LocalizationValue(key)) }
