import Foundation

enum OnboardingState {
    static let completedKey = "onboardingCompleted"

    static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: completedKey) == nil else { return }
        defaults.set(defaults.bool(forKey: "hasOpened"), forKey: completedKey)
    }
}
