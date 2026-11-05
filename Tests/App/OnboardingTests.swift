import Testing
import Foundation

struct OnboardingTests {
    @Test
    @MainActor
    func testFirstLaunchAndCompletion() throws {
        let suite = "onboarding-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(OnboardingState.showsGuide(defaults), "A fresh installation must show the welcome page")
        #expect(defaults.object(forKey: OnboardingState.completedKey) == nil,
               "Reading launch state must not mark the welcome page complete")
        defaults.set(true, forKey: OnboardingState.completedKey)
        #expect(!OnboardingState.showsGuide(defaults), "Starting use must suppress the welcome page on later launches")
    }
}
