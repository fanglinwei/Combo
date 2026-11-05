import Foundation

enum OnboardingState {
    static let completedKey = "onboardingCompleted"

    static func showsGuide(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: completedKey)
    }
}
