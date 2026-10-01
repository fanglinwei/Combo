import Foundation

@main enum OnboardingCheck {
    static func main() {
        let suite = "onboarding-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        OnboardingState.migrate(defaults)
        assert(defaults.object(forKey: OnboardingState.completedKey) as? Bool == false,
               "A new installation must show the guide")
        defaults.set(true, forKey: "hasOpened")
        OnboardingState.migrate(defaults)
        assert(defaults.bool(forKey: OnboardingState.completedKey) == false,
               "Closing the guide must not count as completion")

        defaults.removeObject(forKey: OnboardingState.completedKey)
        OnboardingState.migrate(defaults)
        assert(defaults.bool(forKey: OnboardingState.completedKey),
               "Existing users must not be sent through first-install setup after updating")
        print("Onboarding first-launch migration and unfinished-guide checks passed")
    }
}
