import Foundation

enum OnboardingState {
    static let completedKey = "onboardingCompleted"
    /// 用户点过“稍后再说”。不算完成，但也不在下次启动时再次打断。
    static let postponedKey = "onboardingPostponed"
    /// 停在哪一步，重新打开引导时从这里继续。
    static let stepKey = "onboardingStep"
    /// 引导内容有 3 步；完成页是第 4 屏（step == stepCount），不计入步数。
    static let stepCount = 3

    static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: completedKey) == nil else { return }
        defaults.set(defaults.bool(forKey: "hasOpened"), forKey: completedKey)
    }

    /// 首次启动显示引导的条件：既没完成，也没被旧版“稍后再说”放行。
    static func showsGuide(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: completedKey) && !defaults.bool(forKey: postponedKey)
    }
}
