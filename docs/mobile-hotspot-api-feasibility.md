# 手机个人热点 API 可实现性调研

## Combo 面板接入完成（2026-09-24）

样式更新：信号文字替换为四根底部对齐的圆角阶梯条，0–4 级分别点亮对应数量；电池采用横向轮廓及右侧凸起，内部居中显示整数（例如 `75`，省略百分号），淡色填充随电量变化。整行辅助功能仍朗读完整蜂窝等级和电量百分比，点击行为不变。已用实际 SwiftUI 组件检查 340 点宽度、浅色/深色、0–4 信号、0/5/25/75/100 电量及缺失字段的渲染。

个人热点已接入正式面板：`Combo/HotspotControl.swift` 在进程内动态创建只读发现会话，`PersonalHotspotSection` 展示手机名称、电量百分比及蜂窝信号原始等级。未确认映射的网络制式不显示，也不把信号等级转换成 Wi-Fi RSSI 或满格比例。电量仅接受 0–100 整数，蜂窝等级仅接受当前支持的 0–4 整数；其他值隐藏。

- 面板实际打开、屏幕活跃且 Wi-Fi 开启时开始；Popover 关闭、屏幕休眠、Wi-Fi 关闭或应用退出时停止并清空状态。
- 每次系统回调替换完整列表，按设备标识去重，同名不同设备保留；旧会话的迟到回调丢弃。
- 初次回调超过 10 秒显示“暂时无法读取手机信息”，可重试；正常空结果显示“未发现可用个人热点”。始终保留系统 Wi-Fi 设置入口。
- 点击手机仅复用系统 Wi-Fi 设置跳转，不调用启用或连接接口。设备标识只用于内存中的列表身份，不持久化或输出日志。
- 私有接口仍只开放本次验证的 macOS build `26A428`；其他系统版本回退到状态提示和系统设置入口。

验证：完整 `build.sh`、签名及资源检查通过；`Tests/HotspotControlCheck.swift` 覆盖字段异常、重复设备、设备移除、重复开始、停止、超时、能力缺失与旧回调。正式读取对象连续两次启停均发现真实手机。验证版面板 AX 树显示“轻舟已过万重山”、75% 电量及信号等级更新；点击后系统设置打开 Wi-Fi 页面，当前网络仍为 OVU。未切换真实网络。空/失败和设备移除通过自动检查验证，未通过关闭真实手机或 Wi-Fi 制造故障。

以下保留先前独立探针的验证记录。

## Combo 本机只读验证：可以获得手机状态

验证日期：2026-09-24；系统：macOS 27.0（26A428）。本节替代下文早期“仅使用 CoreWLAN”的方案建议。

### 原因与验证结果

Combo 当前的个人热点区域只是打开系统设置的按钮，没有手机发现会话、手机状态模型或状态展示。现有 CoreWLAN 扫描及 `nixpulvis/wifiscan` 不能提供截图中的手机电量、蜂窝信号和网络类型，因此仅接入普通 Wi-Fi 扫描无法补齐这些内容。

独立 Objective-C 探针动态加载系统私有 `Sharing.framework`，创建 `SFRemoteHotspotSession`，设置委托并调用 `startBrowsing`，从 `session:updatedFoundDevices:` 回调读取字段，10 秒后调用 `stopBrowsing`。初次试验与保存后的探针均收到相同设备数据：

| 字段 | 本机真实返回 | 解释边界 |
|---|---|---|
| deviceName | 轻舟已过万重山 | 与用户截图及系统 Wi-Fi 设置中的设备名称一致 |
| batteryLife | 75 | 电量字段；尚未与手机本身的百分比显示独立校准 |
| signalStrength | 4 | 蜂窝信号等级；不是 CoreWLAN 的 Wi-Fi RSSI，完整量程未核实 |
| networkType | 8 | 原始类型值；截图显示 5G，但本次未核实完整映射，不能直接硬编码 8 → 5G |
| cachedDevice | false | 系统返回的缓存标志 |
| lastSeen | 0 | 时间语义未核实，不转换为用户可见时间 |

本次探针没有调用热点启用、连接或网络切换方法，也没有添加 entitlement 或使用 root。系统设置观察到当前连接仍是 OVU。这里只证明当前机器和进程环境可读取，不代表沙盒应用、签名发行版、其他系统版本或所有手机都能读取。发现设备也不等于已验证其互联网可用性。

### 可复现命令与检查

源码：[personal-hotspot-query.m](../prototypes/personal-hotspot-query.m)。这是独立可运行的初期验证程序；正式面板已使用 Swift 读取对象接入，见首节。

```sh
xcrun clang -Wall -Wextra -fobjc-arc -framework Foundation prototypes/personal-hotspot-query.m -o /tmp/combo-hotspot-query
/tmp/combo-hotspot-query --self-test
/tmp/combo-hotspot-query
```

自检覆盖字段投影、缺失字段、错误类型，以及保留未知网络类型；不触发实际发现。实际发现运行约 10 秒，输出 JSON。退出码：0 收到回调（可能为空列表），2 系统版本或能力不匹配，3 超时未收到回调。原型限制为本次核实的系统 build，避免把旧 ABI 当成跨版本保证。

### 接入建议

保留普通 Wi-Fi 的现有逻辑；为个人热点区域增加独立的发现数据源，面板打开时浏览、关闭时停止。只显示真实返回且已确认含义的状态；缺失字段隐藏，未知网络类型先不显示制式文字。点击手机条目沿用现有 Wi-Fi 系统设置入口，由用户在系统界面连接。浏览能力不可用时保留系统设置入口。

正式集成仍需验证 Combo 进程中的回调、设备离开与重复更新、面板开关生命周期，以及电量、信号和网络制式显示映射。该段记录初期探针阶段；后续面板接入与验证见首节。

### 资料边界

旧版运行时头文件提供 [SFRemoteHotspotSession](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/Sharing.framework/SFRemoteHotspotSession.h)、[委托协议](https://github.com/nst/iOS-Runtime-Headers/blob/master/protocols/SFRemoteHotspotSessionDelegate.h) 和 [SFRemoteHotspotDevice](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/Sharing.framework/SFRemoteHotspotDevice.h) 的线索；本机再通过 Objective-C runtime 核对实际存在的类、方法和类型。这些是私有 API 的逆向资料，不是 Apple 对兼容性的承诺。

旧头文件中的 `cellularProtocolString` 在本机设备类上不存在。设备类存在 `networkTypeForIncomingType:` 转换方法；[Continuity 广播协议研究](https://github.com/furiousMAC/continuity/blob/master/messages/tethering_source.md) 的广播枚举不可直接套用为设备对象的 `networkType`。

---

## 当前需求澄清：只读取可用热点数据，不连接

用户已明确不需要连接。读取端已确认为 macOS Combo，目标是系统“个人热点”中的手机信息。下文早期热点开关调研保留作背景，不是当前实施建议。

- **macOS：公开 API 可实现 Wi-Fi 扫描。** `CWInterface.scanForNetworks(withSSID:includeHidden:)` 返回 `CWNetwork`；可读 SSID、BSSID、RSSI、信道，并查询支持的安全类型。不需要关联目标网络。[扫描 API](https://developer.apple.com/documentation/corewlan/cwinterface/scanfornetworks(withssid:includehidden:))、[CWNetwork](https://developer.apple.com/documentation/corewlan/cwnetwork)
- **权限：**现代 macOS 的 SSID 访问受定位服务授权限制。Apple DTS 明确说明了这一变更；授权与应用启动方式仍需在目标系统实测。[Apple DTS](https://developer.apple.com/forums/thread/732431?answerId=758114022)
- **GitHub 参考：**[nixpulvis/wifiscan](https://github.com/nixpulvis/wifiscan) 用 Swift + CoreWLAN 扫描，可输出 JSON，并记录应用包及定位授权的处理方式；本次未安装运行。
- **个人热点识别边界：**已广播的手机热点可以作为 Wi-Fi 接入点被扫描；CoreWLAN 的公开网络模型没有手机电量、蜂窝信号或可靠的“这是手机热点”字段。系统 Instant Hotspot 分组不能承诺通过普通扫描完整复刻。[CWNetwork 字段](https://developer.apple.com/documentation/corewlan/cwnetwork?changes=l_5)
- **谨慎使用蓝牙猜测：**[stevelacey/wifi-cli-macos](https://github.com/stevelacey/wifi-cli-macos/blob/main/wifi-scanner.swift) 将部分 Apple 蓝牙广播归入 hotspots；这是源码中的识别启发式，本次没有证据证明这些设备都可提供热点，不能当作准确热点清单。
- **Android：**`WifiManager.getScanResults()` 支持读取附近接入点，受定位权限、定位开关和扫描限流约束；返回值可能是旧扫描缓存。[官方扫描指南](https://developer.android.com/develop/connectivity/wifi/wifi-scan)
- **iOS：**普通 App 没有通用的附近 Wi-Fi 扫描 API；读取当前网络与枚举附近网络不同。[Apple TN3111](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)

早期普通接入点扫描建议（不适用于完整手机状态）：若读取端是 macOS，直接使用 CoreWLAN，输出名称、可选 BSSID、RSSI、信道和安全类型即可；无需先引入热点开关、连接、MDM 或 root 方案。扫描可见不代表已验证可以连接或访问互联网。该公开 API 扫描路线未单独实机验证；私有热点发现验证见本文首节。

---

## 早期背景：热点控制（当前不需要）

核查日期：2026-09-24。范围为手机个人热点／Wi-Fi 网络共享的开启、关闭及 Mac 连接，不涉及新闻热榜。以下为官方文档、GitHub 与 AOSP 源码证据，未连接手机、未切换热点、未实机验证。

## 1. 判断

不能将“连接手机热点”“普通 App 直接开关手机热点”“本地无互联网热点”视为同一能力。普通 iPhone App 没有已核实的公开直接开关 API；用户快捷指令和 MDM 各有独立路径。Android 存在热点 API，但本地热点不分享互联网，新公开的网络共享 API 也不等于普通 App 自动获得控制权限。

## 2. iPhone 与 Mac

| 路径 | 核实结果 | 对个人工具的意义 |
|---|---|---|
| 普通 iOS App 直接开关个人热点 | Apple DTS 将 Personal Hotspot 描述为用户功能而非开发者 API；TN3111 的 NEHotspotConfigurationManager 用于加入 Wi-Fi 网络 | 不能用 NEHotspotConfigurationManager 实现手机热点开关。[DTS](https://developer.apple.com/forums/thread/702058)、[TN3111](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview) |
| iPhone 快捷指令 | Apple 在 iOS 16 更新中列出 Set Personal Hotspot 动作；支持通过 shortcuts URL scheme 调用已有快捷指令 | 可研究用户主动配置快捷指令后的触发路径；不能直接推导为 Mac 静默远程执行。[动作说明](https://support.apple.com/en-sg/101583)、[URL scheme](https://support.apple.com/en-tm/guide/shortcuts/apd624386f42/ios) |
| MDM | Apple 官方设备管理定义含 PersonalHotspot 的 Enabled 布尔设置；要求 Network Information 权限，不支持 User Enrollment | 属于受管理设备方案，不适合作为普通个人 App 的默认接入要求；不能笼统说一定要求监督模式。[官方 GitHub 定义](https://github.com/apple/device-management/blob/release/mdm/commands/settings.yaml) |
| Mac 端连接热点 | Hammerspoon 的 PersonalHotspot Spoon 通过菜单 UI 自动化连接热点 | 可作个人自动化参考，但不是 iPhone 热点控制 SDK；界面变化需适配。[源码](https://github.com/Hammerspoon/Spoons/blob/master/Source/PersonalHotspot.spoon/init.lua) |

## 3. Android

普通 App 可以使用 LocalOnlyHotspot 建立本地设备通信网络，但 Android 官方明确其不具备互联网访问。目标 Android 13／API 33 及以上需请求 NEARBY_WIFI_DEVICES；更早目标版本使用 ACCESS_FINE_LOCATION。它不能替代用户所说的蜂窝网络共享热点。[官方指南](https://developer.android.com/develop/connectivity/wifi/localonlyhotspot)

`TetheringManager.startTethering(TetheringRequest, Executor, StartTetheringCallback)` 和对应 stop 方法在 API 36 进入公开 API。官方文档还描述了 provisioning 检查和权限不足错误。因此不应使用“Android 没有公开 API”的旧结论。[官方 API](https://developer.android.com/reference/android/net/TetheringManager)

实际授权需继续看服务端。当前 AOSP master 的 TetheringService 对网络共享变更检查 TETHER_PRIVILEGED；对于开启相应配置能力、Wi-Fi 类型且带 SoftApConfiguration 的请求，还允许 Device Owner 或运营商特权 App。新能力启用时，仅 WRITE_SETTINGS 不足。源码也保留旧版本／配置下的 WRITE_SETTINGS 路径，因此这不是所有 Android 厂商与版本的统一行为承诺。[AOSP 权限检查及 startTethering 源码](https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/master/Tethering/src/com/android/networkstack/tethering/TetheringService.java)

[Mygod/VPNHotspot](https://github.com/Mygod/VPNHotspot) 是可参考的开源实现：README 明确要求 root，支持通过热点或中继分享 VPN，并列出部分系统热点配置需安装在 `/system/priv-app` 的限制及大量隐藏 API 依赖。仓库标示 Apache-2.0。它证明有特权环境下可以实现相关能力，不能证明普通安装 App 在所有手机上可以静默开关热点。

ADB／Shizuku 不应被当作跨手机通用 API：本次未验证某条命令在目标手机及系统版本上的授权与结果，也未实施此路线。它们若成为后续选项，应按用户明确允许的调试环境单独实测。

## 4. 对 Combo 的最小建议（工程推断，未实施）

若需求是 Mac 快速连接 iPhone 热点，先验证系统已有连接流程及目标 macOS 上的行为；若需求是改变 iPhone 自身热点开关，先验证用户快捷指令方案的触发与交互限制。不要把两者统一包装为一个已成功的远程开关。

若加入 Android，先确定手机系统版本与允许的权限模式：普通安装、企业 Device Owner／运营商、root 是不同产品方案。首轮实测至少覆盖开启、关闭、拒绝权限、锁屏、断连，以及操作是否真的影响互联网共享；不能仅以 API 调用无异常作为成功。
