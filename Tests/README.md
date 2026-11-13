# 测试与检查入口

在仓库根目录运行 `./verify.sh`：构建应用，运行默认后台测试计划、本地化扫描、设计资源同步检查和充电 helper 产物检查，再验证签名与品牌资源。默认不显示应用窗口；窗口、焦点和真实设备行为需单独验收。

```sh
./verify.sh
# 无 Developer ID 的本地构建：
./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

## Xcode 单独运行

选择共享 `ComboTests` scheme 和默认的 `ComboBackgroundTests` 计划，按 ⌘U；命令行使用共享入口：

```sh
./Tests/run.sh
./Tests/run.sh -only-testing:ComboTests/StateTests
# 仅在明确需要前台界面验收时运行，会显示窗口并切换焦点：
./Tests/run.sh -testPlan ComboTests
./Tests/run.sh -testPlan ComboTests -only-testing:ComboIntegrationTests/IntegrationTests/ApplicationMenuTests
```

| 计划 | 范围 |
| --- | --- |
| [ComboBackgroundTests](ComboBackgroundTests.xctestplan) | 无宿主 `ComboTests`，另选集成 suite 中的音频电量清理案例；不运行窗口交互 |
| [ComboTests](ComboTests.xctestplan) | 两个测试 bundle 的完整串行覆盖，包含窗口、Dock 生命周期、焦点和动画 |

Xcode 会保留手动选择的计划，日常开发应选回后台计划。测试数量与筛选以当前源码和计划为准，不维护迁移时的固定计数。

[run.sh](run.sh) 使用系统文件锁，让同一用户、同一临时目录下的命令排队；退出时释放锁，保留参数与失败退出码。直接执行 `xcodebuild` 或 Xcode ⌘U 不经过该锁，应避免与命令行检查重叠。运行器自检：`python3 Tests/Tools/TestRunnerCheck.py`。

DerivedData 默认位于系统临时目录，可用 `COMBO_TEST_DERIVED_DATA` 覆盖。`verify.sh` 结果保存到 `build/checks/xctest.*/ComboTests.xcresult`；独立测试命令在日志中给出结果路径。Xcode 可查看失败源码、PNG、GIF 和 helper 日志附件。

## 自动回归与隔离

Swift 案例使用工具链内置 Swift Testing，按 `App/`、`Audio/`、`Battery/`、`Network/`、`Rendering/`、`Views/` 分类。框架选型与历史问题见[测试设计与问题记录](../docs/research/xcode-testing.md)。

| 测试边界 | 覆盖与约束 |
| --- | --- |
| `ComboTests` | 状态、引导偏好、设备分类、媒体解码、电池控制、网络、AirPods/AirPlay、图标像素与转场；编译生产源码子集，无应用宿主 |
| `ComboIntegrationTests` | 本地化、设置、菜单、详情反馈、面板、引导渲染、动画与退出清理，以及 Store 通知与状态恢复；使用隔离宿主 |
| Objective-C helpers | 原生命令行 target 仅为测试依赖；保留 C 断言、`-Wall -Wextra -Werror` 并取消 `NDEBUG`。Swift Testing 检查子进程退出码、成功标记与日志，20 秒超时或取消时终止进程 |
| 独立门禁 | `verify.sh` 调用源码本地化扫描、设计导出检查、打包充电 helper 的只读 `--status`、签名与品牌检查；发布 Python 回归见[更新维护](../docs/release/updates.md)与[DMG 打包](../Releases/packaging/README.md) |

- `ComboTests` 使用替身、临时 helper 或随机偏好域；不连接真实 Wi-Fi、不访问钥匙串、不执行真实更新或充电控制。AppUpdater 保持禁用真实更新并随测试 bundle 嵌入 Sparkle。
- [TestHostApp.swift](Support/TestHostApp.swift) 只启动 AppKit 事件循环，不创建产品 AppDelegate/Store。集成案例使用 `Store(monitorsSystem: false)`，Wi-Fi 替身禁用位置授权回调；产品 SwiftUI 入口与 Commands 的真实启动由按需工具验证。
- [IntegrationTestCase.swift](Support/IntegrationTestCase.swift) 提供串行 `IntegrationTests` suite 与逐案例 scope，先验证宿主 ID，再保存和恢复宿主偏好域、语言、菜单/Services、激活策略、图标及缓存。原偏好域不存在时恢复为不存在；不访问真实 Combo 偏好域。
- [PanelTestCase.swift](Support/PanelTestCase.swift) 在准备前注册清理，等待状态栏尺寸和 screen 就绪；使用固定演示数据、独立工作区通知中心并关闭全局鼠标监听。结束或抛错时关闭窗口、释放内容、取消任务/订阅、移除状态栏项并停止 Store。
- [WiFiReference.png](Fixtures/WiFiReference.png) 是像素基准；不能作为闲置预览删除，也不能为过测试修改。渲染附件在清理临时目录前保存，读取失败应报告为测试失败。

面板、引导与设置覆盖浅深外观、布局、文字、像素、交互及部分辅助功能环境；动画保留定时采样与原生 resize 通知。位图按原颜色配置转换到 sRGB 后检查，不以实时截图固定哈希代替行为断言。离屏宿主未提供完整 SwiftUI 可访问性树，不能据此声明 VoiceOver 已验收。

后台计划不覆盖窗口、Dock 生命周期或焦点；模拟测试不代表真实授权、硬件、线上更新或安装已通过。历史偶发失败与未确认根因见[问题记录](../docs/research/xcode-testing.md#待复核的历史问题)。

## 按需工具

这些工具不纳入 `verify.sh`，模拟回归不能替代它们的视觉、设备或网络覆盖。

| 文件 | 用途与操作范围 |
| --- | --- |
| [RenderIcons.swift](Tools/RenderIcons.swift) | 演示状态对照图生成；原边界断言已迁入 IconBoundaryTests。直接编译时需带入 Localization、State、OutputDevice、IconTransition、WiFiIcon 和 IconRenderer 源码 |
| [RenderSettings.swift](Tools/RenderSettings.swift) | 按需导出三页设置预览；全部 27 组矩阵及布局 / 像素断言已纳入 SettingsLayoutTests。链接 Debug Combo 模块，在独立测试 Bundle 内复制本地化与品牌资源 |
| [check-app-lifecycle.py](Tools/check-app-lifecycle.py) / [AppLifecycleCheck.swift](Tools/AppLifecycleCheck.swift) | 复制 Debug App 到临时独立 bundle，执行真实 `ComboApp.main()`，检查完成引导、首次引导及 `--settings` 启动，菜单、尺寸、Dock 激活策略、最小化、重新打开回调和即时语言切换；只修改临时包及其独立偏好域，不操作系统音量 / 网络控制 |
| [LiveState.swift](Tools/LiveState.swift) | 实机读取、观察器、真实设备静音变化与退出清理，以及真实能耗模式的同值请求；阈值通知、模拟音量提示检查已迁入 StoreIsolationTests；菜单权限检查随功能移除，不能当作纯只读工具自动运行 |
| [MediaPlaybackWatch.swift](Tools/MediaPlaybackWatch.swift) | 真实媒体 helper 的 12 秒轮询观察；与 `Combo/Audio/MediaPlayback.swift` 一起编译，运行参数为 `--watch <helper路径>`，不进入默认回归 |
| [MenuDiagnostics.swift](Tools/MenuDiagnostics.swift) | 手动只读扫描 MenuBarAgent、控制中心和系统菜单栏的 AX 菜单信息；不加入 App、不点击、不修改布局、不自动请求权限 |
| [airpods-live-check.py](Tools/airpods-live-check.py) | 默认读取真实 AirPods helper；显式 `--write` 测试设置切换和恢复，需开展设备验证时使用 |
| [SparkleFeedCheck.swift](Tools/SparkleFeedCheck.swift) | 线上 HTTPS 清单检查；和 AppUpdater 源码编译到含 feed、公钥及 Sparkle 的独立测试 Bundle，不创建安装会话 |
| [check-sparkle-install.py](Tools/check-sparkle-install.py) | 用真实 Release 副本与回环源验证安装；调用同目录的 [SparkleInstallCheck.swift](Tools/SparkleInstallCheck.swift)，只修改临时隔离包 |

已迁移的图标渲染产物保存为 `.xcresult` 附件，可在 Xcode 的测试结果中查看；独立渲染工具仍输出到 `build/`。真实权限、硬件、系统版本和干净 Mac 的首次安装／更新体验需要另行验收，工具编译通过不等于这些行为已经验证。

## 菜单访问诊断

在仓库根目录编译并按需运行，不需要构建或链接 Combo：

```sh
mkdir -p build/tools
DEVELOPER_DIR="${COMBO_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun swiftc -parse-as-library Tests/Tools/MenuDiagnostics.swift -o build/tools/menu-diagnostics
build/tools/menu-diagnostics --help
build/tools/menu-diagnostics
```

没有辅助功能权限时返回非零并停止，不弹授权窗口。需要时手动授权运行工具的终端或可执行文件；Combo 本身不再申请此权限。保留原扫描边界：单次 AX 消息 0.2 秒，每个来源约 5 秒、深度最多 4 层；MenuBarAgent 最多 60 个节点，其他来源最多 120 个节点。命中时间或节点上限时不采用结果；节点候选和声明的点击能力不证明实际可操作。

`python3 Tests/Tools/check-menu-diagnostics.py` 编译工具并验证帮助和非法参数路径，不读取桌面、不请求权限。真实扫描需手动执行，不进入 `verify.sh`。

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

更新产物版本防护检查仍在发布模块：`python3 Releases/updates/test-prepare-update.py`。打包与候选准备测试独立运行；发布流程见 [更新维护](../docs/release/updates.md)。

`App/AppUpdaterTests.swift` 已纳入 Swift Testing 自动入口，验证 Debug 不启动更新、失败保留成功时间、成功时间持久保存。真实网络清单与安装仍由按需工具验证。

使用真实 Release App 与官方 Sparkle 工具运行隔离安装测试：

```sh
python3 Tests/Tools/check-sparkle-install.py --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
python3 Tests/Tools/check-sparkle-install.py --invalid-signature --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
```

`SPARKLE_DIR` 指向同时含 `Sparkle.framework` 与 `bin/sign_update` 的目录，签名使用本机钥匙串 `combo-updates` 账户。仅隔离回环测试 Bundle 关闭 ATS；正式配置保持 HTTPS。测试结束删除临时包，不修改原 App，不上传正式 appcast。正向检查验证替换与嵌套签名，负向检查验证错误签名拒绝；标准窗口自重启与干净 Mac 首次下载仍需另验收。
