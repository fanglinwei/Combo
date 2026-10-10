# 应用入口与窗口生命周期

Combo 使用现有 Xcode App target，最低 macOS 26；[ComboApp.swift](../../Combo/App/ComboApp.swift) 通过 `@main struct ComboApp: App` 声明入口。业务枚举也叫 Scene，因此入口明确使用 `some SwiftUI.Scene`。

## 状态与职责

- `@NSApplicationDelegateAdaptor` 创建唯一 [AppDelegate](../../Combo/App/AppDelegate.swift)，沿用它持有的 Store；启动、系统监听、更新驱动和退出清理继续使用现有路径。
- SwiftUI `Settings` Scene 创建唯一设置窗口，复用 SettingsView；[ComboCommands](../../Combo/App/ComboCommands.swift) 声明关于、设置、更新、隐藏和退出命令，保留快捷键及更新可用性。原生 Services 菜单沿用系统对象，只同步标题语言。
- 菜单栏继续使用 NSStatusItem；总览、详情和引导指针继续使用 AppKit 面板，保留定位、非激活、开合动画和外部点击关闭行为。

## 设置窗口桥接

Scene 安装公开的 `openSettings` 动作，启动阶段的设置请求会等待动作就绪。主菜单、面板按钮、首次引导、`--settings` 和应用重新打开均使用同一条路径。

窗口 reader 在 SwiftUI 视图附着到 NSWindow 后设置外观、标题、可最小化属性、尺寸和引导层级。保留 SwiftUI 的 window delegate，通过关闭通知恢复 accessory 激活策略、结束演示及清理菜单权限界面。退出时取消通知和打开动作。

初始窗口 frame 保持 850 × 690，最小 frame 保持 780 × 620。SwiftUI 根据内容计算最小尺寸，因此 reader 在原生标题栏就绪后测量 contentLayoutRect，换算内容约束并重新应用引导尺寸；不硬编码标题栏高度。引导仍压缩到 620 高，并在结束后恢复设置 frame。

## 测试边界

[Tests/Support/TestHostApp.swift](../../Tests/Support/TestHostApp.swift) 是独立 AppKit 入口，只进入事件循环，不自动创建产品 AppDelegate / Store。宿主共享生产控制器和页面，通过 `COMBO_TEST_HOST` 提供测试用菜单和窗口，不注册产品 Scene。

`./verify.sh` 运行现有自动回归。真实 SwiftUI 入口、命令、首次引导及窗口行为用隔离启动工具单独验证，命令和范围见 [Tests/README.md](../../Tests/README.md#swiftui-app-入口检查)。实机授权、硬件控制和更新安装仍需各自验收。
