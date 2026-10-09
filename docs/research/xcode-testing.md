# 将现有检查迁入 Xcode 测试工程的可行性

调研日期：2026-10-09。范围：`Tests/` 自动检查、手动工具和 fixture，以及 `Releases/` 两组 Python 回归。调研部分记录迁移前的源码与官方资料核对结果；迁移进度如下，后续表格中的旧文件名用于标识原检查。

## 迁移进度

当前计划内的 Swift Testing 迁移已完成，后续批次文字是历史记录。当前 98 个案例全部使用 Swift Testing，26 个测试文件均已注册，未发现遗留 XCTest 案例或漏注册文件。LiveState 剩余真实启动 / 系统监测 / 设备 / 能耗断言、充电产物检查、Python 静态 / 发布测试、实机 / 线上 / 安装工具按下文已约定的边界继续独立运行；两个 Objective-C helper 已接入 Swift Testing 并保持子进程隔离。

本次收尾核对确认：26 个测试文件全部注册，98 个测试方法全部使用 Swift Testing，未发现遗留 XCTest 案例。修正 TestRunnerCheck.py 中应用菜单案例的筛选路径，补上 IntegrationTests 父 suite；运行器的串行排队、参数透传、失败退出码、取消与锁释放检查通过。更新准备的 6 个 Python unittest 与 DMG 打包的 8 个 Python unittest 全部通过；打包依赖使用 build/dmg-venv 中的现有锁定版本，没有增加项目依赖。注册核对、日志和结果保存在 build/swift-testing-closeout/。

首次完整收尾验收为 96 passed / 2 failed / 0 skipped，退出 65，结果包 build/checks/xctest.FN2sCr/ComboTests.xcresult：PanelMotion 的首次打开高度相差 154pt，AirPlayRoute 的替换请求收到 nil 回退。两例原测试在单独复测时均通过，原断言、等待和生产实现未修改；这两次失败的根因未确认，不能把单独复测通过记作修复。首次验收与两份定向结果均保留。

第二次完整收尾验收退出 0：应用构建、98 个 Swift Testing、本地化扫描、打包充电 helper、签名和品牌检查全部通过，摘要为 98 passed / 0 failed / 0 skipped，结果包 build/checks/xctest.xXz8ia/ComboTests.xcresult。每 0.5 秒采样观察到 ComboTestHost 峰值 1、xctest 峰值 1；两轮完整结果和采样均保留。此次复测通过不代表首次两项失败的根因已经解决；没有修改它们的断言、等待、并发设置或生产行为。

七批共迁移 24 个原自动入口，另将 RenderIcons 的独立断言和 RenderSettings 的全部渲染矩阵纳入自动回归。共享 `ComboTests` scheme 当前包含 98 个测试案例（全部使用 Swift Testing），串行执行无宿主的 `ComboTests`（61 例）和隔离宿主的 `ComboIntegrationTests`（37 例，全部使用 Swift Testing）。前者编译 18 个生产源码文件；后者的宿主编译与应用相同的 35 个 Swift 文件并复用资源。第四批增加最小启动 / 监听隔离接口，默认生产行为保持不变。


Swift Testing 第五批迁移了宿主中的本地化 4 例、菜单 2 例、设置偏好 3 例、启动隔离 1 例，并新增 scope 抛错后的清理回归。两种框架共用原偏好 / AppKit 恢复逻辑，Swift Testing 子 suite 放在共同的串行 `IntegrationTests` 下，递归 scope 逐案例用 defer 清理。故障注入验证原生断言能正常失败、窗口能关闭、状态能恢复；撤去注入后的完整 95 例全部通过，采样宿主峰值 1。详细记录及下一批范围见 [测试入口与 Swift Testing 进度](../../Tests/README.md)。

Swift Testing 第六批完成余下 23 例的迁移，包括全部详情反馈、音柱、面板 / 引导 / 设置渲染及面板动画 / 关闭测试。共用面板 fixture 改为普通上下文与显式 defer 清理，XCTest 基类及断言 / 附件 API 已全部移除；95 个测试方法全部使用 Swift Testing。故障注入已验证渲染附件保留和准备 / 运行失败时的清理。完整组合暴露退出后语言订阅仍重建菜单的问题，原启动案例新增回归断言，确认失败后补上一行取消订阅；最终完整 verify.sh 退出 0，95 例全部通过，附件数量 / 名称一致且图像可解码，采样宿主峰值 1。详细进度及保留的失败记录见上述测试入口文档。

Swift Testing 第七批将旧 LiveState 中的阈值变化通知、模拟音量提示状态 / 续期 / 到期恢复迁入既有 StoreIsolationTests，新增 2 例 Swift Testing 并保留原 10 处条件断言与等待。生产源码、target、宿主和串行配置不变；剩余实机检查继续由 LiveState 按需执行。定向 4 例通过，故意断开通知 / 删除续期后两例正确失败并返回 65，注入已恢复。最终完整 verify.sh 退出 0，97 例全部通过，LiveState 工具单独编译 / 链接通过；未运行实机工具。详细记录见 [测试入口与 Swift Testing 进度](../../Tests/README.md)。

Swift Testing 第八批继续迁移 LiveState 的菜单权限刷新 / 拒绝访问控制器检查，新增 1 例并保留原 3 处断言及权限条件分支。当前宿主未授权时验证指引显示且不启动菜单扫描；授权宿主只验证刷新，不把条件分支未执行误算为拒绝覆盖，实际路径记录为文本附件。真实 App 启动与设备检查继续保留手动入口。定向 5 例通过，本机实际执行拒绝分支；故意破坏指引 / 扫描状态后，新案例失败，其余 4 例通过，退出 65，注入已恢复。最终完整 verify.sh 退出 0，98 例全部通过，完整结果的新附件确认拒绝路径状态；采样宿主峰值 1。LiveState 工具编译 / 链接通过，未执行实机操作。详细记录见 [测试入口与 Swift Testing 进度](../../Tests/README.md)。

| 批次 | 已迁入的原检查 | XCTest 方法数 |
| --- | --- | ---: |
| 第一批 | State、Onboarding、OutputDevice、MediaPlayback、EnergyApps | 30 |
| 第二批 | WiFiControl（2）、HotspotControl（1）、AirPlayDiscovery（1）、AirPlayRoute（1）、AirPods（4）、ChargeControl（5） | 14 |
| 第三批 | AppUpdater（1）、IconTransition（11）、MediaPlaybackHelper 与 AirPlayHelper 子进程检查（各 1） | 14 |
| 第四批 | Localization（4）、SettingsPreferences（3）、DetailFeedback（3），新增宿主 / Store 隔离检查（1） | 11 |
| 第五批 | ApplicationMenu（2）、MediaBars（1）、RenderIcons 中的边界断言（3） | 6 |
| 第六批 | PanelDesign（4）、OnboardingDesign（3） | 7 |
| 第七批 | PanelMotion（1）、PanelDismiss（7），新增激活观察器 / 退出清理（2）、设置渲染布局（2） | 12 |

首批保留 202 处原 `assert`；第二批逐项比对保留 143 处行为断言，充电 helper 等待前提改为有截止时间的抛错，打包 helper 的 JSON 断言拆到 [ChargeHelperCheck.swift](../../Tests/Tools/ChargeHelperCheck.swift)。成功、状态过期、失败与超时拆为独立充电案例。Wi-Fi 保留随机账户的真实本机凭据持久化 / 删除检查，关联网络和密码查询使用原注入；没有连接真实网络或操作真实充电状态。

新增案例在结束或抛错时清理临时 helper、浏览器、订阅和偏好域；AirPlay 路由回调在清理时置空，避免回调捕获 probe 造成跨案例残留。禁止路径从 `fatalError` 改为 XCTest 失败与安全返回 / 抛错，等待失败终止当前方法，避免继续访问不存在的结果。

`verify.sh` 使用一次 `xcodebuild test` 执行已迁部分，其余 4 个独立入口（含充电产物检查）和签名、品牌检查继续保留。原媒体 `--watch` 模式保留在 [MediaPlaybackWatch.swift](../../Tests/Tools/MediaPlaybackWatch.swift)。Sparkle、图标 fixture 和 Objective-C helper 子进程已接入；本地化、设置、详情反馈、菜单和音柱已迁入；面板与引导渲染也已迁入；后续处理窗口动画与关闭检查。

第二批首次 44 个案例全部通过。故意让路由等待超时、让空 SSID 进入禁用密码回调后，两例正确失败，另一例仍通过，进程正常结束并返回 65；错误注入已经恢复。连续两轮重复执行共 88 次全部通过，记录在 `build/stage2-repeat.log`。首次完整入口在尚未迁移的 `PanelDismissCheck` 内容移除后的窗口高度断言处失败；单独诊断和先运行 PanelDesign 后的三次诊断均未复现，原断言和 300ms 等待保持不变，仅补充失败时的窗口 / 内容尺寸。原因尚未确认，不能将一次复测通过视作已修复。最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出码为 0，44 个 XCTest、15 个独立入口、签名与品牌检查全部通过，记录在 `build/stage2-verify-final.log`。先前失败保留在 `build/stage2-verify.log`，诊断记录在 `build/panel-dismiss-diagnostic*.log`。

第三批逐项比对保留 AppUpdater 的 11 处断言、IconTransition 的 148 处完整断言及消息，分别迁为 1 个更新组件案例和 11 个图标行为 / 渲染案例。更新保持 `isEnabled: false`、独立随机偏好域和不启动的 Sparkle driver。Sparkle 通过测试 target 的 package dependency 自动嵌入；没有手工复制 framework 或修改应用 target。图标基准从测试 bundle 查找，并与原 PNG 逐字节核对；原 5 张 PNG 和 1 个 GIF 改为 `.xcresult` 附件，临时目录在每例结束清理，像素阈值保持不变。

两个 Objective-C helper 保留原源文件、C 断言、系统调用替身与独立进程；新增两个命令行 target 仅作为 `ComboTests` 的构建依赖，编译产物复制进测试 bundle。没有新增按模块划分的测试 bundle，也不让 helper target 进入应用依赖。编译保留 `-Wall -Wextra -Werror` 并取消 `NDEBUG`，避免优化配置关闭断言。XCTest 分别验证退出原因、退出码及成功标记；日志使用临时文件避免管道写满阻塞，保存为附件后清理，20 秒超时或任务取消时杀掉子进程。这是进程集成检查，两个方法不代表原 C 断言已经变成逐条 XCTest。

第三批质量校准：故意破坏更新成功状态、Wi-Fi 像素阈值和媒体 helper 的一个 C 断言，三个案例均准确失败，AirPlay helper 与后续 State 案例仍通过，返回码为 65；另外故意阻塞媒体 helper，20 秒超时正确报告，后续 State 案例通过，返回码为 65。所有注入均在 `finally` 恢复，记录分别在 `build/stage3-calibration.log`、`build/stage3-timeout-probe.log`。首次图标 / Sparkle 56 案例通过，两个新增 helper 案例也通过；从 `build/stage3-native.xcresult` 实际导出了 6 个图像附件。全部 58 个案例在同一测试会话逐例重复两次，共 116 次全部通过，记录在 `build/stage3-repeat.log`。

第三批完整入口两次在未迁移的 `PanelMotionCheck` 快速关闭 / 重开后的复合断言失败，58 个 XCTest 均已通过。失败信息显示可见性、alpha、expanded 均正常，横坐标却移动 1920px。三次初始独立诊断未复现；随后加入屏幕诊断成功复现：刚创建的状态栏窗口高度为 0，`screen` 暂指向内置屏，稍后才落位到外接屏，导致重开使用另一块屏幕。原失败保留在 `build/stage3-verify.log`、`build/stage3-verify-final.log`，复现记录在 `build/stage3-panel-motion-screens.log`。

修正在测试准备阶段先完成 `NSApplication.finishLaunching()`，再异步等待状态栏窗口高度大于 0 且有 screen，截止时间 2 秒；失败则明确抛错并附 frame / screen / main，统一清理窗口、Store 和状态栏项。保持原 450ms 动画等待、全部位置 / 可见性断言和产品逻辑。仅等待的版本三次独立运行通过，记录在 `build/stage3-panel-motion-fixed-*.log`，但完整入口仍报告未落位，记录在 `build/stage3-verify-complete.log`；该版本不作为最终验收。加入应用启动初始化后的初次独立运行也曾报告未落位，记录在 `build/stage3-panel-motion-launched-1.log`；最终入口完成了全部检查，状态栏未在截止时间内就绪仍明确失败，不将其隐藏或重试为成功；在临时副本故意跳过等待时，前提检查正确失败，记录在 `build/stage3-panel-motion-precondition.log`。这解决的是已复现的测试初始化问题，不能据此声称之前 PanelDismiss 的窗口高度失败也已修复。

第三批最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出码为 0，58 个 XCTest、11 个独立入口、签名与品牌检查全部通过，记录在 `build/stage3-verify-accepted.log`。最终 PanelMotion 文件另连续运行三次均通过，记录在 `build/stage3-panel-motion-final-*.log`；两个 helper 日志也已从 `.xcresult` 实际导出并核对成功标记。失败日志与诊断保留，没有修改像素基准或放宽原有动画 / 尺寸断言。

第三批结束时还有 9 个 Swift 入口可继续迁移：Localization、ApplicationMenu、MediaBars、PanelMotion、PanelDismiss、DetailFeedback、SettingsPreferences、PanelDesign、OnboardingDesign。当时这些入口依赖 `Bundle.main` 资源或完整 Combo 模块 / AppKit 状态，继续保留在统一入口中，并计划先验证独立资源 / 偏好域及应用启动隔离；不能直接把真实 Combo 设置为宿主，因为 Store 构造会启动系统监听和 helper。PanelDismiss 曾出现的窗口缩小失败仍需确认原因，不能通过加大等待或放宽尺寸断言掩盖。Python 本地化扫描、充电 helper 产物、品牌及签名门禁继续保留独立入口。

第四批迁入本地化、设置和详情反馈三个入口，逐项核对保留 36、30、18 处完整原断言及消息，共 84 处。资源路径 / 字典前提使用 `XCTUnwrap` 安全终止当前案例；中英文 Localizable 和 InfoPlist 字符串表与宿主编译资源按解析值核对一致。旧三个 Swift 入口及对应手工编译步骤已删除。

新建 `ComboTestHost` 和 `ComboIntegrationTests`，沿用共享 scheme / plan，关闭并行。宿主使用独立 bundle ID `local.combo.integration-host`，`COMBO_TEST_HOST` 只用于该 target，主入口仅运行 AppKit 事件循环，不创建产品 AppDelegate。Store 新参数 `monitorsSystem` 默认 true，测试传 false 后不启动监听 / helper、自动刷新及位置授权回调；WiFiControl 新参数 `observesLocationAuthorization` 默认 true。新增隔离案例验证事件循环运行后这些状态仍未启动。现有发行应用的 target 配置和源文件成员保持原样。

首次宿主从 Documents 下的 DerivedData 启动，在 dyld 的 open 调用中停滞，采样保留在 `build/stage4-host-sample.txt`，该次中断不能作为通过（`build/stage4-first.log`）。切换至系统临时目录后可正常运行；这说明目录位置相关，尚不能据此确定是系统权限机制的哪一项。`verify.sh` 默认改用 `${TMPDIR:-/tmp}/Combo-XCTest`，支持 `COMBO_TEST_DERIVED_DATA` 覆盖。

随后第一轮 10 个迁移案例中，详情反馈因位置授权异步回调刷新了模拟 Wi-Fi 名称而失败（`build/stage4-isolated-host.log`）。这暴露了旧独立入口缺少运行中事件循环时未发现的外部状态干扰。通过上述位置回调隔离接口消除干扰，保留原失败回退断言和等待上限，没有在断言前重新塞入状态或放宽条件。

偏好隔离由 `IntegrationTestCase` 在每例前确认宿主 ID，完整保存 / 恢复宿主持久偏好域、语言和激活策略；原域不存在时恢复为不存在。设置案例关闭窗口、释放内容，控制器停止并清理随机偏好域。质量校准预置宿主哨兵偏好，故意破坏本地化、阈值、反馈和隔离四类断言：4 例准确失败、其余 7 例通过，返回 65，完整宿主偏好域保持原样，真实 `local.combo.app` 偏好在前后逐字节核对未变。注入与预置偏好全部恢复，记录在 `build/stage4-calibration.log`。

全部 69 例首次通过（`build/stage4-native.log`），逐例重复两次共 138 次通过（`build/stage4-repeat.log`）。完善“原偏好域不存在”的恢复语义后，最终 11 个集成案例又逐例重复两次共 22 次通过（`build/stage4-integration-repeat.log`）。

第四批首次完整入口的 69 个 XCTest 均通过，但保留的 PanelMotion 在初始化时报告状态栏窗口已有高度、screen 仍为 nil（`build/stage4-verify.log`）。原准备循环只等高度，未等 guard 同时要求的 screen；修正为同时等待这两项前提，仍保留 2 秒截止时间及所有动画断言。再次完整入口中的 PanelMotion 已通过，不扩大动画等待或忽略初始化失败。

第二次完整入口的 69 个 XCTest、PanelMotion 与 PanelDesign 均通过，但 PanelDismiss 在 open() 的“打开后保持可见”断言失败（`build/stage4-verify-final.log`），与既有窗口缩小失败位置不同。补充打开次数、窗口与前台应用 / 屏幕信息后，按原顺序运行保留检查时该案例通过（`build/stage4-remaining-diagnostic.log`）。没有改变 300ms 等待或原判定；该次失败未复现，原因仍未确认，不将诊断运行通过视为修复。

第四批最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出码为 0，69 个 XCTest、8 个独立入口、签名与品牌检查全部通过，记录在 `build/stage4-verify-accepted.log`，结果包为 `build/checks/xctest.x8EW4j/ComboTests.xcresult`。保留的渲染检查包含 60 组图标 / 主题、24 组面板 / 详情和 96 组引导渲染。前述两次完整入口失败与诊断均保留；PanelDismiss 的偶发失败仍作为未定位风险。

第四批结束时剩余 6 个 Swift 入口：ApplicationMenu、MediaBars、PanelMotion、PanelDismiss、PanelDesign、OnboardingDesign。可优先迁入音柱与菜单，再迁窗口动画 / 渲染；PanelDismiss 的既有窗口缩小失败仍需定位，原覆盖继续执行。Python 本地化扫描、充电 helper 产物、品牌与签名仍作为独立门禁。

第五批迁入 ApplicationMenu 的 2 个案例、MediaBars 的 1 个案例，以及 RenderIcons 的 3 个边界案例，没有增加 target 或修改生产源码。原菜单 20 处完整断言和图标工具 5 处完整断言及消息逐项核对保留；音柱保留 18×20pt 采样区域、每轮 6 帧、200ms 间隔、切换后 300ms 等待和 `[true, false, true, false]` 的四次切换及变化判定。它是实际渲染集成检查，不能仅用 playing / reducedMotion 状态断言替代。

菜单沿用隔离宿主，使用 `Store(monitorsSystem: false)`；分别验证双语菜单、action / target、快捷键、Services / 更新可用性，以及设置窗口的 Dock、最小化、重开与关闭行为。IntegrationTestCase 新增主菜单和 Services 菜单的保存 / 恢复，设置案例在抛错或结束时关闭窗口并释放内容。先验证非分隔项数量再索引，缺项会报告 XCTest 失败，不中断整个进程。音柱同样使用无监听 Store，清理窗口和内容，将每轮采样保存为结果附件。

图标边界加入现有无宿主 bundle：充电缺口圆头、19% / 20% / 21% 及满电颜色、深浅外观、16 个演示场景数量和 22pt 原生尺寸。保持原取样坐标、目标颜色、颜色空间校准和像素阈值；强制解包改为 XCTUnwrap。RenderIcons 只保留原演示图生成流程，去掉已迁断言，输出消息改为渲染结果，不将生成预览图称为回归通过。

第五批首轮新增 6 例及已有 11 个宿主案例共 17 例通过（`build/stage5-first.log`）。全套 75 例逐例重复两次，共 150 次通过（`build/stage5-repeat.log`）。音柱的 24 张采样 PNG 已从结果包实际导出并检查格式和非零尺寸，保存在 `build/stage5-media-attachments/`。

质量校准故意破坏圆头像素、菜单标题、窗口解包前提和音柱变化判定：17 例中 4 例准确失败、13 例通过，返回 65（`build/stage5-calibration.log`）。窗口前提抛错后仍执行清理；临时预置的主菜单 / Services 菜单和激活策略在每例 teardown 后按对象身份 / 值核对恢复，没有新增失败。宿主完整偏好域保持一致，真实 Combo 偏好逐字节未变，所有注入和预置偏好在 finally 恢复。旧菜单 / 音柱入口及 verify.sh 对应手工编译步骤已删除。

第五批最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出码为 0，75 个 XCTest、6 个保留的独立入口、签名与品牌检查全部通过（`build/stage5-verify.log`；结果包 `build/checks/xctest.uoSab6/ComboTests.xcresult`）。本轮完整入口没有出现新的失败，既有 PanelDismiss 偶发风险仍保留。修改后的 RenderIcons 单独编译、运行成功，生成 16 个演示场景预览；结果另存 `build/stage5-icons-preview.png`，原预览若存在则恢复，记录在 `build/stage5-render-icons.log`。最终文档链接、脚本语法及 diff 空白检查通过。

第五批结束时剩余 4 个 Swift 自动入口：PanelDesign、OnboardingDesign、PanelMotion、PanelDismiss。优先迁面板 / 引导渲染，再处理窗口动画与关闭。PanelDismiss 的既有偶发失败原因仍未确认；源码扫描、充电产物、品牌与签名继续保留独立门禁，实机 / 线上 / 安装工具保持按需执行。

第六批将 PanelDesign 拆为 4 例（封面 / 对比度、行交互像素、面板 / 详情布局、AirPods 早到 / 晚到数据），OnboardingDesign 拆为 3 例（渲染与导航矩阵、真实启动路径、完成引导后的窗口恢复）。逐项比对保留 18 + 26 = 44 处完整原断言及消息，仅将两处旧专用 app 的宿主 ID 更新为 `local.combo.integration-host`；像素阈值、尺寸、等待时间、96 页矩阵及 Return / Escape / 真实鼠标返回事件保持原样。另补面板 60 组封面 / 主题和 24 组页面的数量断言。

案例沿用现有隔离宿主 / 集成 bundle。所有窗口在抛错时也关闭并释放内容；临时 AirPods helper 与其目录结束后清理。AirPods 原覆盖要求回复身份与当前输出身份匹配，旧入口为取得非零身份启动了真实 Store；新案例使用固定身份 42 和原临时 helper，AudioStore 增加初始输出身份参数，默认仍为 0，避免为了准备渲染而读取真实设备或启动监听。

引导启动案例仍调用生产 `applicationDidFinishLaunching`，使用禁用系统监听的 Store 和 Debug 更新驱动。它会注册工作区激活观察器，旧退出清理未移除该 token；本批在生产退出方法中补充移除与置空，案例显式调用该清理方法并移除状态栏项 / 关闭窗口 / 停止定时器。主菜单 / Services 菜单除对象身份外还恢复原标题和原挂接项；应用图标与命名缓存也保存 / 恢复，避免启动和渲染影响后续案例。没有增加 target，应用 / 宿主 / helper 工程配置及原成员保持不变，仅集成 bundle 添加两个测试源文件。

第六批首轮 7 个新案例全部通过（`build/stage6-first.log`）。全套 82 例逐例运行两次，共 164 次全部通过（`build/stage6-repeat.log`）。从首轮结果实际导出并检查 149 张 PNG：24 张面板 / 详情、24 张行状态、96 张引导页和 5 张前进 / 返回导航图片，保存在 `build/stage6-render-attachments/`。

第六批失败校准：临时破坏面板 bitmap 前提、行像素读取、AirPods 回复前提、引导页脚像素识别和首次启动窗口前提，集成 bundle 的 21 例中 5 例失败、16 例继续通过，返回 65。每例预置 Services 原挂接和标题，核对菜单 / 激活策略 / 应用图标及命名缓存恢复，并检查新原生窗口已关闭且释放内容；宿主完整偏好保持一致，真实 Combo 偏好逐字节未变，临时 helper 目录没有残留。所有注入和预置偏好在 finally 恢复。

首次校准中的引导像素检查直接抛通用 render 错误，Xcode 将其报告为含糊的 InvalidTransition（`build/stage6-calibration.log`）。因此将渲染、窗口、颜色和事件等缺失前提改为带明确消息的 XCTUnwrap；第二次校准准确报告“Missing guide primary-button pixels”“Missing row pixel”及对应 bitmap / 回复 / 窗口前提，保持 5 例失败、16 例通过且没有新增清理失败（`build/stage6-calibration-final.log`）。尺寸前提失败后结束当前布局案例，避免继续用无效尺寸创建 bitmap；原尺寸断言仍保留。旧两个自动入口与 verify.sh 中对应手工编译 / 复制资源步骤已删除。

完善失败报告后的最终 7 个渲染案例又逐例运行两次，共 14 次通过（`build/stage6-render-repeat-final.log`）。这一轮使用最终的前提检查与清理代码；不将故意失败日志作为验收通过记录。

第六批最终 `./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出码为 0：82 个 XCTest、4 个保留的独立入口、签名与品牌检查全部通过（`build/stage6-verify.log`；结果包 `build/checks/xctest.IIsT6q/ComboTests.xcresult`）。本轮没有出现新的非注入失败，PanelMotion / PanelDismiss 的原断言保持不变，既有偶发风险仍保留。最终脚本语法、文档链接及 diff 空白检查通过。

第六批结束时剩余 2 个 Swift 自动入口：PanelMotion 和 PanelDismiss。前者仍需保留多屏落位及真实动画断言；后者有未定位的偶发失败，不通过放宽等待或尺寸条件迁移。Python 本地化扫描、充电产物、品牌与签名保持独立门禁。

## 第七批：面板事件 / 动画与设置渲染

PanelMotion 的 19 处原行为断言迁入 1 个连续交互案例，PanelDismiss 的 31 处原断言迁入 7 个独立案例；打开前提移入共用 PanelTestCase。新增实际应用激活通知回调、退出期间任务 / 监听移除两例，以及 SettingsLayout 的常规矩阵 / 大字体高对比两例，共新增 12 例。两个原 Swift 入口及 verify.sh 内的编译 / 启动块删除。默认自动回归的可迁移 Swift 行为检查已全部进入 Xcode；保留 Python 本地化扫描、充电 helper 产物、品牌与签名门禁。

面板使用既有不监听系统的 Store 和固定演示数据，仍实际创建窗口、状态栏项与 SwiftUI 内容。保留状态栏 frame / screen 的 2 秒准备截止、全部动画等待、位置 / 高度容差、真实本地鼠标事件和通知观察器回调。AppDelegate 新增工作区 NotificationCenter 注入与全局鼠标监听开关，生产默认仍使用真实工作区并启用全局监听；测试向独立中心投递 NSWorkspace 通知，避免用户实际切换应用干扰。退出增加 reveal / detail 任务取消和 Escape monitor 移除，新增案例验证退出后没有迟到更新或事件回调。

首轮面板动画失败的诊断栈明确显示全局鼠标 monitor 收到外部输入并关闭测试面板（`build/stage7-diagnostic.log`）。隔离该输入后面板案例通过。旧 PanelDismiss 的详情收缩偶发失败没有确认根因；原高度 / 对齐断言与 300ms 等待保留，并在固定数据下继续执行，不能据此声称旧产品问题已经修复。

设置渲染承接 RenderSettings 原有 144 组常规矩阵及 6 组大字体 / 高对比组合，保持原 80ms 布局等待。新增窗口 / 内容尺寸、滚动视口边界、正文横向宽度、六行导航文字与标题像素、选中导航文字至少 4.5:1 对比度断言。当前离屏宿主没有提供 SwiftUI 可访问性子节点，相关诊断记录在 `build/stage7-settings-ax.log`；没有将这些检查表述为完整可访问性树或 VoiceOver 验收。像素读取曾将 Display P3 位图组件误当作 calibrated RGB，修正为保留位图颜色配置并转换至 sRGB，原阈值保持不变；150 组全部通过（`build/stage7-settings-profile.log`）。150 张 PNG 已实际导出到 `build/stage7-settings-attachments/`，验证 72 张 1700×1316、78 张 1560×1176。RenderSettings 保留为按需预览导出工具。

初次全套逐例两次运行中，无宿主 122 次通过；宿主面板动画的一次“中间高度帧”检查失败，其他案例通过，结果保留在 `build/stage7-repeat.log`。并行 Timer / async 采样诊断的 10 次运行也有一次未捕获中间帧（`build/stage7-motion-samplers.log`），不接受复测偶尔通过作为验收。新增原生 NSWindow.didResizeNotification 记录，保留原 20 次 15ms 定时采样，对两路真实帧共同检查中间高度和顶部固定，帧与时间保存为附件。新版本连续 10 次通过（`build/stage7-motion-observed.log`）；故意把采样间隔改成 150ms 的校准中，定时采样确实错过中间帧，原生通知仍捕获中间高度，原行为断言通过（`build/stage7-sampling-calibration.log`）。该临时延迟已恢复，正式案例仍为 15ms，不放宽尺寸或延长动画等待。

首轮组合故障校准中五个预期案例失败，另有 Services 恢复与引导 Return 两个额外失败（`build/stage7-calibration.log`），该轮不作为校准验收。独立最小 AppKit 程序确认 `servicesMenu = nil` 不会清除已有菜单；IntegrationTestCase 在首次尚无 Services 菜单时建立可恢复的原生空菜单基线，再保存原对象 / 标题 / 挂接。

最终组合故障校准（`build/stage7-calibration-final.log`）：禁用高度动画、禁用实际本地鼠标 monitor、破坏详情窗口前提、破坏设置 bitmap 前提与文字像素识别，33 个集成案例中恰好 5 例失败、28 例通过，返回 65。临时清理断言确认新面板隐藏 / 内容释放、主菜单 / Services 原对象与标题 / 挂接、激活策略、应用图标与命名缓存恢复；宿主和真实 Combo 偏好逐字节未变。所有注入及临时断言在 finally 恢复（`build/stage7-calibration-final-audit.log`）。此前 Services / 引导额外失败未被忽略；菜单与引导相关 3 例逐例运行三次，共 9 次通过（`build/stage7-menu-guide.log`），最终校准中也继续通过。

最终版本的共享 scheme 逐例运行两次，94 个不同方法每例两次，共 188 次全部通过（`build/stage7-repeat-final.log`；结果包 `build/stage7-repeat-final.xcresult` 的 94 个唯一案例全部 Passed）。旧版未通过的重复运行与诊断日志继续保留，不把它们计入成功验收。工作区共享命令行入口 Tests/run.sh 已用于最终回归，运行器的并发、参数、失败退出码、中断与锁释放检查通过。

最终 `COMBO_TEST_DERIVED_DATA=/tmp/Combo-XCTest ./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 退出码 0：应用构建、94 个 XCTest（结果包 `build/checks/xctest.q0cTPO/ComboTests.xcresult`）、两个独立自动入口、签名和品牌全部通过（`build/stage7-verify.log`）。实际读取结果摘要为 Passed / 94 passed / 0 failed，并逐项核对原 19 + 31 处行为断言仍在新文件与共用准备中。没有故障注入残留；脚本语法、文档本地链接和 diff 空白检查通过。没有执行 Git 暂存、提交或推送。

## 结论

**可以用 Xcode 测试 target 替换大部分 Swift / Objective-C 检查的独立编译与启动流程，但不能用单元测试替代所有现有验证。** 迁移前 25 个自动入口包含 22 个 Swift 检查、2 个 Objective-C helper 检查和1个 Python 源码检查；品牌脚本与签名检查另行执行。前 24 个可逐步迁入测试体系，其中不少仍属于进程、资源或渲染集成测试。Python 静态检查、产物检查、线上源、真硬件与安装验证有独立用途，建议保留。

第一轮建议新增一个 `ComboTests` macOS Unit Testing Bundle，优先使用 XCTest 承接已有断言与串行工作流；按现有功能目录组织测试类，不按目录新建 6 个 target。不为迁移先抽出产品 framework 或改 Swift 语言模式。先证明少量纯逻辑和异步检查可等价运行，再接入渲染与宿主资源。Objective-C helper 的进程隔离应暂时保留。

这不是 XCTest 能力优于 Swift Testing 的一般结论。Apple 推荐新 Swift 单元测试使用 Swift Testing，它也能测试集成行为。这里选择 XCTest 的依据是现有 Objective-C 测试、全局 AppKit 状态、标准输出重定向和偏好隔离，使第一轮保持运行语义更重要。纯 Swift 无共享状态的新测试可以使用 Swift Testing，与 XCTest 共用 target。[Apple：添加测试 target](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)

## 迁移前已核对的工程基线

- 本机指定 `/Applications/Xcode.app/Contents/Developer` 后为 Xcode 27.0（27A266a），Swift 工具链 6.4；工程 `SWIFT_VERSION` 是 5.0。工具链版本和源码语言模式是两个不同配置。
- 工程只有 `Combo` 应用 target、`Combo` scheme 和 Debug / Release；没有测试 target、test plan 或已提交的共享 `.xcscheme`。因此当前不能直接通过添加命令得到等价的 `xcodebuild test` 覆盖。
- Debug 已启用 `ENABLE_TESTABILITY`；数个检查已经 `@testable import Combo`，但目前通过手工链接 `Combo.debug.dylib` 执行。启用 testability 会向 Swift 编译器传入 `-enable-testing`，它不自动创建测试 target 或隔离程序启动。[Apple：Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
- `verify.sh` 同时构建应用、单独编译检查程序、创建带资源的临时 `.app`、运行 Python 检查、校验签名与品牌产物。替换可执行程序部分后仍需要统一脚本协调剩余检查。
- `Combo/App/main.swift` 入口会创建 `AppDelegate` 和 `Store`，然后进入 `app.run()`；不能假定选择 Combo 为 Test Host 后只加载类型、不触发应用启动。

源码依据：[`Tests/README.md`](../../Tests/README.md)、[`verify.sh`](../../verify.sh)、[`Combo.xcodeproj/project.pbxproj`](../../Combo.xcodeproj/project.pbxproj)、[`Combo/App/main.swift`](../../Combo/App/main.swift)、[`Localization.swift`](../../Combo/App/Localization.swift)。

## 每类自动检查如何迁移

下表以现有入口为单位；每个入口可能包含大量断言，不等于一个测试案例。尚未迁移的入口仍是基于源码的建议；已迁移范围与实证结果见上方进度。

| 现有入口 | 可替代范围 | 迁移条件与保留内容 |
| --- | --- | --- |
| App `main.swift`、`OnboardingCheck.swift` | 适合直接单元测试化 | 状态选择、事件时序和引导状态拆成少量按行为分组的测试方法；顶层入口改为测试类，不把 `main.swift` 当应用入口加入测试编译 |
| Audio `OutputDeviceCheck.swift` | 大部分适合直接单元测试化 | 分类、模型名、JSON 和缓存失效可以独立断言；SF Symbol 是否存在属于系统资源检查，保留原覆盖 |
| Rendering `MediaBarsCheck.swift` | 可迁为逻辑 / 渲染测试 | 保留音柱边界和渲染断言，依赖 AppKit 的部分在 MainActor 上运行 |
| App `AppUpdaterCheck.swift` | 可迁为组件集成测试 | 保留 `isEnabled: false` 和独立 defaults，不触发真实更新；链接 Sparkle，保持成功时间持久化与失败回退断言 |
| Network `WiFiControlCheck.swift`、`HotspotControlCheck.swift` | 可迁为带替身的控制器测试 | 沿用现有注入和临时脚本，保留权限拒绝、失败回退和异步取消；不能因此声称真实 Wi-Fi / 热点已验证 |
| Battery `ChargeControlCheck.swift`、`EnergyAppsCheck.swift` | 可迁为控制器 / 子进程集成测试 | 临时 helper、超时、重复点击、过期状态断言可保留；充电检查末尾还读取打包 helper 的真实 `--status`，该部分作为额外产物集成检查保留 |
| Audio `AirPodsCheck.swift`、`AirPlayRouteCheck.swift`、`AirPlayDiscoveryCheck.swift`、`MediaPlaybackCheck.swift` | 可迁为异步组件集成测试 | 保留假 helper、取消、轮询停止和晚到结果丢弃等覆盖；等待与超时仍要保证测试运行时继续调度 MainActor，不可用阻塞等待代替 |
| App `LocalizationCheck.swift`、`ApplicationMenuCheck.swift` | 可迁，但先解决 bundle / 偏好隔离 | 原检查使用专用 `.app` 提供资源和独立偏好域；直接迁为 hosted test 可能访问真实 Combo 偏好。迁移前明确资源 bundle 与保存恢复策略 |
| Views `PanelMotionCheck.swift`、`PanelDismissCheck.swift`、`DetailFeedbackCheck.swift`、`SettingsPreferencesCheck.swift` | 可迁为 AppKit / 控制器集成测试 | 仍需主线程、窗口和事件调度；关闭窗口、停止 Store / observer / task 并恢复全局状态。不属于端到端鼠标键盘 UI 测试 |
| Views `PanelDesignCheck.swift`、`OnboardingDesignCheck.swift` | 可迁为渲染集成测试 | 保留 `NSHostingView`、布局 / 像素断言、主题及本地化资源；生成图片可附到测试结果，图像差异仍受系统字体、颜色和渲染版本影响 |
| Rendering `IconTransitionCheck.swift` | 可迁，建议分逻辑和像素两组方法 | 前半转场时序适合单元测试；后半图标像素、基准 PNG 和演示输出是渲染检查。不能只保留状态断言而丢掉像素覆盖 |
| Audio `AirPlayHelperCheck.m`、`MediaPlaybackHelperCheck.m` | 可使用 Objective-C XCTest；不建议首轮直接合并到共享进程 | 当前直接导入 helper 源码并用宏替换系统调用，存在静态测试状态；AirPlay 检查还用 `dup2` 重定向进程 stdout。先保留独立 executable，由测试启动并检查结果，后续再评估重写为 XCTestCase |
| Views `PanelLocalizationCheck.py` | 保留 Python 静态检查 | 扫描 Swift 字面量与字符串表，不是运行应用行为；重写为 Swift 没有覆盖收益。可继续由 `verify.sh` 调用 |

品牌 [`check-brand.sh`](../../Tests/App/check-brand.sh) 检查编译产物 `AppIcon.icns`、`Assets.car`、Info.plist 和源 SVG；`codesign --verify --deep --strict` 检查整个产物。即使由 XCTest 调用 subprocess，它们仍是产物门禁，不会变成单元测试。建议保持脚本，传入本轮构建产物路径。

## 手动工具、fixture 与发布回归

| 文件 / 资源 | 迁移建议 |
| --- | --- |
| `Tools/RenderIcons.swift` | 第五批已将圆头、颜色边界、场景数量与原生尺寸断言纳入 IconBoundaryTests；演示图生成保留为按需工具 |
| `Tools/RenderSettings.swift` | 第七批已将全部 150 组矩阵纳入 SettingsLayoutTests 并补充布局 / 像素断言；按需预览导出和人工视觉验收保留 |
| `Tools/LiveState.swift` | 阈值通知、模拟音量提示以及菜单权限刷新 / 拒绝访问控制器检查已迁入 StoreIsolationTests 的 3 个 Swift Testing 案例；权限检查只读当前宿主授权状态，拒绝分支按实际状态执行，并记录分支覆盖附件。其余真实启动、系统监测、设备静音变化和能耗同值请求继续保留为按需实机工具 |
| `Tools/airpods-live-check.py` | 保留实机工具；设备存在和私有接口支持需要真实硬件，显式 `--write` 路径涉及设置切换和恢复 |
| `Tools/SparkleFeedCheck.swift` | 可单独纳入手动集成计划，但不进入默认单元回归；线上 HTTPS 与公钥 / 清单检查不能以假响应代替 |
| `Tools/SparkleInstallCheck.swift`、`Tools/check-sparkle-install.py` | 保留隔离安装工具；安装替换、自重启、嵌套签名及错误签名拒绝涉及独立 App 副本和安装进程。Xcode 可以协调执行，但不替代真实安装条件 |
| `Fixtures/WiFiReference.png` | 迁入测试 bundle 的资源阶段，通过测试 bundle 查找；不要求测试工作目录恰好为仓库根目录，不修改基准以使结果通过 |
| `Releases/updates/test-prepare-update.py` | 保留 Python unittest：直接测试 Python 更新准备实现，覆盖版本 / 构建号、旧清单迁移、已有产物、远端失败和错误公钥防护 |
| `Releases/packaging/test-dmg.py` | 保留 Python unittest：直接测试 Python 打包实现，覆盖可执行权限、发布失败回滚、元数据保留和挂载清理。部分案例调用真实 `hdiutil` / `diskutil`，不宜偷偷纳入默认单元测试 |

调研基线的“7 个手动工具”按源文件计数；首批迁移新增独立媒体观察入口后为 8 个源文件、7 个工具用途。

## XCTest 与 Swift Testing：当前能力与选择

Xcode 16 起内置 Swift Testing。Swift Testing 与 XCTest 可位于同一测试 target / bundle；XCTest 支持 Swift 和 Objective-C，UI 自动化与性能测试仍使用 XCTest。Swift 测试可以调用其他语言的代码，但用 Objective-C 编写的测试无需为框架选择而翻译成 Swift。[Apple：Testing](https://developer.apple.com/documentation/xcode/testing)、[Apple：Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/)

**不要把“同 target 共存”与“同一个测试混用 issue API”混为一谈，也不要沿用 Xcode 16 的绝对禁止混用表述。** Xcode 27 支持有限集合的跨框架 issue interoperability：旧 test plan 默认 limited，XCTest 失败在 Swift Testing 中可能降为警告；新项目默认 complete，会保留错误；strict 会在这类跨框架报告处中止。建议每个测试使用其原生断言；若复用跨框架 helper，明确选择 complete 并验证故意失败确实失败。[Apple：Migrate to Swift Testing，WWDC26](https://developer.apple.com/videos/play/wwdc2026/267/)

Swift Testing 默认在同一进程并发执行。`.serialized` 只串行化指定 suite 的内部测试与子 suite，不互斥无关 suite；单个非参数化方法加此 trait 没有串行化其他方法的作用。[Apple：Running tests serially or in parallel](https://developer.apple.com/documentation/testing/parallelization)

需要 AppKit / SwiftUI 的测试应明确在 `@MainActor` 上运行；异步 setup / teardown 也要遵守对应 actor。MainActor 保证 actor 上执行，不保证一个含 `await` 的完整测试独占全局状态。[Apple：Defining test functions](https://developer.apple.com/documentation/testing/definingtests)、[Apple：Set Up and Tear Down State](https://developer.apple.com/documentation/xctest/set-up-and-tear-down-state-in-your-tests)

因此，首轮 `ComboTests` 采用 XCTest 并关闭并行执行，是降低现有共享状态迁移风险的选择；这不能替代逐测试清理，也不能恢复“每个文件独立进程”的隔离。后续无共享状态的纯 Swift 测试使用 Swift Testing 完全可行，无需再新建 target。

## 初期工程方案与迁移约束

首批建议只新增一个 `ComboTests` 和一个共享测试 scheme / 默认 test plan，在现有 App、Audio、Battery、Network、Rendering、Views 目录内保留分类。默认计划只包含确定性回归，关闭并行执行；人工工具与发布脚本仍由原入口协调。测试文件只能加入测试 target，不加入发行应用。

**Test Host 不能未经验证就选 Combo。** Hosted 方式最便于 `@testable import Combo` 和访问 App 资源，但应用启动会创建实际 Store 等状态。迁移时需要证明宿主启动可被隔离，不启动真实监听 / 更新 / 控制，并隔离标准偏好；或者先使用无应用宿主的 bundle 编译现有检查所需生产源码子集，延后依赖整个 Combo 模块的 Views 检查。首批已验证无应用宿主的源码子集方案；第四批已验证独立宿主编译完整生产模块的隔离方案，真实 Combo 仍不直接作为测试宿主。也不建议为绕开此问题先抽新产品 framework。

`TEST_HOST` 指定运行测试的宿主，`BUNDLE_LOADER` 指定加载 bundle 的 executable 并参与未定义符号链接检查；宿主与链接设置必须一起验证。继续依赖手工 `Combo.debug.dylib` 路径并不会自动获得稳定的 Xcode 测试配置。[Apple：Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)

**Bundle 与偏好域需要明确。** `Bundle.main` 是运行 executable 的主 bundle，并非永远是 `.xctest`。fixture 应通过 `Bundle(for: 测试标记类.self)` 找测试 bundle；本地化与品牌检查则应明确使用应用资源 bundle 或隔离宿主的资源。迁移前 `LocalizationCheck` 改写 `Localization.shared` 和 `UserDefaults.standard`，原清理逻辑只是删除 key；直接搬到真实宿主可能删除开发者原设置，必须改成独立 suite / bundle 或精确保存恢复。[Apple：Bundle](https://developer.apple.com/documentation/foundation/bundle)

**断言迁移不能仅包装 `main()`。** Swift `assert` / C `assert` 失败会中断进程，不能提供正常逐案例结果；优化配置还可能使断言失效。直接迁移的断言改为 `XCTAssert…` / `XCTUnwrap` 或 `#expect` / `#require`；重要前提失败后应终止当前案例，不要改成记录失败后继续危险操作。暂保留的 helper executable 可继续在当前配置独立执行，由 XCTest 检查退出码和输出，不能将其误算为细粒度单元覆盖。

**异步与清理需要保留。** 不用同步 sleep / wait 阻塞 MainActor；保留 cancellation / timeout 断言，并在每例结束关闭窗口、停止 observer / task / helper，清理临时目录、恢复偏好和 NSApp 状态。固定等待时长可后续改成有上限的条件等待，但不为首次迁移扩大产品改动。

## 建议迁移顺序与验收

1. 首批只选状态规则、Onboarding 状态、OutputDevice 分类、MediaPlayback 的解码 / 元数据保留规则、EnergyApps 的归属与聚合规则等纯逻辑；不把对应文件里的整套异步、系统资源检查都算作首批。再选一个临时 helper 异步案例做小样，验证 Xcode 发现测试、失败能准确记录、异步能完成，且不启动真实产品监听，不污染用户偏好。
2. 确定宿主方案后迁入其余确定性 Swift 逻辑 / 控制器检查。先不改变测试含义，每迁一个入口比对原断言清单，旧入口在覆盖等价后删除。
3. 迁入本地化、菜单、Views 和图标渲染检查，解决 bundle、临时产物和全局清理。保留 Objective-C helper 的独立进程直到 stdout 与静态状态可安全隔离。
4. 将 `verify.sh` 中已迁部分改为一次 `xcodebuild test`，保留签名、品牌与 Python 静态检查；发布 Python unittest 与实机 / 安装工具保持明确的独立运行入口。同步更新 Tests README 和工程共享配置。

target / scheme / plan 已创建，下列命令现在可运行已迁移及新增的 98 个案例；完整回归仍使用 `./verify.sh`：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Combo.xcodeproj -scheme ComboTests \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO -derivedDataPath "${TMPDIR:-/tmp}/Combo-XCTest"
```

共享 scheme 名为 `ComboTests`。test plan 控制参与的测试、配置与诊断选项，可在需要多个计划时用 `-testPlan` 明确选择。`build-for-testing` / `test-without-building` 可分别用于编译验收与复用已建产物，不必保留逐文件 swiftc 命令。[Apple：组织测试计划](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback)、[Apple：命令行测试 TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)

验收应包含原行为覆盖清单、故意制造失败能否报错、测试数量是否非零、资源查找、重复执行与顺序独立性、取消后的任务清理，以及执行前后偏好不变。主迁移不以运行真硬件操作或安装工具作为单元测试验收。

## 尚未验证

无应用宿主的源码子集、Sparkle 加载、测试 bundle 图标资源和隔离 helper 子进程已验证。独立应用宿主的启动 / 监听隔离、真实资源和偏好恢复已验证。直接使用发行 Combo 作为宿主、无宿主链接完整 Combo 模块、Objective-C 同 bundle 链接及宏导入后的符号冲突未验证。没有运行 UI 自动化、真实硬件、线上 feed 或隔离安装。分类为“可迁移”代表能力与源码结构支持，不能当作工程已可运行的证明。
