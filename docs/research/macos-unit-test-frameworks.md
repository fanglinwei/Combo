# macOS 单元测试框架与进程启动问题调研

调研日期：2026-10-09。范围：GitHub 项目及 Apple、Swift 项目的官方资料；不修改测试实现或 Xcode 配置。

## 结论

最值得评估的是官方开源的 **Swift Testing**，使用 Xcode / Swift 工具链内置的 `Testing` 模块，搭配现有无宿主测试 target 或 SwiftPM 的 `swift test`。它支持进程内并行测试，可以解决为了并行 XCTest 而启动多个测试进程的问题。不过，“不用主 App 当宿主”由测试 target 和 runner 决定；替换断言框架不会自动修复宿主启动、动态链接、权限或业务代码自身启动 helper 的问题。

Apple 官方明确区分：Swift Testing 默认并行运行测试，XCTest 的并行化使用多个进程，每个进程一次执行一个测试。[WWDC24：Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195/)。Swift Testing 的官方框架说明也明确列出进程内并行执行能力。[Apple Swift Testing](https://developer.apple.com/documentation/Testing)

“进程内并行”并不表示整个测试命令零进程：仍然需要一个执行测试代码的进程，CLI、编译器或运行器也可能有自己的子进程。它避免的是依靠多个 XCTest worker 达成并行执行。

串行 XCTest 也不是每个测试必然启动一个进程；不能把框架并行机制与每个用例的进程生命周期等同。Swift Testing 的 exit testing 专门在子进程中验证退出行为，因此同样不能承诺零子进程。[Swift Testing exit testing](https://docs.swift.org/latest/documentation/testing/exit-testing/)

## GitHub 候选比较

| 候选 | 适用价值 | 能否解决此处进程问题 | 建议 |
| --- | --- | --- | --- |
| [swiftlang/swift-testing](https://github.com/swiftlang/swift-testing) | 官方 Swift 单元测试；`@Test`、`#expect`、参数化、async/await、进程内并行 | 可以替代 XCTest 的多进程并行模式；无宿主还需要 target / runner 配置 | 首选评估，逐步迁移纯逻辑测试 |
| [Quick/Quick](https://github.com/Quick/Quick) | BDD 的 `describe / context / it` 组织语法 | 已有 `QuickSpec` 实现依赖 XCTest；更换语法无法改变宿主加载链路 | 不为解决本问题引入 |
| [Quick/Nimble](https://github.com/Quick/Nimble) | 更丰富的 matcher、异步 polling；可搭配 XCTest 或 Swift Testing | 断言层，不负责启动、链接或管理测试宿主 | 只有确实需要 matcher 时再考虑 |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 图像、文本、数据快照；支持 macOS 与 Swift Testing | 快照断言库，不负责 runner；UI 渲染仍有运行环境要求 | 适合未来视图回归测试，与当前启动问题独立 |
| [swiftlang/swift-package-manager](https://github.com/swiftlang/swift-package-manager) 的 `swift test` | 官方 CLI 构建与运行 Swift package 测试，支持 XCTest 与 Swift Testing | 可以让模块测试脱离 App host 和 Xcode 工程测试宿主链路；仍要启动测试执行进程 | 纯逻辑模块的备选运行路径 |

Quick 的当前源码直接 `import XCTest`，`QuickSpec` 的 SwiftPM fallback 基类为 `XCTestCase`，macOS 路径也使用 XCTest 的 suite 和 Objective-C 测试发现机制。[QuickSpec 源码](https://github.com/Quick/Quick/blob/main/Sources/Quick/QuickSpec.swift)

Nimble 的官方 v13.5.0 发布说明列出基础 Swift Testing 支持；当前 releases 页显示 v14.0.0，并说明改进了 polling 在高负载、并行环境中的可靠性。这说明它可以和 Swift Testing 配合，但不能把 matcher 能力当作独立 runner。[Nimble releases](https://github.com/Quick/Nimble/releases)

SnapshotTesting README 给出 `import Testing` / `@Test` 示例，并列出 macOS 平台支持；发布页当前显示 1.19.6。它解决快照回归比较，与宿主启动无直接关系。[SnapshotTesting README](https://github.com/pointfreeco/swift-snapshot-testing)、[releases](https://github.com/pointfreeco/swift-snapshot-testing/releases)

## Swift Testing 使用条件与边界

Swift Testing 从 Swift 6.0 工具链、Xcode 16.0 和对应 Command Line Tools 起内置。官方推荐使用内置版本，普通项目无需在 `Package.swift` 加上 `swift-testing` 包依赖；源码包会增加 runtime、宏和 SwiftSyntax 的构建成本，还可能带来工具集成或混用版本的问题。[Obtaining Swift Testing](https://github.com/swiftlang/swift-testing/blob/main/Documentation/Distributions.md)

它支持 Apple 平台，能够与已有 XCTest 测试并存，可以逐个文件迁移，不需要一次重写测试体系。仓库的 `main` 分支可能需要开发版工具链，因此“工具链内置模块可用”和“拉取 main 源码能构建”是不同条件。[Swift Testing README](https://github.com/swiftlang/swift-testing/blob/main/README.md)

UI 自动化与性能测试仍需要分别检查需求。Apple 建议新单元测试使用 Swift Testing，同时保留 XCTest / XCUIAutomation 进行应用 UI 自动化。[Apple testing overview](https://developer.apple.com/documentation/xcode/testing)、[XCTest](https://developer.apple.com/documentation/XCTest)

SwiftPM 的官方 `swift test` 文档提供 `--enable/disable-xctest`、`--enable/disable-swift-testing`、`--parallel/--no-parallel` 等控制选项。具体可用参数应以项目安装工具链的 `swift test --help` 为准；`main` 文档不是项目本地版本保证。[SwiftTest 官方文档](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftTest.md)

## Combo 当前情况与选择

以下是本次读取项目配置与已有文档得到的观察，不是本次运行测试后的结果：

- `ComboTests` 已经是无宿主测试：`TEST_HOST` / `BUNDLE_LOADER` 为空。
- `ComboIntegrationTests` 使用独立 `ComboTestHost`，通过 `COMBO_TEST_HOST` 进入 `NSApplication` 事件循环，不走主 App 的 AppDelegate。
- 测试计划关闭并行；验证脚本也使用 `-parallel-testing-enabled NO`。因此现有问题不能直接归因于 XCTest 并行 worker。
- 已有调研记录显示：DerivedData 放在 Documents 下时，测试宿主曾停在 dyld 的 `open`；改到 `TMPDIR` 后成功。权限或文件系统机制尚未被证实，不能将其描述为已经确定的 XCTest 缺陷。

本地证据：[Tests README](../../Tests/README.md)、[Xcode 测试问题记录](./xcode-testing.md)、[测试 target 配置](../../Combo.xcodeproj/project.pbxproj)、[宿主入口](../../Tests/Support/TestHostApp.swift)、[测试计划](../../Tests/ComboTests.xctestplan)、[验证脚本](../../verify.sh)。

基于这些观察，最小完整方案是保留无宿主 XCTest 和轻量集成宿主，优先确认当前启动问题是否已经由临时目录构建路径解决。需要减少测试运行链路时，可选择少量没有全局系统副作用的纯逻辑模块试用 SwiftPM + 内置 Swift Testing，并比较冷启动、增量构建和测试执行耗时；在有真实结果前，不建议整体迁移。

真实 XPC、权限、蓝牙、音频、网络及 helper 进程测试，应保留集成边界。Swift Testing 默认并行可能让共享全局状态或系统状态的测试互相影响；迁移时应审查隔离与串行策略，不能直接打开全局并行。

## 本次未做

未新增依赖、迁移 XCTest、修改工程或执行 Git 写操作；未做性能基准或复现 dyld 卡住。框架选择结论来自官方资料，Combo 启动问题的根因仍需本地复现与采样证据。
