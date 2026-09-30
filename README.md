# Combo · 电池、Wi‑Fi、声音三合一预览版

一个菜单栏入口展示电池、当前网络路径与声音状态。系统图标由用户在 macOS 菜单栏设置中手动隐藏；Combo 不再使用会连自身图标一起隐藏的私有折叠实验。

## 图标会怎样变化

| Wi-Fi 连接中 | 充电 + 播放 | AirPods 播放时调音量 |
| :---: | :---: | :---: |
| ![Wi-Fi 连接时中央图形放大并脉冲](docs/assets/states/connecting.gif) | ![充电绿环、闪电和播放音柱同时显示](docs/assets/states/charging.gif) | ![音量数字短暂出现，随后恢复 AirPods 和播放音柱](docs/assets/states/adjusting.gif) |
| 中央放大并脉冲，等待连接结果。 | 电量、充电和媒体状态组合在一枚图标里。 | 音量提示结束后，恢复 AirPods 和播放动效。 |

[查看完整状态与变化](docs/combo-current-states.md)。

## 运行

用 Xcode 打开 `Combo.xcodeproj` 并运行 Combo scheme，或在终端执行 `./build.sh` 后打开 Xcode 的 DerivedData/Build/Products/Debug/Combo.app。Debug 运行时自动打开设置窗口，Release 首次启动时打开；关闭窗口后菜单栏图标继续运行；点击菜单栏图标可操作三项功能。退出使用设置页或弹窗中的“退出 Combo”，也可按 Command-Q。

## 可以体验

- 电池电量、电源来源、充电状态、当前充电上限、低电量模式及系统提供的粗略健康状态；主面板可经系统授权切换当前电源类型的能耗模式，保留另一电源类型的设置；确认手动上限暂停充电时可“立即充满电”，临时恢复由 macOS 管理；电池设置和活动监视器入口。
- Wi‑Fi 电源开关、当前 SSID、已知网络与可展开的其他网络、RSSI 信号等级和基础安全提示；按需定位授权后扫描与连接。个人热点显示手机名称、电量和蜂窝信号等级，点击后转交系统 Wi‑Fi 设置连接；企业认证也使用系统设置。点击已知网络时可按需使用系统钥匙串密码；设置中提供请求开关与授权说明。手动输入的密码默认在连接成功后存入本机 Combo 钥匙串，可取消记住或删除，不上传服务器。
- 系统默认输出设备选择、主通道/左右声道音量与静音控制；AirPods 左右耳电量、通透/自适应/降噪、对话感知已接入。设备列表支持展开/收起耳机选项；不监控空间音频，完整设置及 AirPlay 保留系统入口。实机范围与验证命令见 [声音与 AirPods](docs/airpods-audio-feasibility.md)。
- 「通用」页的手动隐藏区域直达 macOS“菜单栏”设置，读取三项勾选状态；无法读取时明确显示“无法判断”。用户自行关闭系统图标。
- 设置窗口包含通用、外观与动效、系统菜单整合、媒体来源、实验性项目、关于与帮助六组导航；外观页可独立选择蓝色、紫色或暖金色主题及跟随系统、浅色或深色模式，并预览示例场景，媒体页显示播放检测状态并可演示音柱。
- 记录首次读到的三项状态，正常退出时尝试恢复；失败会提示手动检查，异常退出后下次启动提示恢复。
- 登录时启动调用系统 SMAppService，只有用户主动开启才注册。

## 尚未接入与技术限制

- 充电上限后台只读 `pmset -g battlimit`，只展示有效且一致的手动限制，读取失败、未知策略或不同上限显示无法判断；不是持久偏好值。到达上限提示还依赖 IORegistry 的社区已观察字段 `NotChargingReason` bit 24，跨系统版本可能不可用。无管理员 helper，不修改充电控制；参考 [Ampere](https://github.com/az-code-lab/ampere/blob/master/Sources/Shared/NativeChargeLimit.swift) 和 [OpenDente](https://github.com/killerk3emstar/OpenDente/blob/main/OpenDente/Models/BatteryState.swift)。
- 「实验性项目」收纳自动折叠预选、8 秒单项实验、立即恢复和原生菜单诊断。自动折叠仍未启用：旧私有接口会同时隐藏 Combo。系统图标设置会持久保存；恢复依赖辅助功能权限和系统设置界面，异常退出后不能保证自动恢复。
- Wi‑Fi 网络名称需要定位权限；本地 ad-hoc 重新编译可能使权限授权失效。连接网络、切换输出设备和设置状态恢复仍需在不同硬件与权限状态下实机回归。
- 媒体检测枚举系统注册的媒体客户端并聚合播放状态，任一客户端播放时启用原有底部音柱；暂停、停止或读取失败时恢复圆点，音量为零或静音时优先显示原有静音图标。主面板读取当前媒体的标题、作者、来源和可用封面，提供上一首、播放／暂停、下一首；暂停后保留媒体卡，直到系统媒体会话结束。锁屏/休眠时停止检测，唤醒后恢复。不录音、不读取网页。
- 媒体读取使用隔离的 `MediaPlaybackHelper.m` 与系统 Perl，参考 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) 的加载机制；不是公开 API 的兼容性承诺。每秒查询一次全部已注册媒体客户端，单次超时 2 秒，宿主设 5 秒看门狗并处理退出/失效。未向系统注册的播放器不能识别；每个客户端查询默认播放器，多播放器子会话仍需实机验证。普通通知音不注册媒体会话；已显式排除 FaceTime、微信、QQ、Teams、Zoom、Discord 等通讯来源，但浏览器内通话及未知通讯应用仍需验证，不能保证语义分类覆盖所有应用。
- 媒体检查：`Tests/MediaPlaybackHelperCheck.m` 覆盖多客户端聚合、暂停/停止/中断、通讯来源排除与 JSON 布尔类型；`Tests/MediaPlaybackCheck.swift` 覆盖解码和缺失 helper，使用 `./verify.sh` 运行。
- 日期折叠未实现；不修改系统时钟设置。
- 菜单栏组合图标的 Wi-Fi 图形仅代表连接介质；面板内网络列表另用 RSSI 显示信号等级。默认路径使用 NWPath 可用性及 SystemConfiguration IPv4/IPv6 接口；介质冲突、未映射接口和隧道返回不确定。没有互联网探测，也不宣称代表全机所有流量。
- 中央内容自动显示网络、电量或静音状态，不提供手动选择，也不显示日期或输出设备；设备切换不触发中央提示。
- 电池与默认音频输出/音量/静音使用系统事件监听；电源和播放中音量提示缩小完成后保持 5 秒，连续音量变化续期；已移除日期刷新计时器。
- 图标遵循状态总览的几何与颜色；菜单栏、面板和设置共用绘图，低电量保留红色短弧。
- 仅构建当前机器架构（本次 arm64），本地 ad-hoc 签名，无 Developer ID 公证；不作为公开分发包。

## 构建与检查

```sh
./build.sh
./verify.sh
```

`build.sh` 调用 Xcode 27 构建 Debug 应用；`COMBO_CONFIGURATION=Release ./build.sh` 构建 Release。目标系统仍为 macOS 26.0。`verify.sh` 单独运行原有状态、Helper、图标与签名检查。Xcode 从 GitHub 获取 InjectionNext 2.0.1 和 Inject 1.6.0；`Combo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 固定版本。首次构建需要访问 GitHub，包括 InjectionNext 的 Git 子模块。

### SwiftUI 热重载

安装 [InjectionNext 2.0.1](https://github.com/johnno1962/InjectionNext/releases/tag/2.0.1) 到 `/Applications`，退出 Xcode，然后从 InjectionNext 菜单栏图标选择 **Launch Xcode**。在 Xcode 里运行 Combo 的 Debug scheme；InjectionNext 图标变橙色表示应用已连接。若保存文件后没有检测到改动，在 InjectionNext 中选择 **...or Watch Project** 并指定仓库根目录。保存 `Combo/Views.swift` 或 `Combo/Icon.swift` 中的 SwiftUI 视图实现后，InjectionNext 会编译改动并注入运行中的应用。属性布局、函数签名等结构性修改仍需重新构建运行。Debug 配置含 `-interposable`，并关闭沙盒与强化运行时以允许代码注入；Release 不设置注入链接参数。

构建、状态测试与代码签名校验通过；在 macOS 27.0 开发机检查三合一面板与 Wi‑Fi、声音、电池系统设置跳转。Wi‑Fi 实际连接、输出设备切换、钥匙串写入、辅助功能读取及退出恢复尚未完成实机验证。

2026-09-24 Wi‑Fi 面板：普通网络留在 Combo，个人热点现通过只读发现展示手机名称、电量和蜂窝信号等级，点击直达系统 Wi‑Fi 设置（本机 AX 点击系统菜单项未能确认展开，因此不启用这条路径）。系统设置中已确认个人热点列表可见；示例数据检查了列表展开、密码表单与企业认证提示。`Tests/WiFiControlCheck.swift` 覆盖同名不同安全类型隔离、保留当前 BSSID、RSSI 未知值与基础安全分类，已接入构建。扫描仅在打开面板或手动刷新时进行，面板活跃期间每 10 秒刷新连接状态。已知网络来自 CoreWLAN 配置；点击已知的普通加密网络时，可用 `CWKeychainFindWiFiPassword` 按所选 SSID 获取系统密码，仅用于此次连接，不复制到 Combo 存储；旧版 Combo 仅按名称存储的密码不会自动复用，新条目按安全类型和名称保存，旧条目保留。低安全性提示仅基于协议类型，不承诺与系统全部规则一致；本轮没有切换真实网络或写入真实 Wi‑Fi 密码。

2026-09-24：补齐电池电源与上限展示，测试覆盖重复/失效/冲突限制及未知状态；能耗模式完成适配器 0 → 1 → 0 的实际写入与回读，电池模式保持不变。“立即充满电”已加入正式面板；本机补测单独临时解除手动上限即可开始充电，优化充电仍保持开启，系统显示将在 06:00 恢复 80% 上限。界面不承诺固定恢复时刻，暂不支持仅优化充电暂缓。超时、请求失败、状态变化和重复点击有自动化检查；跨系统兼容及实际到时恢复仍未验证，详见 [电池操作记录](docs/battery-controls.md)。

源码：`Combo/State.swift` 纯显示规则；`Store.swift` 系统数据；`Icon.swift` 共享图标绘制；`Views.swift` 面板与设置；`main.swift` 应用生命周期。

品牌：应用图标与设置中的 Logo 使用电量弧、无线连接和音量四点，强调色 `#148C78`；菜单栏仍使用原有实时单色状态图标。矢量资源与配色说明见 [`docs/assets/brand/README.md`](docs/assets/brand/README.md)。构建会生成应用图标并打包到 `.app`，不依赖 Pillow。

完整需求：[设置规格](docs/combo-settings.md) · [实施文档](docs/combo-implementation.md)。

## 以下为旧版验证记录

下面记录此前 0.2 预览版与私有折叠实验的观察；六组设置和演示场景已恢复，试验按钮仍不代表当前三合一功能。

### 图标样式对齐

以用户提供的状态总览和 `docs/assets/render_design.py` 为依据，统一 240° 电量弧、Arial 常规数字、Wi-Fi/耳机轮廓、四点/音柱、静音叉号、低电量红色与充电留空标记。设置预览现提供 16 个状态，中央按 P4 事件提示 > P3 Wi-Fi 连接中 > P2 其他常驻状态 > P1 Wi-Fi 正常选择；一般升／同级播放切换动画，降级直接恢复；网络连接结束会先收尾并停留 2 秒，再缩小，缩小后保留结果 5 秒再恢复常驻状态。自动显示、静音和临时音量规则见 [状态优先级](docs/combo-settings.md#31-中央状态优先级2026-09-24)。

当前绘图输出：[原生 16 状态对照图](docs/assets/combo-native-icon-review.png)。APP 图标保留原版；Wi-Fi 在菜单栏、设置、网络列表和透明 Logo 中统一为两条加粗圆头弧线加圆润倒三角，弧线间隙收紧，保留信号强弱及关闭、异常、连接中状态。下列命令将当前 16 状态对照图输出到 `build/combo-priority-review.png`：

```sh
xcrun swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -swift-version 5 -parse-as-library Combo/State.swift Combo/Icon.swift Tests/RenderIcons.swift -o build/render-icons
./build/render-icons
```

对照图直接调用应用共享绘图代码，不以参考 PNG 替代应用图标。平台文字抗锯齿与原 Pillow 绘制存在栅格差异；几何参数、字体和配色按参考统一。

### 0.2 运行验证

- `./build.sh`：构建与纯规则测试通过，最低部署目标 26.0。
- 本机只读运行检查：电池/音量值有效、网络返回 Wi-Fi、电池与音频事件注册成功。
- 连续音量提示计时检查：第二次变化续期，最终到期清除，退出释放监听。
- 设置界面已检查 PREVIEW 0.2 和新增检测入口；点击检测得到“需要辅助功能授权”，没有触发权限弹窗或修改菜单栏。
- 宿主仍为 macOS 27.0；没有模拟拔插、改网络、改系统音量或启用登录项。事件注册成功不等于全部外部设备和 macOS 26 版本已验收。

复现只读运行检查：

```sh
xcrun swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -swift-version 5 -parse-as-library Combo/State.swift Combo/NetworkStatus.swift Combo/WiFiControl.swift Combo/HotspotControl.swift Combo/MenuBarSetup.swift Combo/MenuDiagnostics.swift Combo/MenuFoldExperiment.swift Combo/PowerModeControl.swift Combo/ChargeControl.swift Combo/EnergyApps.swift Combo/Store.swift Tests/LiveState.swift -o build/live-state-check
./build/live-state-check
```

菜单继续验证的操作入口：Combo 设置 → 实验性项目 → 授权辅助功能。用户在系统设置完成授权后返回点击“检查菜单访问”。授权并不自动启用折叠；只读检测也不能代替菜单打开、关闭和归位验证。

### 辅助功能授权引导（2026-09-23）

实验性项目中的“授权辅助功能…”现在打开单页引导；未授权时点击“检查菜单访问”也会进入该页。页面说明权限范围、系统设置路径、找不到 Combo 时的添加方式及当前应用路径。用户主动点击“打开系统设置并授权”才请求系统提示并尝试打开辅助功能设置；跳转失败可按页面路径手动操作。

返回 Combo 时自动刷新授权状态，也可以点击“重新检查”。已授权显示“继续检测”，只有点击后才执行只读菜单检测。可按 Escape 或“稍后再说”关闭；授权不会自动开启折叠。

验证：构建与状态测试通过；运行检查覆盖权限状态刷新，并在测试进程未授权时验证引导出现且不启动菜单扫描。没有替用户更改权限。电脑控制工具反复报告应用变化，未完成新引导页的端到端视觉、跳转与授权成功回流验证。当前已运行的旧版本需要退出后重新打开构建产物才能加载本次修改。

### 引导页实机复验

2026-09-23 后续复验：已正常退出旧进程并启动当前构建。在设置中点击“检查菜单访问”，应用显示未授权引导，截图确认正文、路径、三个按钮完整可见，辅助功能树可识别各按钮。当前运行的 Combo 仍返回未授权；没有执行系统菜单扫描或开启权限。系统授权成功回流、菜单定位与展开仍需实际授权后验证。

### 系统开关已开启，但 Combo 检测未通过

2026-09-23：用户截图显示 Combo 开关开启，应用内重新检查及不改构建的退出重启后，AXIsProcessTrusted 仍为 false。故不是仅 UI 缓存问题。当前 ad-hoc 签名的 designated requirement 是精确 cdhash；重新构建后可能与旧授权不匹配。未能读取受保护的 TCC 记录，因此旧记录不匹配是高概率原因，尚未证实为唯一根因。

先退出并重启；若仍无效，在系统权限列表移除旧 Combo，用当前运行路径重新添加并开启。macOS 27 的用户截图中页面名称为“设备控制和数据访问”。不要重置整个 TCC 或给其他进程额外权限。

以下是 2026-09-23 的旧构建记录，现已由上方 Xcode 工程取代：当时的构建脚本拒绝覆盖正在运行的输出应用，避免运行中代码与磁盘签名不一致。权限验证使用固定签名身份；不设置时采用 ad-hoc。身份首次切换后也可能需要重新授权。

本次修改在 `build/validation/Combo.app` 单独构建验证，未覆盖当时运行的 `build/Combo.app`；验证副本不应当作当前已授权应用使用。引导文案改成“系统尚未允许当前进程访问”，补充开关已开启时的排查步骤。未修改系统权限、未清空 TCC。旧构建防覆盖检查脚本已随 Xcode 迁移移除。

Apple 签名身份依据：https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

### 授权后系统菜单检测结果

2026-09-23，原项目路径中运行的 Combo 辅助功能权限已生效。只读检查 Control Center 和 SystemUIServer 均未取得 AX 菜单栏根项（两个根属性均返回 `kAXErrorNoValue`）；这不是“尚未授权”，也不能据此排除其他访问路径。方案对照、已确认边界和后续验证顺序见 [系统菜单整合实施计划](docs/menu-integration-plan.md)。

### macOS 27 单项实验（feature 分支）

MenuBarAgent 的辅助功能树在本机暴露了 Wi-Fi、声音、电池的独立标识。此前逐项 8 秒测试观察到目标项约第 3 秒从树中消失，另外两项保留；计时结束后恢复，“立即恢复”也可提前释放电池限制。后续实测发现 Combo 图标也被折叠，违反恢复入口始终可见的要求，因此三个实验按钮现已暂停。`AXPress` 与按 AX 坐标点击均未观察到原生菜单；总开关仍禁用。详细记录见 [系统菜单整合实施计划](docs/menu-integration-plan.md)。

2026-09-24 个人热点：已接入 `Sharing.framework` 只读发现；打开面板开始，关闭面板、屏幕休眠或关闭 Wi-Fi 停止。显示真实手机名称、电量及蜂窝信号原始等级，未知 5G／LTE 映射隐藏；空结果、读取失败和重试均有对应状态。私有 ABI 目前仅验证并支持 macOS 27.0 build `26A428`，其他版本保留系统设置入口。完整构建、热点自动检查及本机面板读取/跳转验证通过，未连接手机热点。详见 [热点验证记录](docs/mobile-hotspot-api-feasibility.md)。

2026-09-24 Wi‑Fi 钥匙串：设置 → 系统菜单整合 → Wi‑Fi 提供“使用系统保存的 Wi‑Fi 密码”（默认开启）和“钥匙串授权与隐私”入口。开关只控制是否请求，不能代表 macOS 已授权；系统按项目决定是否弹窗。仅在用户域找不到项目时尝试系统域，拒绝或取消不继续尝试，也不自动连接，本次运行停止再请求，可由设置中的“允许下次请求授权”恢复。手动密码默认在连接成功后保存为本机 Combo 钥匙串项目，可取消勾选；系统密码不另存，网络名称及密码没有上传路径。关闭开关不撤销系统已授予的访问权限。测试覆盖取消、重复点击、偏好持久化和授权中修改偏好等分支；真实系统授权与网络切换仍需用户实机验证。
