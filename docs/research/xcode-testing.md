# 测试设计与问题记录

当前运行方式、覆盖和隔离约定统一见 [Tests/README.md](../../Tests/README.md)。Swift 检查迁入 Xcode target 及 Swift Testing 的工作已完成；本页只保留选型理由和仍有排查价值的历史问题，不作为本次测试通过凭证。

## 选型理由

- 使用工具链内置的 `Testing`，无需增加 Swift Testing 包依赖。Quick、Nimble 和 SnapshotTesting 不能解决宿主加载问题，未为此引入；也未为迁移额外抽出产品 framework 或改用 SwiftPM。
- 测试框架与运行边界分开：无宿主 target 编译所需生产源码；依赖主 bundle、AppKit 事件循环的案例使用独立 `ComboTestHost`；Objective-C helper 保留独立子进程。
- Swift Testing 默认进程内并行，仍需测试执行进程；换框架不会自动修复宿主启动、动态链接、权限或 helper 生命周期。当前计划关闭并行，集成 suite 另有 `.serialized` 与逐案例状态恢复。`@MainActor` 不保证跨 `await` 独占全局状态。
- 每个案例使用原生断言，必要前提失败即终止当前案例；保留超时、取消、像素基准和失败时的清理，不以包装旧 `main()` 代替逐案例覆盖。

## 可复用的排查结论

2026-10-09 迁移记录中的以下观察已影响当前测试结构；历史结果不代表当前环境再次验证：

| 观察 | 当前处理与结论边界 |
| --- | --- |
| Documents 下的 DerivedData 曾在宿主 dyld `open` 停滞，换系统临时目录后可运行 | 运行器默认使用临时目录；权限或文件系统根因未证实，不能归为测试框架缺陷 |
| 状态栏刚创建时高度为 0，或 screen 尚未落到最终显示器，曾使重开位置偏移 1920px | fixture 完成 AppKit 启动并等待尺寸和 screen 就绪；保留 2 秒截止与位置断言，不据此宣称所有面板偶发问题已修复 |
| 真实位置授权回调、工作区通知和全局鼠标输入会污染模拟状态或关闭测试面板 | 使用无系统监听的 Store、禁用授权回调、独立通知中心与关闭全局鼠标监听；生产默认行为保持开启 |
| AppKit 不会用 `servicesMenu = nil` 清除已建立菜单 | scope 在首次无 Services 菜单时建立可恢复的空菜单基线，并恢复原对象、标题和挂接位置 |
| Display P3 位图分量直接当作 calibrated RGB 会误判颜色 | 保留位图颜色配置并转到 sRGB；布局与像素检查不等于完整辅助功能树验收 |

## 待复核的历史问题

- PanelDismiss 曾出现详情收缩高度、打开可见性失败；PanelMotion 的首次高度和 AirPlayRoute 的替换请求也曾各失败后单独复测通过。记录未确认这些偶发失败的根因，不能把复测通过当作修复。定位线索为 `build/stage2-verify.log`、`build/stage4-verify-final.log` 和 `build/swift-testing-closeout/`；这些是本机历史产物路径，不保证新 checkout 中存在。
- SwiftUI 应用入口迁移时，锁屏会话中 PanelDismiss/PanelMotion 失败；迁移前临时副本同样失败。解锁后的前台动画验收当时仍待完成，历史完整 suite 不能记为通过；记录位于 `build/checks/swiftui-migration/`。

本次仅收敛既有记录，未重新复现上述问题。后续用当前源码、正常桌面和新结果包裁决，不沿用迁移批次的案例数、旧成功摘要或已删除功能的覆盖。

## 官方依据

- [Swift Testing 与内置版本](https://github.com/swiftlang/swift-testing/blob/main/Documentation/Distributions.md)、[Apple Testing](https://developer.apple.com/documentation/Testing)
- [并行与串行](https://developer.apple.com/documentation/testing/parallelization)、[WWDC24：Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195/)
- [TestScoping](https://developer.apple.com/documentation/testing/testscoping)、[Xcode build settings](https://developer.apple.com/documentation/xcode/build-settings-reference)
