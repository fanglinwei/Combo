# 测试与检查入口

在仓库根目录运行 `./verify.sh`：构建应用，执行 25 个自动检查入口，再验证签名和品牌资源。测试按功能模块分类；统一入口、检查顺序及输出位置 `build/checks/` 保持不变。

```sh
./verify.sh
# 当前无 Developer ID 的本地构建使用明确的 ad-hoc 覆盖：
./verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

## 自动回归

| 模块 | 覆盖内容 | 文件 |
| --- | --- | --- |
| App | 状态规则、更新状态、应用菜单、本地化、引导状态和品牌资源 | [main.swift](App/main.swift), [AppUpdaterCheck.swift](App/AppUpdaterCheck.swift), [ApplicationMenuCheck.swift](App/ApplicationMenuCheck.swift), [LocalizationCheck.swift](App/LocalizationCheck.swift), [OnboardingCheck.swift](App/OnboardingCheck.swift), [check-brand.sh](App/check-brand.sh) |
| Audio | 默认输出、AirPods、AirPlay 路由与发现、媒体及 helper | [AirPlayDiscoveryCheck.swift](Audio/AirPlayDiscoveryCheck.swift), [AirPlayHelperCheck.m](Audio/AirPlayHelperCheck.m), [AirPlayRouteCheck.swift](Audio/AirPlayRouteCheck.swift), [AirPodsCheck.swift](Audio/AirPodsCheck.swift), [MediaPlaybackCheck.swift](Audio/MediaPlaybackCheck.swift), [MediaPlaybackHelperCheck.m](Audio/MediaPlaybackHelperCheck.m), [OutputDeviceCheck.swift](Audio/OutputDeviceCheck.swift) |
| Battery | 临时充满和高耗能应用 | [ChargeControlCheck.swift](Battery/ChargeControlCheck.swift), [EnergyAppsCheck.swift](Battery/EnergyAppsCheck.swift) |
| Network | Wi-Fi 与个人热点 | [HotspotControlCheck.swift](Network/HotspotControlCheck.swift), [WiFiControlCheck.swift](Network/WiFiControlCheck.swift) |
| Rendering | 图标状态／转场与播放音柱 | [IconTransitionCheck.swift](Rendering/IconTransitionCheck.swift), [MediaBarsCheck.swift](Rendering/MediaBarsCheck.swift) |
| Views | 面板、详情反馈、设置、引导界面及面板本地化 | [DetailFeedbackCheck.swift](Views/DetailFeedbackCheck.swift), [OnboardingDesignCheck.swift](Views/OnboardingDesignCheck.swift), [PanelDesignCheck.swift](Views/PanelDesignCheck.swift), [PanelDismissCheck.swift](Views/PanelDismissCheck.swift), [PanelLocalizationCheck.py](Views/PanelLocalizationCheck.py), [PanelMotionCheck.swift](Views/PanelMotionCheck.swift), [SettingsPreferencesCheck.swift](Views/SettingsPreferencesCheck.swift) |

[Fixtures/WiFiReference.png](Fixtures/WiFiReference.png) 是图标检查的像素基准，不是可随意删除的预览图。`App/main.swift` 保留顶层 Swift 状态检查入口；其它检查沿用原有独立可执行程序方式，不新增测试框架或 Xcode target。

## 按需工具

这些工具不纳入 `verify.sh`，模拟回归不能替代它们的视觉、设备或网络覆盖。

| 文件 | 用途与操作范围 |
| --- | --- |
| [RenderIcons.swift](Tools/RenderIcons.swift) | 图标圆头、充电／低电颜色边界断言及演示状态对照图；直接编译时需带入 Localization、State、OutputDevice、IconTransition、WiFiIcon 和 IconRenderer 源码 |
| [RenderSettings.swift](Tools/RenderSettings.swift) | 六页设置在语言、主题、外观、尺寸、较大字号和高对比环境下的渲染；链接 Debug Combo 模块，在独立测试 Bundle 内复制本地化与品牌资源 |
| [LiveState.swift](Tools/LiveState.swift) | 实机读取、观察器、权限拒绝指引、音量事件续期和退出清理；还会临时修改电量阈值偏好并恢复，以及调用真实能耗模式的同值请求，不能当作纯只读工具自动运行 |
| [airpods-live-check.py](Tools/airpods-live-check.py) | 默认读取真实 AirPods helper；显式 `--write` 测试设置切换和恢复，需开展设备验证时使用 |
| [SparkleFeedCheck.swift](Tools/SparkleFeedCheck.swift) | 线上 HTTPS 清单检查；和 AppUpdater 源码编译到含 feed、公钥及 Sparkle 的独立测试 Bundle，不创建安装会话 |
| [check-sparkle-install.py](Tools/check-sparkle-install.py) | 用真实 Release 副本与回环源验证安装；调用同目录的 [SparkleInstallCheck.swift](Tools/SparkleInstallCheck.swift)，只修改临时隔离包 |

渲染产物仍输出到 `build/`。真实权限、硬件、系统版本和干净 Mac 的首次安装／更新体验需要另行验收，工具编译通过不等于这些行为已经验证。

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

能耗同值请求通常不写入，但读取后系统状态可能改变，不能保证零写操作；电量阈值偏好也会暂存和恢复。运行前确认当前机器适合这次验证。

## Sparkle 安装检查

更新产物版本防护检查仍在发布模块：`python3 Releases/updates/test-prepare-update.py`。打包与候选准备测试不在这次目录迁移范围内；发布流程见 [更新维护](../docs/release/updates.md)。

`App/AppUpdaterCheck.swift` 已纳入自动入口，验证 Debug 不启动更新、失败保留成功时间、成功时间持久保存。真实网络清单与安装仍由按需工具验证。

使用真实 Release App 与官方 Sparkle 工具运行隔离安装测试：

```sh
python3 Tests/Tools/check-sparkle-install.py --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
python3 Tests/Tools/check-sparkle-install.py --invalid-signature --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
```

`SPARKLE_DIR` 指向同时含 `Sparkle.framework` 与 `bin/sign_update` 的目录，签名使用本机钥匙串 `combo-updates` 账户。仅隔离回环测试 Bundle 关闭 ATS；正式配置保持 HTTPS。测试结束删除临时包，不修改原 App，不上传正式 appcast。正向检查验证替换与嵌套签名，负向检查验证错误签名拒绝；标准窗口自重启与干净 Mac 首次下载仍需另验收。
