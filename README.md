# Combo · 原生预览版 0.2

用于先评审组合菜单栏与设置界面的本地版本，不是首版全部功能已完成的发行包。

## 运行

双击 `build/Combo.app`。首次启动打开设置窗口，关闭窗口后菜单栏图标继续运行；点击菜单栏图标可查看状态和重新打开设置。退出使用“通用 → 退出 Combo”或 Command-Q。

## 可以体验

- 底部开口电量圆弧、中央内容、四点音量、固定播放音柱。
- 本机电池/充电状态、默认网络路径类型、系统默认输出设备及主音量。
- 设备支持时可在点击面板调节主音量和静音；不支持时禁用控制。
- 五组原生设置：通用、图标与动效、系统菜单整合、媒体来源、关于与帮助。
- 有线中央内容及动效开关持久化；三项折叠预选持久化但不执行。
- “图标与动效”使用示例预览；“通用 → 菜单栏数据”可切换真实菜单栏的演示场景。演示不持久化，悬停和面板标明演示。
- 登录时启动调用系统 SMAppService，只有用户主动开启才注册；失败如实显示。未在本次验证中开启用户登录项。

## 尚未接入与技术限制

- 不折叠任何系统图标。设置页新增只读菜单检测及用户主动授权入口；不自动弹出授权。当前构建已获辅助功能授权，原生菜单唤起与恢复仍待 macOS 27 兼容性验证。
- Safari/Chrome 扩展、网易云/QQ 适配尚未实现；真实播放不会驱动音柱，只能用演示场景查看动画。
- 日期折叠未实现；不修改系统时钟设置。
- Wi-Fi 图形仅代表连接介质，没有 RSSI 信号格数。使用 NWPath 可用性及 SystemConfiguration IPv4/IPv6 默认接口；介质冲突、未映射接口和隧道返回不确定。没有互联网探测，也不宣称代表全机所有流量。
- 输出设备按类型采用自绘通用轮廓；总览耳机示例已对齐，实际 AirPods 型号匹配尚未实现。
- 电池与默认音频输出/音量/静音使用系统事件监听；音量变化触发 2 秒提示，后续变化续期。日期每分钟刷新，不再每 3 秒轮询硬件。
- 图标遵循状态总览的几何与颜色；菜单栏、面板和设置共用绘图，低电量保留红色短弧。
- 仅构建当前机器架构（本次 arm64），本地 ad-hoc 签名，无 Developer ID 公证；不作为公开分发包。

## 构建与检查

```sh
./build.sh
```

使用已安装的 Swift 编译器及 `/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk`，部署目标 macOS 26.0，无第三方依赖。编译前运行 `Tests/main.swift` 的音量边界及显示优先级测试。

本次构建、状态测试与代码签名校验通过；在 macOS 27.0 开发机启动并检查原生设置布局、可访问性控件、场景切换。macOS 26 真机、登录项授权、外部音频设备写入、完整节能及系统菜单整合不在已通过范围。

源码：`Combo/State.swift` 纯显示规则；`Store.swift` 系统数据；`Icon.swift` 共享图标绘制；`Views.swift` 面板与设置；`main.swift` 应用生命周期。

品牌：应用图标与设置中的 Logo 使用电量弧、无线连接和音量四点，强调色 `#148C78`；菜单栏仍使用原有实时单色状态图标。矢量资源与配色说明见 [`docs/assets/brand/README.md`](docs/assets/brand/README.md)。构建会生成应用图标并打包到 `.app`，不依赖 Pillow。

完整需求：[设置规格](docs/combo-settings.md) · [实施文档](docs/combo-implementation.md)。

## 图标样式对齐

以用户提供的状态总览和 `docs/assets/render_design.py` 为依据，统一 240° 电量弧、Arial 常规数字、Wi-Fi/耳机轮廓、四点/音柱、静音叉号、低电量红色与充电留空标记。设置预览提供全部 12 个状态。

实际绘图输出：[原生 12 状态对照图](docs/assets/combo-native-icon-review.png)。重绘：

```sh
xcrun swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -swift-version 5 -parse-as-library Combo/State.swift Combo/Icon.swift Tests/RenderIcons.swift -o build/render-icons
./build/render-icons
```

对照图直接调用应用共享绘图代码，不以参考 PNG 替代应用图标。平台文字抗锯齿与原 Pillow 绘制存在栅格差异；几何参数、字体和配色按参考统一。

## 0.2 运行验证

- `./build.sh`：构建与纯规则测试通过，最低部署目标 26.0。
- 本机只读运行检查：电池/音量值有效、网络返回 Wi-Fi、电池与音频事件注册成功。
- 连续音量提示计时检查：第二次变化续期，最终到期清除，退出释放监听。
- 设置界面已检查 PREVIEW 0.2 和新增检测入口；点击检测得到“需要辅助功能授权”，没有触发权限弹窗或修改菜单栏。
- 宿主仍为 macOS 27.0；没有模拟拔插、改网络、改系统音量或启用登录项。事件注册成功不等于全部外部设备和 macOS 26 版本已验收。

复现只读运行检查：

```sh
xcrun swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -swift-version 5 -parse-as-library Combo/State.swift Combo/NetworkStatus.swift Combo/MenuDiagnostics.swift Combo/Store.swift Tests/LiveState.swift -o build/live-state-check
./build/live-state-check
```

菜单继续验证的操作入口：Combo 设置 → 系统菜单整合 → 授权辅助功能。用户在系统设置完成授权后返回点击“检查菜单访问”。授权并不自动启用折叠；只读检测也不能代替菜单打开、关闭和归位验证。

## 辅助功能授权引导（2026-09-23）

系统菜单整合中的“授权辅助功能…”现在打开单页引导；未授权时点击“检查菜单访问”也会进入该页。页面说明权限范围、系统设置路径、找不到 Combo 时的添加方式及当前应用路径。用户主动点击“打开系统设置并授权”才请求系统提示并尝试打开辅助功能设置；跳转失败可按页面路径手动操作。

返回 Combo 时自动刷新授权状态，也可以点击“重新检查”。已授权显示“继续检测”，只有点击后才执行只读菜单检测。可按 Escape 或“稍后再说”关闭；授权不会自动开启折叠。

验证：构建与状态测试通过；运行检查覆盖权限状态刷新，并在测试进程未授权时验证引导出现且不启动菜单扫描。没有替用户更改权限。电脑控制工具反复报告应用变化，未完成新引导页的端到端视觉、跳转与授权成功回流验证。当前已运行的旧版本需要退出后重新打开构建产物才能加载本次修改。

### 引导页实机复验

2026-09-23 后续复验：已正常退出旧进程并启动当前构建。在设置中点击“检查菜单访问”，应用显示未授权引导，截图确认正文、路径、三个按钮完整可见，辅助功能树可识别各按钮。当前运行的 Combo 仍返回未授权；没有执行系统菜单扫描或开启权限。系统授权成功回流、菜单定位与展开仍需实际授权后验证。

## 系统开关已开启，但 Combo 检测未通过

2026-09-23：用户截图显示 Combo 开关开启，应用内重新检查及不改构建的退出重启后，AXIsProcessTrusted 仍为 false。故不是仅 UI 缓存问题。当前 ad-hoc 签名的 designated requirement 是精确 cdhash；重新构建后可能与旧授权不匹配。未能读取受保护的 TCC 记录，因此旧记录不匹配是高概率原因，尚未证实为唯一根因。

先退出并重启；若仍无效，在系统权限列表移除旧 Combo，用当前运行路径重新添加并开启。macOS 27 的用户截图中页面名称为“设备控制和数据访问”。不要重置整个 TCC 或给其他进程额外权限。

构建现在拒绝覆盖正在运行的输出应用，避免运行中代码与磁盘签名不一致。权限验证应显式使用同一开发者签名身份：`COMBO_SIGNING_IDENTITY='证书 SHA-1' ./build.sh`；不设置仍为 ad-hoc，会打印权限失效风险。不能随意选择钥匙串中其他人的证书。身份首次切换后也可能需要重新授权。

本次修改在 `build/validation/Combo.app` 单独构建验证，未覆盖正在运行的 `build/Combo.app`；验证副本不应当作当前已授权应用使用。引导文案改成“系统尚未允许当前进程访问”，补充开关已开启时的排查步骤。未修改系统权限、未清空 TCC。`zsh Tests/check-build-guard.sh` 验证运行中构建被拒绝且原二进制哈希不变。

Apple 签名身份依据：https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

## 授权后系统菜单检测结果

2026-09-23，当前构建的辅助功能权限已生效。只读检查 Control Center 和 SystemUIServer 均未取得 AX 菜单栏根项（两个根属性均返回 `kAXErrorNoValue`）；这不是“尚未授权”，也不能据此排除其他访问路径。当前构建仍未实现原生菜单展开或自动折叠。方案对照、已确认边界和后续验证顺序见 [系统菜单整合实施计划](docs/menu-integration-plan.md)。
