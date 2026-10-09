import Testing
import Foundation

struct OnboardingTests {
    @Test
    @MainActor
    func testFirstLaunchMigrationAndPostponement() async throws {
        let suite = "onboarding-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        OnboardingState.migrate(defaults)
        #expect(defaults.object(forKey: OnboardingState.completedKey) as? Bool == false,
               "A new installation must show the guide")
        defaults.set(true, forKey: "hasOpened")
        OnboardingState.migrate(defaults)
        #expect(defaults.bool(forKey: OnboardingState.completedKey) == false,
               "Closing the guide must not count as completion")

        defaults.removeObject(forKey: OnboardingState.completedKey)
        OnboardingState.migrate(defaults)
        #expect(defaults.bool(forKey: OnboardingState.completedKey),
               "Existing users must not be sent through first-install setup after updating")

        // 稍后再说只是放行本次启动：不算完成，也不在下次启动时再次打断。
        defaults.set(false, forKey: OnboardingState.completedKey)
        defaults.removeObject(forKey: OnboardingState.postponedKey)
        #expect(OnboardingState.showsGuide(defaults), "A new installation must show the guide")
        defaults.set(true, forKey: OnboardingState.postponedKey)
        #expect(!OnboardingState.showsGuide(defaults), "Postponing must not prompt again on launch")
        defaults.set(false, forKey: OnboardingState.postponedKey)
        defaults.set(true, forKey: OnboardingState.completedKey)
        #expect(!OnboardingState.showsGuide(defaults), "A finished guide must not reappear on launch")
    }
}
