# 测试与检查入口

在仓库根目录运行 `./verify.sh`：构建应用，运行共享 `ComboTests` scheme 的 99 个测试用例（全部使用 Swift Testing；61 个无宿主案例、38 个隔离宿主案例）和仍保留的 2 个独立自动检查入口，再验证签名和品牌资源。测试按功能模块分类，产物输出到 `build/checks/`。

```sh
./verify.sh
# 当前无 Developer ID 的本地构建使用明确的 ad-hoc 覆盖：
./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

当前迁移状态：**原计划中可直接迁移的 Swift 检查已完成迁移**。26 个测试文件共 99 个案例全部注册到共享 scheme 的两个 target，测试源码及 fixture 中没有遗留 XCTest 案例。原 Swift 自动入口、图标 / 设置预览工具中的可自动化断言，以及 LiveState 的阈值通知、模拟音量提示和菜单权限控制器检查都已有对应 Swift Testing 覆盖。

后续按既定边界保留独立入口：LiveState 的 10 处断言验证真实启动、系统监测、设备和能耗状态；真实 AirPods、媒体观察、线上清单和安装工具继续按需执行；充电 helper 产物、本地化扫描、签名和品牌检查继续由 verify.sh 调用；两组共 14 个 Python 发布案例保留 unittest。两个 Objective-C helper 已由 Swift Testing 案例协调执行，继续保留子进程隔离。下一阶段为维护与验收，不再按旧的迁移批次表重复新增框架迁移案例。

## 自动回归

| 模块 | 覆盖内容 | 文件 |
| --- | --- | --- |
| App | 状态规则、更新状态、应用菜单、本地化、引导状态和品牌资源 | [StateTests.swift](App/StateTests.swift), [AppUpdaterTests.swift](App/AppUpdaterTests.swift), [ApplicationMenuTests.swift](App/ApplicationMenuTests.swift), [LocalizationTests.swift](App/LocalizationTests.swift), [StoreIsolationTests.swift](App/StoreIsolationTests.swift), [OnboardingTests.swift](App/OnboardingTests.swift), [check-brand.sh](App/check-brand.sh) |
| Audio | 默认输出、AirPods、AirPlay 路由与发现、媒体及 helper | [AirPlayDiscoveryTests.swift](Audio/AirPlayDiscoveryTests.swift), [HelperProcessTests.swift](Audio/HelperProcessTests.swift), [AirPlayHelperCheck.m](Audio/AirPlayHelperCheck.m), [AirPlayRouteTests.swift](Audio/AirPlayRouteTests.swift), [AirPodsTests.swift](Audio/AirPodsTests.swift), [MediaPlaybackTests.swift](Audio/MediaPlaybackTests.swift), [MediaPlaybackHelperCheck.m](Audio/MediaPlaybackHelperCheck.m), [OutputDeviceTests.swift](Audio/OutputDeviceTests.swift) |
| Battery | 临时充满和高耗能应用 | [ChargeControlTests.swift](Battery/ChargeControlTests.swift), [EnergyAppsTests.swift](Battery/EnergyAppsTests.swift), [ChargeHelperCheck.swift](Tools/ChargeHelperCheck.swift) |
| Network | Wi-Fi 与个人热点 | [HotspotControlTests.swift](Network/HotspotControlTests.swift), [WiFiControlTests.swift](Network/WiFiControlTests.swift) |
| Rendering | 图标状态／转场与播放音柱 | [IconTransitionTests.swift](Rendering/IconTransitionTests.swift), [MediaBarsTests.swift](Rendering/MediaBarsTests.swift), [IconBoundaryTests.swift](Rendering/IconBoundaryTests.swift) |
| Views | 面板、详情反馈、设置、引导界面及面板本地化 | [DetailFeedbackTests.swift](Views/DetailFeedbackTests.swift), [OnboardingDesignTests.swift](Views/OnboardingDesignTests.swift), [PanelDesignTests.swift](Views/PanelDesignTests.swift), [PanelDismissTests.swift](Views/PanelDismissTests.swift), [PanelLocalizationCheck.py](Views/PanelLocalizationCheck.py), [PanelMotionTests.swift](Views/PanelMotionTests.swift), [SettingsPreferencesTests.swift](Views/SettingsPreferencesTests.swift), [SettingsLayoutTests.swift](Views/SettingsLayoutTests.swift) |

[Fixtures/WiFiReference.png](Fixtures/WiFiReference.png) 是图标检查的像素基准，不是可随意删除的预览图。七批共 24 个原自动检查已由 Xcode 测试 target 承接：22 个 Swift 旧入口已删除，2 个 Objective-C helper 源文件保留并由原生命令行 target 编译，作为独立子进程运行。其余检查继续独立执行，保持原覆盖。RenderIcons 中原有圆头、颜色边界、场景数量和原生尺寸断言也已纳入 IconBoundaryTests，预览图生成保留为工具。

第一批 Swift Testing 试迁移为 [StateTests.swift](App/StateTests.swift)：保留 12 个案例名称、93 处断言、原有输入与调用顺序，以及 MainActor 隔离。迁移按文件推进，两种框架共用现有 target / scheme。单独运行试迁移案例可用 `./Tests/run.sh -only-testing:ComboTests/StateTests`。本批保持既有串行与跨命令排队策略，尚未扩大并发；状态规则原本已无应用宿主，因此框架迁移本身不会进一步减少这组测试的宿主数量。

第二批 Swift Testing 迁移为 [OutputDeviceTests.swift](Audio/OutputDeviceTests.swift)（12 例）、[OnboardingTests.swift](App/OnboardingTests.swift)（1 例）、[MediaPlaybackTests.swift](Audio/MediaPlaybackTests.swift)（3 例）和 [EnergyAppsTests.swift](Battery/EnergyAppsTests.swift)（2 例）。保留 18 个案例名称、109 处条件断言、2 处可选值解包和 9 处失败记录，以及原有 MainActor、随机偏好域、临时 helper、等待截止时间与 defer 清理。没有改变 target、宿主或并发配置；本批结束时，无宿主 bundle 包含 30 个 Swift Testing 和 31 个 XCTest 案例。

本批迁移前后的 18 例均通过；临时注入条件错误、空可选值和 helper 状态错误后，`#expect`、`#require` 与 `Issue.record` 均正确报告源码位置，命令返回 65，注入随后恢复。最终 `./Tests/run.sh -only-testing:ComboTests` 通过全部 61 例（31 个 XCTest + 30 个 Swift Testing），过程未观察到 ComboTestHost。记录在 `build/swift-testing-phase2/`。未重跑 33 个宿主案例或完整 `verify.sh`，没有扩大并发或验证真实性能收益。

第三批 Swift Testing 迁移为 [WiFiControlTests.swift](Network/WiFiControlTests.swift)（2 例）、[HotspotControlTests.swift](Network/HotspotControlTests.swift)（1 例）、[AirPlayDiscoveryTests.swift](Audio/AirPlayDiscoveryTests.swift)（1 例）、[AirPlayRouteTests.swift](Audio/AirPlayRouteTests.swift)（1 例）、[AirPodsTests.swift](Audio/AirPodsTests.swift)（4 例）、[ChargeControlTests.swift](Battery/ChargeControlTests.swift)（5 例）及 [AppUpdaterTests.swift](App/AppUpdaterTests.swift)（1 例）。保留 15 个案例名称、154 处条件断言、13 处可选值解包、4 处失败记录，以及原有异步等待、MainActor、随机偏好 / 凭据账户、临时 helper 和清理路径。现有 target、串行和跨命令排队配置继续沿用；本批结束时，无宿主 bundle 包含 45 个 Swift Testing 和 16 个 XCTest 案例，当时剩余 XCTest 为图标渲染及原生 helper 附件检查。

本批迁移前后的 15 例均通过，逆向还原框架语法后，7 个文件与迁移前源码完全一致。强制 AirPlay 路由等待超时、让非空 SSID 进入禁用密码回调后，对应两例正确失败并返回 65，另一个 Wi-Fi 案例通过；注入随后恢复。最终 `./Tests/run.sh -only-testing:ComboTests` 通过全部 61 例（16 个 XCTest + 45 个 Swift Testing），每 0.5 秒采样观察到 xctest 进程峰值 1、ComboTestHost 峰值 0。记录在 `build/swift-testing-phase3/`。未重跑 33 个宿主案例或完整 `verify.sh`，尚未扩大并发或验证真实性能收益。

第四批 Swift Testing 迁移为 [IconTransitionTests.swift](Rendering/IconTransitionTests.swift)（11 例）、[IconBoundaryTests.swift](Rendering/IconBoundaryTests.swift)（3 例）和 [HelperProcessTests.swift](Audio/HelperProcessTests.swift)（2 例）。保留 16 个案例名称、157 处条件断言、62 处可选值解包和原 helper 超时失败记录；原像素基准、采样矩阵、容差及 240 帧 GIF 不变。嵌套解包与 mutating 调用按原顺序拆成局部值，避免宏展开限制。图标 suite 保留 class 管理每例产物目录，四个产物案例使用显式 defer 记录附件并清理；helper 用 NSObject 标记类定位测试 bundle，仍保留独立进程和 20 秒上限。PNG、GIF、日志在清理前读取为 Data，通过原生 Attachment.record 保存，读取错误记录为测试失败。本批结束时，无宿主 bundle 的 61 个案例全部使用 Swift Testing，当时 33 个宿主案例继续使用 XCTest；沿用现有 target、串行及跨命令排队配置。

本批迁移前后的 16 例均通过；还原框架语法、顺序局部值和明确的生命周期改动后，三个文件的原测试内容完全一致，WiFiReference.png 的 SHA-256 未变。迁移前后结果包实际导出的 5 张 PNG、1 个 GIF 和 2 份 helper 日志逐字节相同；ImageIO 成功解码全部 PNG 和 GIF 的 240 帧。临时注入缺失基准图和缺失 helper 成功标记后，两例正确失败、其余 14 例通过，命令返回 65；失败案例的已生成 PNG / 日志仍可导出，临时目录和日志已清理，注入随后恢复。最终 `./Tests/run.sh -only-testing:ComboTests` 的结果摘要为 Passed / 61 passed / 0 failed / 0 skipped，8 个附件仍与迁移前一致，每 0.5 秒采样观察到 xctest 峰值 1、ComboTestHost 峰值 0。结果包与日志在 `build/swift-testing-phase4/`；附件核对使用 `xcresulttool export attachments` 的完整导出，`--only-failures` 会过滤正常记录在失败案例中的附件。未重跑 33 个宿主案例或完整 `verify.sh`，尚未扩大并发或验证真实性能收益。

第五批 Swift Testing 迁移开始处理隔离宿主：[LocalizationTests.swift](App/LocalizationTests.swift)（4 例）、[ApplicationMenuTests.swift](App/ApplicationMenuTests.swift)（2 例）、[SettingsPreferencesTests.swift](Views/SettingsPreferencesTests.swift)（3 例）及 [StoreIsolationTests.swift](App/StoreIsolationTests.swift)（原 1 例）。保留原案例名称、95 处条件断言、10 处可选值解包和菜单缺项失败记录，继续使用 MainActor、原有窗口等待及 defer 清理。本地化中嵌套的 bundle 解包按原顺序拆成局部值。四组测试放入共同的 `IntegrationTests` suite，用 `.serialized` 约束这些子 suite 之间的执行；现有两个 target、测试计划、跨命令排队和 ComboTestHost 保持不变。

`IntegrationTestCase.swift` 将原状态保存 / 恢复提取为共用的 `IntegrationTestState`，保留恢复操作及顺序。当时剩余 XCTest 经 setUp / teardown 使用它；Swift Testing 经递归 `IntegrationTestScope` trait 在每例前保存状态，使用 defer 在正常结束、断言失败或抛错后恢复，不在 suite 层另建快照。使用原生 [TestScoping](https://developer.apple.com/documentation/testing/testscoping)，测试体内不混用两套断言。新增 1 例宿主清理回归，分别从删除偏好域后的状态和带哨兵 / 英文偏好的状态开始，在 scope 内改动偏好、语言、菜单标题 / 挂接、图标缓存及激活策略后抛错，检查恢复并确认错误向外传播。Services 基线使用宿主实际注册的菜单；删除偏好域后 Foundation 可能读回空字典，因此比较删除后实际读到的基线。

迁移前的 33 个宿主案例通过；迁移后的 10 例加清理回归共 11 例通过。还原框架语法、suite 包装及顺序局部值后，四个文件的原测试源码完全一致，共用恢复操作也保持原顺序。故意注入翻译错误、菜单缺项及窗口创建后的前提失败时，三例正确失败、其余 8 例通过，命令返回 65；13 次 scope 恢复检查和失败窗口关闭 / 内容释放检查均通过，注入已恢复。撤去注入后完整共享 scheme 的结果摘要为 Passed / 95 passed / 0 failed / 0 skipped，其中 61 个无宿主 Swift Testing、11 个宿主 Swift Testing 和 23 个宿主 XCTest 均通过；每 0.5 秒采样观察到 ComboTestHost 峰值 1、xctest 峰值 1。结果、采样与源码核对脚本保存在 `build/swift-testing-phase5/`。本批未重跑包含签名 / 品牌 / 产物门禁的完整 verify.sh，没有扩大并发或验证性能收益。本批结束时，共享 scheme 包含 95 例：无宿主 61 个 Swift Testing，隔离宿主 11 个 Swift Testing + 23 个 XCTest。当时计划接着迁移详情反馈、渲染附件及共用 PanelTestCase。

第六批 Swift Testing 迁移完成剩余 23 例：[DetailFeedbackTests.swift](Views/DetailFeedbackTests.swift)（3）、[MediaBarsTests.swift](Rendering/MediaBarsTests.swift)（1）、[PanelDesignTests.swift](Views/PanelDesignTests.swift)（4）、[OnboardingDesignTests.swift](Views/OnboardingDesignTests.swift)（3）、[SettingsLayoutTests.swift](Views/SettingsLayoutTests.swift)（2）、[PanelMotionTests.swift](Views/PanelMotionTests.swift)（1）和 [PanelDismissTests.swift](Views/PanelDismissTests.swift)（9）。保留原案例名称、129 处条件断言和 69 处解包，共用面板 fixture 另保留 2 处条件断言 / 4 处前提解包。原有渲染矩阵、像素阈值、动画采样、通知 / 本地事件路径、等待上限和清理操作保持不变；两处嵌套内容视图解包按原顺序拆成局部值。所有宿主测试归入既有 `IntegrationTests` 串行 suite，测试计划和跨命令排队沿用现有配置。

`PanelTestCase` 改为普通 final class 上下文，每个面板案例在准备 delegate 前创建 fixture 并注册 defer，结束或准备失败时调用 cleanUp；先执行应用退出清理、移除状态栏项、关闭本例面板和释放内容，再由外层 `IntegrationTestScope` 恢复全局状态。已无调用者的 XCTest 基类及 import 删除。PNG 与动画轨迹通过原生 Attachment.record 保存，沿用原内容与名称，为图片 / 文本补明确扩展名；原有 attachPNG 方法继续复用。两个 bundle 的 95 个测试方法现在全部使用 Swift Testing，测试源码及 fixture 中不再使用 XCTest 断言或附件 API。

首轮详情反馈、音柱、面板动画与关闭 / 退出 14 例通过。还原框架语法、suite 包装、顺序局部值和明确的生命周期 / 附件替换后，排除新增的退出订阅回归后，七个案例文件及两个 fixture 的原源码均完全一致。故意让音柱在首帧附件之后解包失败、让面板高度断言失败、让设置在首张 PNG 之后抛错时，三例均正确失败并返回 65，已记录的两张 PNG 与动画轨迹仍能导出，窗口 / 内容、面板偏好、工作区观察器和 AppKit 状态恢复检查全部通过。另在状态栏项已创建后故意让 anchor 解包失败，对应单例正确失败并返回 65，准备阶段的清理检查通过。注入全部撤去，记录与核对脚本位于 `build/swift-testing-phase6/`。

首轮完整回归中，本轮迁移的 23 例全部通过，但原 scope 清理回归失败。最小组合（实际引导启动 + scope 清理）再次复现；诊断显示已收到 applicationWillTerminate 的同一个 AppDelegate 仍响应语言变化并重建菜单，因为退出没有取消 languageChange 订阅。原启动案例增加退出后切换语言、经主队列屏障后确认菜单不变的断言：修复前两例失败并返回 65，补上一行 languageChange?.cancel() 后原组合 3 例全部通过。新增断言保留，原菜单 / Services 恢复断言未放宽。首轮失败结果保存在 `build/swift-testing-phase6/full.xcresult`，诊断及 red / green 结果也继续保留。

最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出码 0，应用构建、95 个 Swift Testing（61 无宿主 + 34 宿主）、本地化扫描、打包充电 helper 的只读 status、签名和品牌检查全部通过。实际读取结果摘要为 Passed / 95 passed / 0 failed / 0 skipped，并核对 95 个唯一案例全部 Passed；结果包为 `build/checks/xctest.E1l9CX/ComboTests.xcresult`，日志 / 摘要 / 进程采样保存在 `build/swift-testing-phase6/verify*`。每 0.5 秒采样观察到 ComboTestHost 峰值 1、xctest 峰值 1，结束后没有残留宿主。

上一批完整通过的结果包作为迁移前基线。迁移前后 332 个附件的案例标识（去除新增 suite 前缀）、名称与数量一致，包含 328 张 PNG、1 个 240 帧 GIF、1 份面板轨迹、2 份 helper 日志；213 个附件逐字节相同，其余 119 个截图 / 轨迹的字节不同。所有 PNG 与 GIF 帧通过 ImageIO 解码，原有布局、像素、动画与采样断言通过；完整实时截图 / 时间轨迹不使用固定哈希作为验收条件。附件比较见 `build/swift-testing-phase6/attachment-comparison.json`。原像素基准及产物矩阵保持原样，未验证真实硬件、线上更新或性能收益；历史面板收缩偶发问题的根因仍未确认。

Swift Testing 第七批从按需 LiveState 工具迁出两组确定性检查，在既有 [StoreIsolationTests.swift](App/StoreIsolationTests.swift) 中新增阈值变化通知与音量提示状态 / 续期 / 到期恢复两个 Swift Testing 案例。保留原 10 处条件断言、静音 / 非静音 / 零音量 / 空闲输入和三次 1100ms 等待；Task.sleep 错误向外传播，Store 停止、订阅取消及阈值恢复通过 defer 执行，偏好由既有 IntegrationTestScope 恢复。沿用 Store(monitorsSystem: false)、现有宿主、target、串行 suite 和命令排队入口，不修改生产代码。本批结束时共 97 例：61 个无宿主 + 36 个隔离宿主。

LiveState 删除已迁移的两段检查和 Combine import，其余真实设备、权限、观察器与能耗同值请求保持手动入口。移走音量检查后，充电上限读取不再得到原来的隐含等待，因此改为最多 3 秒的显式等待，保留非 loading 断言及生产读取的 2 秒超时；main 允许抛错，并用 defer 停止 Store。工具仅编译 / 链接验证，没有执行实机操作。

定向运行 StoreIsolationTests 的 4 例通过。临时断开阈值通知回调、删除第二次音量提示续期后，两个新案例分别失败，原有 2 例通过，命令返回 65；额外的 stop 后提示状态清理断言通过。原代码在 finally 恢复，逐项核对确认 10 处原条件和三次等待保留。记录位于 build/swift-testing-phase7/。

最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出 0，构建、全部 97 个 Swift Testing（61 无宿主 + 36 隔离宿主）、本地化扫描、打包充电 helper、签名及品牌检查通过。实际结果摘要为 Passed / 97 passed / 0 failed / 0 skipped，结果包 `build/checks/xctest.gRFICD/ComboTests.xcresult`，日志和三轮结果摘要保存于 `build/swift-testing-phase7/`。LiveState 单独编译 / 链接退出 0，未执行真实硬件、能耗或权限操作。

Swift Testing 第八批将 LiveState 中菜单权限刷新 / 拒绝访问的 3 处原断言迁入既有 StoreIsolationTests 的 1 个案例，并增加隔离 Store 初始状态的 2 处前提检查。沿用 Store(monitorsSystem: false)、MainActor、串行 scope、偏好恢复和 defer 停止；生产源码、target 和宿主配置不变。权限只通过 AXIsProcessTrusted 读取，不调用授权请求或打开系统设置；拒绝分支保留原 if 条件，仅在当前宿主未授权时执行。menu-permission-coverage.txt 附件明确记录执行的分支和指引 / 扫描状态，授权宿主通过时不能据此声称已验证拒绝分支。

LiveState 删除已迁移的控制器检查和 ApplicationServices import，保留真实 Store 启动时 checkingMenus / showMenuPermission 的原断言，以及设备、系统监听、充电状态和能耗同值请求。定向 5 例通过，本机附件确认实际执行拒绝分支。临时在检查后关闭指引并设置 scanning 状态时，新案例报告原两处断言失败，其余 4 例通过，命令返回 65；注入在 finally 撤去。工具单独编译 / 链接通过，未运行实机操作。记录位于 build/swift-testing-phase8/。

最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出 0，应用构建、98 个 Swift Testing（61 无宿主 + 37 隔离宿主）、本地化扫描、打包充电 helper、签名和品牌检查全部通过。实际结果摘要为 Passed / 98 passed / 0 failed / 0 skipped，完整结果包 `build/checks/xctest.86BZqb/ComboTests.xcresult`。单独导出新案例附件确认拒绝分支执行、guidanceVisible=true、scanning=false；每 0.5 秒采样观察到 ComboTestHost 峰值 1、xctest 峰值 1。日志、结果摘要、分支附件和采样位于 `build/swift-testing-phase8/`。没有修改系统授权状态，已授权宿主分支和实际授权弹窗流程未验证。

迁移收尾验收：核对 26 个测试文件与两个 target 的注册，未发现遗留 XCTest 案例；运行器的串行、参数、失败退出码、中断和锁释放检查，以及 14 个 Python 发布案例全部通过。最终完整 verify.sh 退出 0，98 passed / 0 failed / 0 skipped，结果包 build/checks/xctest.xXz8ia/ComboTests.xcresult；ComboTestHost 与 xctest 的采样峰值均为 1。首次完整验收中 PanelMotion 的首次高度和 AirPlayRoute 的替换请求曾各失败一次，单独复测和第二次完整验收通过，但根因未确认，未放宽原检查；详见 [收尾记录](../docs/research/xcode-testing.md)。日志、注册核对和两轮结果保存在 build/swift-testing-closeout/。

## Xcode 单独运行

选择共享 `ComboTests` scheme，按 ⌘U；或在仓库根目录执行：

```sh
./Tests/run.sh
# 只运行指定案例：
./Tests/run.sh -only-testing:ComboIntegrationTests/IntegrationTests/ApplicationMenuTests
```

[run.sh](run.sh) 是命令行测试的共享入口，`verify.sh` 也通过它运行测试。同一用户、同一临时目录下的多个调用通过系统文件锁排队，避免多条 `xcodebuild` 各自启动一个 `ComboTestHost`。进程内串行配置只能约束单条命令，不能防止不同命令重叠。锁在运行器退出时自动释放，失败退出码和测试参数保持原样；可用 `python3 Tests/Tools/TestRunnerCheck.py` 验证入口的并发、失败与中断行为。

设置窗口的 Dock 生命周期检查仍会短暂显示一个宿主图标，以验证打开、最小化、重开与关闭的真实行为。直接运行 `xcodebuild` 或 Xcode 的 ⌘U 不经过此文件锁，避免与命令行检查同时执行。

[ComboTests.xctestplan](ComboTests.xctestplan) 默认串行执行两个测试 bundle。`ComboTests` 无应用宿主，编译所需的 18 个现有生产源码文件，不启动 Combo 的 Store、权限监听或更新流程。Onboarding 使用独立随机偏好域；EnergyApps 沿用临时 helper，保留失败、取消和超时覆盖；OutputDevice 保留系统图标存在性检查。这些 Swift 测试只加入 `ComboTests` target。AppUpdater 链接并随测试 bundle 嵌入 Sparkle，保持禁用真实更新；图标基准 PNG 从测试 bundle 读取，图像与 GIF 保存为结果附件。Network、AirPlay、AirPods 沿用注入和临时 helper；Wi-Fi 凭据持久化仍使用随机测试账户并清理，不连接真实网络。充电的模拟案例使用 Swift Testing，打包 helper 的只读 `--status` 由 `ChargeHelperCheck.swift` 继续独立执行。

`ComboIntegrationTests` 通过独立 `ComboTestHost` 承接本地化 4 例、设置 3 例、详情反馈 3 例、应用菜单 3 例、音柱 1 例、面板设计 4 例、引导设计 3 例、面板动画 1 例、面板关闭与退出清理 9 例、设置布局 2 例及 Store 通知 / 音量提示 / 菜单权限 / 启动隔离 / scope 清理 5 例。宿主编译 35 个共享生产 Swift 文件并复用本地化、权限描述和品牌资源；独立入口 [TestHostApp.swift](Support/TestHostApp.swift) 运行 AppKit 事件循环，不创建产品 AppDelegate / Store。`COMBO_TEST_HOST` 只用于宿主，启用测试用菜单及设置窗口；产品入口 [ComboApp.swift](../Combo/App/ComboApp.swift) 和 SwiftUI commands 不加入宿主。案例使用 `Store(monitorsSystem: false)`，Wi-Fi 替身禁用位置授权回调，避免真实系统变化覆盖测试状态；生产默认行为保持开启。设置案例关闭窗口并释放 SwiftUI 内容，所有 Store 在退出时停止。

[IntegrationTestCase.swift](Support/IntegrationTestCase.swift) 提供 `IntegrationTests` 串行 suite 和逐案例 `IntegrationTestScope` 状态恢复。每例先验证宿主 bundle ID；宿主尚无 Services 菜单时建立原生空菜单基线（AppKit 不支持将它设回 nil），再完整保存并恢复该宿主的偏好域（包括原域不存在的情况）、语言状态、应用激活策略及主菜单 / Services 菜单（包括原标题和原挂接位置）、应用图标与命名图像缓存。独立组件继续使用随机偏好域，不访问真实 Combo 的偏好域。两个 bundle 区分无宿主逻辑和需要主 bundle / AppKit 事件循环的集成行为；仍按目录分类测试，没有逐模块增加 target。

音柱案例保留每轮 6 帧、4 次减弱动态切换的真实渲染采样，将 24 张采样 PNG 保存为结果附件；应用菜单检查通过宿主菜单覆盖共享 action / target、快捷键、Services、更新可用性和最小化窗口重新打开；新增案例覆盖 Scene 动作桥接、保留窗口 delegate、尺寸重用、关闭及退出清理。真实产品 SwiftUI 菜单和入口由下述隔离启动工具单独验证。图标边界检查加入无宿主 bundle，保留原像素阈值和采样坐标。

面板案例保留 60 组封面 / 主题与对比度检查、24 组面板 / 详情渲染、6 套调色板的 4 种行交互状态，以及 AirPods 提前 / 晚到数据的高度变化。引导案例分别验证实际 AppDelegate 启动路径、设置窗口恢复、96 组双语 / 主题 / 外观 / 较窄尺寸渲染和前进 / 返回 / Return / Escape 行为。149 张页面与导航 PNG 保存为结果附件。所有窗口在抛错时也关闭并释放内容；临时 AirPods helper 结束后清理。

AirPods 渲染使用固定输出身份和原临时 helper，不读取真实音频设备；AudioStore 的初始输出身份默认仍为 0。引导启动案例仍调用生产启动方法，Debug 更新驱动保持禁用、Store 不监听系统；结束时显式调用退出清理，移除工作区观察器并停止定时器 / Store。

[PanelTestCase.swift](Support/PanelTestCase.swift) 是每个面板案例独立创建的普通上下文，准备前注册 defer，调用 cleanUp 执行共用窗口 / 退出清理：2 秒内等状态栏尺寸和 screen 就绪；使用不监听系统的 Store 和固定演示数据；每例停止任务、移除状态栏项、关闭本例面板并释放内容。工作区通知通过独立 NotificationCenter 注入，禁用测试进程的全局鼠标监听，避免用户在其他应用的点击 / 切换污染时序。生产默认仍监听真实工作区与全局鼠标。实际本地鼠标 monitor、工作区通知回调与 Escape monitor 的注册 / 移除继续验证，不用直接调用处理器替代这些路径。

动画案例保留 20 次定时高度采样并补充原生 resize 通知记录，验证首次测量、快速反转和减弱动态效果的原等待与容差；帧数据保存为文本附件。关闭案例保留详情增长 / 收缩、超过 5 秒的权限保护、内部点击与外部关闭、应用切换、整组移动，以及 Wi-Fi 表单 Escape 优先级；新增实际应用激活观察器和退出期间任务 / 监听清理的案例。历史详情收缩偶发失败没有确认根因，不将隔离后的测试通过视为产品问题已修复。

设置布局案例覆盖原 RenderSettings 工具的 144 组常规矩阵与 6 组大字体 / 高对比环境，保存 150 张 PNG 附件。新增窗口尺寸、滚动视口边界、正文水平宽度、六行导航文字与页标题像素、选中导航文字 4.5:1 对比度断言。像素读取保留位图颜色配置后转换至 sRGB；不使用整个截图的固定哈希。当前离屏宿主没有暴露 SwiftUI 可访问性子节点，因此这些检查属于布局 / 文字渲染覆盖，不代表完整可访问性树或 VoiceOver 验收。

命令行默认把测试 DerivedData 放在系统临时目录，避免从 Documents 内启动测试宿主时出现的加载阻塞；可用 `COMBO_TEST_DERIVED_DATA` 指定另一个目录。测试结果仍保存在仓库的 `build/checks/`。

两个 helper 命令行 target 仅作为测试依赖，不加入应用构建或安装。保留原 C 断言及 `-Wall -Wextra -Werror`，显式取消 `NDEBUG`；Swift Testing 检查正常退出、退出码和成功标记，并保存子进程日志。每次运行有 20 秒上限，超时或取消时终止子进程，临时日志随后清理。

`verify.sh` 每次在 `build/checks/xctest.*/ComboTests.xcresult` 保存结果；Xcode 中可查看每个案例和源码行上的失败。独立命令的结果路径由 Xcode 在日志中给出。覆盖率分别对应无宿主源码子集和隔离宿主模块；不能据此声称实际应用启动或真硬件行为已验证。后续迁移边界见 [迁移调研与进度](../docs/research/xcode-testing.md)。

## 按需工具

这些工具不纳入 `verify.sh`，模拟回归不能替代它们的视觉、设备或网络覆盖。

| 文件 | 用途与操作范围 |
| --- | --- |
| [RenderIcons.swift](Tools/RenderIcons.swift) | 演示状态对照图生成；原边界断言已迁入 IconBoundaryTests。直接编译时需带入 Localization、State、OutputDevice、IconTransition、WiFiIcon 和 IconRenderer 源码 |
| [RenderSettings.swift](Tools/RenderSettings.swift) | 按需导出六页设置预览；全部 150 组矩阵及布局 / 像素断言已纳入 SettingsLayoutTests。链接 Debug Combo 模块，在独立测试 Bundle 内复制本地化与品牌资源 |
| [check-app-lifecycle.py](Tools/check-app-lifecycle.py) / [AppLifecycleCheck.swift](Tools/AppLifecycleCheck.swift) | 复制 Debug App 到临时独立 bundle，执行真实 `ComboApp.main()`，检查完成引导、首次引导及 `--settings` 启动，菜单、尺寸、Dock 激活策略、最小化、重新打开回调和即时语言切换；只修改临时包及其独立偏好域，不操作系统音量 / 网络控制 |
| [LiveState.swift](Tools/LiveState.swift) | 实机读取、观察器、真实启动时不显示权限指引、真实设备静音变化与退出清理，以及真实能耗模式的同值请求；阈值通知、模拟音量提示和菜单权限刷新 / 拒绝访问控制器检查已迁入 StoreIsolationTests，不能当作纯只读工具自动运行 |
| [MediaPlaybackWatch.swift](Tools/MediaPlaybackWatch.swift) | 真实媒体 helper 的 12 秒轮询观察；与 `Combo/Audio/MediaPlayback.swift` 一起编译，运行参数为 `--watch <helper路径>`，不进入默认回归 |
| [airpods-live-check.py](Tools/airpods-live-check.py) | 默认读取真实 AirPods helper；显式 `--write` 测试设置切换和恢复，需开展设备验证时使用 |
| [SparkleFeedCheck.swift](Tools/SparkleFeedCheck.swift) | 线上 HTTPS 清单检查；和 AppUpdater 源码编译到含 feed、公钥及 Sparkle 的独立测试 Bundle，不创建安装会话 |
| [check-sparkle-install.py](Tools/check-sparkle-install.py) | 用真实 Release 副本与回环源验证安装；调用同目录的 [SparkleInstallCheck.swift](Tools/SparkleInstallCheck.swift)，只修改临时隔离包 |

已迁移的图标渲染产物保存为 `.xcresult` 附件，可在 Xcode 的测试结果中查看；独立渲染工具仍输出到 `build/`。真实权限、硬件、系统版本和干净 Mac 的首次安装／更新体验需要另行验收，工具编译通过不等于这些行为已经验证。

## SwiftUI App 入口检查

先构建 Debug 应用，再将 `--app` 指向产物路径：

```sh
python3 Tests/Tools/check-app-lifecycle.py --app /absolute/path/to/Debug/Combo.app
```

工具使用当前产物的 Debug 模块与资源，不进入默认 Swift Testing suite；每条启动路径有 60 秒进程上限，失败保留标准输出并返回非零。临时 App 使用独立 bundle ID 和偏好域，正常退出清理偏好，随后删除临时包。启动产品会读取真实系统状态，因此按需单独执行；不代表真实授权弹窗、硬件控制或更新安装已验收。

## LiveState 编译入口

先构建 Debug 应用（模块必须启用 testability），在仓库根目录将 `APP` 指向该构建的完整 `Combo.app` 路径，然后编译：

```sh
export DEVELOPER_DIR="${COMBO_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
APP="/absolute/path/to/Debug/Combo.app"
PRODUCTS="$(dirname "$APP")"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="$(uname -m)-apple-macosx26.0"
mkdir -p build/checks
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library \
  -I "$PRODUCTS" -F "$PRODUCTS" Tests/Tools/LiveState.swift \
  "$APP/Contents/MacOS/Combo.debug.dylib" \
  -Xlinker -rpath -Xlinker "$APP/Contents/MacOS" -o build/checks/live-state-check
```

编译不执行实机操作。开展实机验证时再运行：

```sh
DYLD_FRAMEWORK_PATH="$APP/Contents/Frameworks" build/checks/live-state-check
```

能耗同值请求通常不写入，但读取后系统状态可能改变，不能保证零写操作。运行前确认当前机器适合这次验证。

## Sparkle 安装检查

更新产物版本防护检查仍在发布模块：`python3 Releases/updates/test-prepare-update.py`。打包与候选准备测试不在这次目录迁移范围内；发布流程见 [更新维护](../docs/release/updates.md)。

`App/AppUpdaterTests.swift` 已纳入 Swift Testing 自动入口，验证 Debug 不启动更新、失败保留成功时间、成功时间持久保存。真实网络清单与安装仍由按需工具验证。

使用真实 Release App 与官方 Sparkle 工具运行隔离安装测试：

```sh
python3 Tests/Tools/check-sparkle-install.py --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
python3 Tests/Tools/check-sparkle-install.py --invalid-signature --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
```

`SPARKLE_DIR` 指向同时含 `Sparkle.framework` 与 `bin/sign_update` 的目录，签名使用本机钥匙串 `combo-updates` 账户。仅隔离回环测试 Bundle 关闭 ATS；正式配置保持 HTTPS。测试结束删除临时包，不修改原 App，不上传正式 appcast。正向检查验证替换与嵌套签名，负向检查验证错误签名拒绝；标准窗口自重启与干净 Mac 首次下载仍需另验收。
