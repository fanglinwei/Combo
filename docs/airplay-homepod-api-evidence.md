# AirPlay / HomePod 设备识别：API 与信号证据

调研与只读取证日期：2026-10-03。环境：macOS 27.0（Build 26A428），Apple Silicon，`MacOSX.sdk`（Command Line Tools）。

本文保留 2026-10-03 的历史 API 与只读取证，并在下节同步当前实现契约。历史采集不代表本轮异步、权限与生命周期修改已经实机通过。它是[中央图标支持 AirPlay / HomePod：可行性与推荐方案](airplay-homepod-icon-research.md)的配套证据文档，沿用仓库既有的“证据 + 可行性”成对惯例。

⚠️ **取证前提**：本机**没有 HomePod**。局域网内唯一的 AirPlay 设备是 Apple TV（Bonjour 实例名 `客厅`，`model=AppleTV14,1`，tvOS 26.6）。因此蓝牙侧那条结论在这里同样适用：**HomePod 专属取值（TXT `model=AudioAccessory*`、CoreAudio 名字串）本次未实测**，本文逐条标注证据等级。

## 当前实现契约（2026-10-03 更新）

- CoreAudio 默认输出 transport 为 `'airp'` 时调用既有 helper 的 `--route <deviceID> <UID SHA256>`。短进程 2 秒超时；宿主核对 deviceID、UID token、关联 context 与 endpointID。路由缓存 Request 带 UUID 序号；新请求取消旧进程，无输出/离开 AirPlay 清缓存，唤醒先 invalidate 再读。失败回退通用符号与 CoreAudio 名，面板可手动重新读取。
- `canSetVolume` 为可空布尔，缺失表示未知。历史 Apple TV 的 false 表示接收端音量不可调，面板提示“电视音量请用遥控器”；CoreAudio 的 Mac 软件输出滑块不能当成接收端设备音量。
- 附近服务已采用 `NWBrowser(.bonjourWithTXTRecord(type: "_airplay._tcp"))`。首次由用户按“查找”开始并保存 opt-in；之后仅真实 live 面板可见且屏幕活动时自动恢复，关闭/演示/睡眠停止。浏览器实例身份屏蔽旧回调；列表由发现结果与当前路由动态推导，切离 AirPlay 后立即恢复附近项。
- 发现状态区分 idle、searching、ready（可为空）、denied、failed。只有 `DNSPolicyDenied` 报本地网络权限不足，并提供设置入口；普通网络故障可重试。首次请求记录 `askedAt`，浏览器 ready 或停止后清除；`permissionRequestStarting` 仅在系统弹窗出现前为应用切换提供一秒交接保护，弹窗可见期间由 `SystemPermissionAlert` 的窗口可见性保护，不以 5 秒限制用户作答。允许或拒绝后保留面板，不补执行等待期间忽略的交互；下一次外部点击或应用切换正常收起。实际系统权限弹窗与 ad-hoc 身份稳定性仍需实机验证。
- Info.plist 已声明本地网络用途与 `_airplay._tcp` Bonjour 服务。`_raop._tcp` 尚未浏览，因此 AirPlay 1 老设备未全面覆盖。没有建立未路由设备的全系统 AirPlay 路由能力，保留系统声音设置。
- `Tests/AirPlayRouteCheck.swift` / `Tests/AirPlayDiscoveryCheck.swift` 已纳入 `./verify.sh`，覆盖取消、过期回调、切换、超时、权限/普通故障区分和模拟面板失焦。执行结果以本轮实际检查为准；HomePod、多设备、macOS 26 与本轮新流程尚未实机验证。

## 历史结论摘要

| 想知道 | 机制 | 状态 |
| --- | --- | --- |
| 当前输出是不是 AirPlay | `kAudioDevicePropertyTransportType` = `'airp'` | **公开** ✅ 头文件实测（`AudioHardwareBase.h:618`） |
| AirPlay 设备何时出现在 CoreAudio 设备表 | 本机历史观测为路由建立/选中后 | **公开** ✅ 本机实测（Bonjour 可见但设备表没有它） |
| 把已列出的 AirPlay 设备设为默认输出 | `kAudioHardwarePropertyDefaultOutputDevice`（写） | **公开**（Combo 的 `setOutput` 已经是这么做的） |
| 应用内**建立全系统** AirPlay 路由 | 路由由系统 UI 管理 | 未找到并验证可用公开接口；agent 常驻本身不构成 API 不存在的证明（见 §1） |
| 让用户路由 | `AVRoutePickerView`（AVKit） | **公开** ✅ 头文件实测（macOS 10.15+，用户点选） |
| 有没有"多个路由可用" | `AVRouteDetector` | **公开** ✅ 头文件实测（macOS 10.13+，**只有 BOOL，无设备列表**） |
| 枚举可路由的 AirPlay 设备对象（Apple 官方 API） | `AVOutputDeviceDiscoverySession` 等 | **私有/SPI**：由 `AVRouting.framework` 导出符号，但 SDK **无公开头文件** ✅ 本机实测 |
| 免配对读出机型 / 房间名 | **AVRouting SPI**：`AVOutputDevice.modelID` / `name` | **可行** ✅ 本机实测（路由激活时，见 §3.1）；需 helper + entitlement interpose |
| 同上（另一条来源） | Bonjour TXT `model=` + 实例名 | **可行，但要自建 mDNS + 本地网络授权** ✅ 本机实测；值与 SPI 的 `modelID` 一致 |
| 从 CoreAudio 拿机型 | — | **本机未取得** ✅ 历史实测：名字是通用 `"AirPlay"`，`ModelUID` 与 `UID` 同为不透明 UUID（见 §3.1） |
| HomePod 能否被第三方控制/投送 | pyatv（RAOP/AirPlay 2）等 | **仅开源可行**，需配对凭据 |

## 1. CoreAudio：历史枚举与路由边界

- `kAudioDeviceTransportTypeAirPlay = 'airp'`（`AudioHardwareBase.h:618`）。同表里还有 `'blue'`/`'blea'`（蓝牙）、`'bltn'`（内置）、`'grup'`（聚合）、`'ccwd'`/`'ccwl'`（Continuity Capture）、`'rscr'`/`'rstr'`（远程屏/远程流）等，均在 608–624 行。✅ 头文件实测。
- `/System/Library/Audio/Plug-Ins/HAL/AirPlay.driver` 存在于本机 ✅ —— AirPlay 在 CoreAudio 里是标准 HAL 设备，所以"它成为输出时"图标完全可以识别。

**关键行为（本机实测）**：Apple TV `客厅` 在 Bonjour 上活着（`keting.local:7000`），但**不在** CoreAudio 设备表里。同一时刻枚举 `kAudioHardwarePropertyDevices` 只有 4 台：

```
id=84  ccwd  “轻舟已过万重山”的麦克风   id=79  bltn  MacBook Air麦克风
id=72  bltn  MacBook Air扬声器          id=48  grup  多输出设备
```

**当时没有任何 `'airp'` 设备。** 这与 Apple 开发者论坛的历史结论一致（AirPlay 设备自 10.11 起不再"只要可达就枚举"）。直接后果有两条：

1. 中央图标能在"AirPlay 已是当前输出"时识别它——这条路没问题。
2. 但 Combo 的输出设备列表（枚举同一张表，[AudioStore.swift:72-103](../Combo/Stores/AudioStore.swift#L72-L103)）**在 Apple TV 未被系统路由前根本列不出它**，所以"在面板里把输出切到 HomePod/Apple TV"这件事不能靠公开 CoreAudio 完成。

反向操作是公开的：**一旦它出现在设备表里**，用 `kAudioHardwarePropertyDefaultOutputDevice` 写它即可（Combo 现有 `setOutput` 就是这么做的）。但该设备必须仍在设备表里；切走后本机观察到路由消失，所以不能承诺选过一次就能随时切回。

本轮保留系统 UI 建立路由；未找到并验证可用的公开全系统路由接口。**历史本机实测**这三个进程常驻 ✅——`AirPlayUIAgent`（`/System/Library/CoreServices/AirPlayUIAgent.app/Contents/MacOS/AirPlayUIAgent`）、`AirPlayXPCHelper`（`/usr/libexec/AirPlayXPCHelper`）、`fairplayd`（`/System/Library/PrivateFrameworks/CoreFP.framework/Versions/A/fairplayd`）。它们参与系统路由与 FairPlay；常驻现象不能单独证明不存在公开路由 API。

## 2. AVFoundation / AVKit 在 macOS 27 上的真实边界

| API | macOS 27 状态 | 证据 |
| --- | --- | --- |
| `AVRouteDetector` | **公开**（macOS 10.13+），只有 `multipleRoutesDetected` 布尔值，**不给设备列表** | ✅ 本机头文件实测 |
| `AVRoutePickerView` | **公开**（macOS 10.15+），系统自带 AirPlay 路由按钮，**用户点选** | ✅ 本机头文件实测 |
| `AVCustomRoutingController` | `API_UNAVAILABLE(macos)`（iOS 16+） | ✅ 本机头文件实测 |
| `AVRoutingPlaybackArbiter` | `API_UNAVAILABLE(macos)`（iOS/tvOS 26+） | ✅ 本机头文件实测 |
| `AVSystemRouteController` | macOS SDK 中**没有**该声明（只在 `AVCustomRoutingController.h` 的弃用说明里被提及） | ✅ 本机实测 |
| `AVOutputDeviceDiscoverySession` / `AVOutputDevice` / `AVOutputContext` / `AVOutputDeviceGroup` | **SPI**：符号由 `/System/Library/Frameworks/AVRouting.framework` 导出（`.tbd` 里可见整族 `AVOutputDevice*`，含 `AVOutputDeviceAuthorizationTokenTypePIN`），但 **SDK 不提供公开头文件** | ✅ 本机实测（官方头文件 + `.tbd`） |

本仓库已经在踩这条 SPI 线：[AirPodsHelper.m:102-105](../Combo/Audio/AirPodsHelper.m#L102-L105) 先 `dlopen("AVFoundation")` 与 `dlopen("AVRouting")`，再 `NSClassFromString(@"AVOutputContext")` 拿 `sharedSystemAudioContext`（聆听模式/对话感知就走这条）。✅ 本机实测。

**边界：在 macOS 上未找到公开 API 枚举可直接建路由的 `AVOutputDevice` 对象**——`AVRouteDetector` 只给一个布尔值，`AVOutputDeviceDiscoverySession` 一族是无头文件的 SPI。公开的 Bonjour 浏览可以列出附近服务，但不提供上述设备对象。公开路由控件 `AVRoutePickerView` 服务于 **AVPlayer 的媒体路由**，"能否改变系统默认输出"**未验证**（TN3179 只把高层服务 "AirPlay" 列为本地网络豁免，把该控件等同于豁免条目是本报告的推断）。**

## 3. Bonjour：机型与房间名免配对可读（历史本机实测）

`dns-sd` 只读浏览与解析结果（2026-10-03）：

```
_airplay._tcp  →  客厅   + MacBook Air（本机自身也在广播）
_raop._tcp     →  E2AE98315DC2@客厅   + A6577FE94CB3@MacBook Air
_homekit._tcp  →  （无结果）

客厅（_airplay._tcp）TXT:
  model=AppleTV14,1  deviceid=E2:AE:98:31:5D:C2  srcvers=960.13.1  osvers=26.6
  features=0x4A7FDFD5,0x3C177FDE  flags=0x644  pk=23bfcb2f…  fex=1d9/St5/Fzw4oY58
  pi=a58e4dd2-…  psi=E2AE9831-5DC2-4AEA-AAA8-BC4E9F6311ED  gid=FFB6248E-…  acl=0  btaddr=73:A1:F9:84:34:5A  igl=1  gcgl=1  protovers=1.1  vv=1
客厅（_raop._tcp）TXT:
  am=AppleTV14,1  et=0,3,5  ft=0x4A7FDFD5,0x3C177FDE  sf=0x644  md=0,1,2  cn=0,1,2,3
  da=true  tp=UDP  vn=65537  vs=960.13.1  ov=26.6  pk=23bfcb2f…  vv=1
```

要点：

1. **该设备 `model=` 是机型标识**（这里 `AppleTV14,1`），`_raop` 里对应 `am=`。不需要配对、不需要私有 API、不需要开源库——但要自己跑 mDNS 并解析 TXT。
2. **房间名/设备名 = Bonjour 实例名**（`客厅`）。⚠️ **它不等于 CoreAudio 里的输出名**：AirPlay 路由在 CoreAudio 里叫通用的 `AirPlay`（2026-10-03 实测，见 §3.1）——上一版文档把两者当成同一个串，是错的。
3. 本机这台 Apple TV 同时广播 `_airplay._tcp` 与 `_raop._tcp`；不能推广为所有 AirPlay 设备都广播两者。`_homekit._tcp` 在本网络无结果（HomePod 是否广播 `_homekit._tcp` 未实测）。
4. **HomePod 的 `model` 取值（社区普遍写作 `AudioAccessory1,1` / `5,1` / `6,1`）本次未能实测**——这个网络里没有 HomePod，不得把社区值当结论。
5. `btaddr` 同时出现在 TXT 里，说明"蓝牙配对表里的 `客厅`"就是这台 Apple TV：HomePod / Apple TV 会同时广播 BLE，所以**不能因为某设备出现在蓝牙配对表里就把它当成蓝牙音频设备**。

### 3.1 路由激活时的实测：机型其实拿得到（2026-10-03）

把 Apple TV（`客厅`）设为系统默认输出后，三条来源各读一次：

| 来源 | 名称 | 机型 | 关键细节 |
| --- | --- | --- | --- |
| CoreAudio（公开） | `AirPlay` | **拿不到**：`kAudioDevicePropertyModelUID` 与 `kAudioDevicePropertyDeviceUID` 是同一串不透明 UUID（`b13d2acb-c09f-40f2-ae50-1a937ff49e48-419406439965750-Audio`） | 设备名不是房间名；`kAudioDevicePropertyDeviceManufacturer` 不存在 |
| **AVRouting SPI**（`AVOutputContext.sharedSystemAudioContext.outputDevices[0]`，需 helper + entitlement interpose） | `name` / `deviceName` = `客厅` | **`modelID` = `AppleTV14,1`** | 另有 `manufacturer = Apple`、`identifyingMACAddress = E2:AE:98:31:5D:C2`、`deviceID = E2AE9831-5DC2-4AEA-AAA8-BC4E9F6311ED`、`deviceSubType = 13`、`deviceType = 0`、`transportType = 3`、`canSetVolume = 0`、`routeSymbolName = nil`、`OEMIconLabel = nil` |
| Bonjour TXT（公开协议，需本地网络授权） | 实例名 `客厅` | `model=AppleTV14,1` | `deviceid` / `psi` 与 SPI 的 `identifyingMACAddress` / `deviceID` **完全一致** → 两套发现可互相校验、也可互为匹配键 |

要点：

1. **本机这条 CoreAudio 路由未给出机型或房间名**。此前"CoreAudio 里看到的名字就是房间名"的写法是错的，已更正（§3 第 2 条）。
2. `modelID` 与 Bonjour 的 `model=` 是同一个值，说明它就是机型字符串：`AppleTV14,1` → Apple TV；HomePod 预计是 `AudioAccessory*`（**仍未实测**，本网络无 HomePod）。
3. **不过 entitlement 就拿不到上下文**：不注入本项目那个 interpose dylib 时 `sharedSystemAudioContext = nil`，与本仓库既有 AirPods helper 的结论一致（[AirPodsContext.c](../Combo/Audio/AirPodsContext.c)）。另注意：注入后初始化 `NSApplication` 会崩，必须在没有 AppKit 的宿主里查（仓库现成的 helper 就是这个形态）。
4. `AVOutputDevice` 还暴露 `canSetVolume` / `setVolume:` / `increaseVolumeByCount:` / `AVOutputContext.setOutputDevice:` 等控制面——"日后在 Combo 内控制 AirPlay 设备"同样只能走这条 SPI（Apple TV 本条路由的 `canSetVolume = 0`）。
5. 第三方设备的 `modelID` / `manufacturer` 取值未实测；该 Apple 设备上 `OEMIcons` / `OEMIconLabel` 为 nil（系统预留了 OEM 图标位，但 Apple 自家设备不用）。
6. **历史原型观测**：早期 helper 的 `--route` 模式带 interpose 返回 `{"model":"AppleTV14,1"}`、不带时返回 `{"model":""}`。当前命令含设备 ID 与 UID token，并要求完整身份回复；此旧 JSON 不是当前契约。App 侧见 [AirPlayRoute.swift](../Combo/Audio/AirPlayRoute.swift) 与 [可行性与推荐方案](airplay-homepod-icon-research.md) §4。

### 3.2 机型 ID 表与"支持到最新"

`modelID` 是一串 Apple 机型标识，取值来自 Apple 自家表。第三方维护、覆盖到 2026 代设备的 [libirecovery](https://cgit.libimobiledevice.org/libirecovery.git/plain/src/libirecovery.c)（LGPL）里，HomePod 条目的**全部**内容为：

| modelID | 对应机型 |
| --- | --- |
| `AudioAccessory1,1` / `AudioAccessory1,2` | HomePod（1 代） |
| `AudioAccessory5,1` | HomePod mini |
| `AudioAccessory6,1` | HomePod（2 代） |

该表同时印证了本机实测值：`AppleTV14,1` = Apple TV 4K（3 代）；表里**不存在**比 `6,1` 更新的 HomePod ID，也没有 `AirPort*` / `HomeAccessory*` 条目。

两条对图标设计有决定意义的结论：

1. **SF Symbols 没有"按代际"的 HomePod 图标**——只有 `homepod` 与 `homepod.mini`，而 `.2` 后缀是**复数（两个设备）**而不是"二代"：本机渲染 `homepod` / `homepod.2` / `homepod.mini` / `homepod.mini.2` 肉眼可见 `.2` 变体是两个并排设备。所以"支持到最新"在上限上只能是**全尺寸 vs mini**，与 HomePod 1/2 代无关。
2. **当前家族级映射**：任何未知的 `AudioAccessory*`（含未来新机型）当前都按全尺寸 HomePod 处理；这不是未来机型的正确性承诺，新增设备仍需验证；只有未知前缀（第三方、AirPort 等无依据的标识）才回落 `airplay.audio`。⚠️ 该表仍是第三方来源，**未在本机实测**。

### 3.3 控制能力的历史实测边界（2026-10-03）

围绕"能不能在 Combo 面板里控制 AirPlay 设备"，逐项实测的结果：

| 能力 | 实测结果 | 依据 |
| --- | --- | --- |
| 这条 AirPlay 输出的音量 / 静音 | ✅ **历史观测可写**（Mac 软件输出音量，不等同接收端硬件音量） | CoreAudio `id=86`：`kAudioDevicePropertyVolumeScalar` 主通道可写（当时 0.164）、`kAudioDevicePropertyMute` 可写 |
| 接收端**设备自身**音量 | ❌ Apple TV 不支持 | `AVOutputDevice`：`canSetVolume = 0`、`canMute = 0`、`volumeControlType = 0`；`AVOutputContext` 反而 `canSetVolume = 1`（那是系统输出音量，即上一条） |
| 接收端播放/暂停/切歌 | ❌ 接口不存在 | 全量方法表里 `AVOutputDevice`（158 个方法）与控制集**当时没有任何** play/pause/next/previous；`MediaRemote` 只控本机播放源 |
| **把输出切走（断开 AirPlay）** | ⚠️ 本次观测会拆掉路由，需系统 UI 重建 | 实测：把默认输出从 AirPlay 切到内置扬声器后，AirPlay 设备从 `kAudioHardwarePropertyDevices` 消失，**应用内无法重建**（无公开 API，SPI 也需要一个 AVOutputDevice 对象） |
| SPI 重新连接 / 枚举设备对象 | ❌ **未打通** | `AVOutputDeviceDiscoverySession` 的 `initWithDeviceFeatures:`（0/1/2/4/8/16/0xFFFF）全部返回 nil；`outputDeviceDiscoverySessionFactory` 返回的 `AVFigRouteDiscovererOutputDeviceDiscoverySessionFactory` 上，`outputDeviceDiscoverySessionOfClass:withDeviceFeatures:` 也建不出会话。`AVOutputDeviceDiscoverySessionConfiguration` 类存在但装配方式未知 |
| **列出附近（未路由）的 AirPlay 设备** | ✅ **历史浏览探针可见设备；当前权限与生命周期流程未实机回归** | `NWBrowser(.bonjourWithTXTRecord(type: "_airplay._tcp"))`：本机实测列出 2 台（`客厅[AppleTV14,1]`、本机 `MacBook Air[Mac14,2]`），TXT 里的 `model=` 可读。**必须用 `bonjourWithTXTRecord`**——普通 `.bonjour` 描述符不带 TXT。代价：本地网络授权（`NSLocalNetworkUsageDescription` + `NSBonjourServices`） |
| **连接到未路由的 AirPlay 设备** | ❌ **未打通** | `AVOutputDeviceDiscoverySession` 的三种构造入口（`initWithDeviceFeatures:`、工厂类方法、configuration 路径）全部返回 nil；没有 `AVOutputDevice` 就无法用 `setOutputDevice:` / `addOutputDevice:` 建立路由。当前只能"列出 + 跳系统声音设置由用户选择" |
| 多房间分组 | ⚠️ 接口在、无硬件可验 | `canBeGrouped = 1`、`participatesInGroupPlayback = 1`；`AVOutputDeviceGroup` 有 `addOutputDevice:withOptions:completionHandler:` / `removeOutputDevice:withOptions:completionHandler:` / `volume` |
| 路由控制接口（存在但需对象） | ✅ 方法存在 | `AVOutputContext`：`setOutputDevice:forFeatures:`、`setOutputDevice:options:`、`setOutputDevices:`、`addOutputDevice:`、`removeOutputDevice:` |
| AV ↔ CoreAudio 关联键 | ✅ 历史单路由一致；多设备未验证 | `context.associatedAudioDeviceID` = CoreAudio 的 UID（如 `b13d2acb-…-Audio`），比按名字匹配可靠 |

**当前边界**：不新增专用“断开 AirPlay”操作；系统默认输出选择仍可切到扬声器，但切回 AirPlay 可能要系统 UI 重建。Bonjour 发现不等于建立路由能力，附近项明确转交系统声音设置。

## 4. 权限与签名（TN3179 原文核实）
[Apple TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) 原文结论（本次已抓取核实）：

1. 本地网络隐私在 **macOS 15** 引入；用户在"系统设置 → 隐私与安全性 → 本地网络"里控制。
2. **"All Bonjour operations require local network access."** 注册、浏览、解析三类 Bonjour 操作都要本地网络访问权 → 自建 `NWBrowser`/`dns-sd` **会被要求授权**。
3. **"The multicast entitlement isn't required on macOS."** → `com.apple.developer.networking.multicast` 在 macOS 上**不需要**（沙盒与否都不需要）。这一条纠正了本文档早期版本的说法。
4. **"High-level services that use Bonjour internally don't require local network access… Such services include: AirPlay — no."** → 原文只把高层服务 **"AirPlay"** 列为豁免。Apple 自己的 AirPlay 路由路径（系统 agent）大概率落在这条豁免里，但**把 `AVRoutePickerView` 等同于该条目属于本次推断、未逐条验证**。可以确定的是：我们自己的 mDNS 浏览器**不在**豁免范围。
5. 需要声明实际浏览的服务；当前 `NSLocalNetworkUsageDescription` 与 `NSBonjourServices` 已声明 `_airplay._tcp`，`_raop._tcp` 尚未采用；并且**系统可能在用户应答弹窗前就拒绝这次操作**，需要支持等待连通性的 API（Network framework）或重试逻辑。
6. **与本项目最相关的一条**：*"Local network privacy tracks the identity of your program using its code signature. This presents a challenge on macOS, which allows for unsigned code and ad hoc signed code… To ensure that local network privacy reliably tracks the identity of your macOS program, sign it with an Apple-issued code-signing identity."* 另外它用**主可执行文件 UUID** 参与实现，UUID 缺失或与他程序重复会导致行为怪异。
   Combo 是 ad-hoc 签名（[README.md:41](../README.md#L41) 声明 ad-hoc、无 Developer ID 公证；具体值在 [project.pbxproj:440](../Combo.xcodeproj/project.pbxproj#L440) `CODE_SIGN_IDENTITY = "-"`、[:443](../Combo.xcodeproj/project.pbxproj#L443) 空 `DEVELOPMENT_TEAM`、[:445-446](../Combo.xcodeproj/project.pbxproj#L445-L446) 沙盒与加固运行时关闭），**正落在这条警告里**：当前已引入 Bonjour 浏览，本地网络授权的身份跟踪**可能**不可靠（重复弹窗/授权不生效），而这与"只读取证是否存在"无关，是签名方式的问题。

## 5. GitHub 开源项目的历史能力记录（2026-10-03 逐仓用 GitHub API 复核）

| 项目 | 语言 / 许可 | 方向 | 能当 API 用吗 | macOS |
| --- | --- | --- | --- | --- |
| [pyatv](https://github.com/postlund/pyatv) | Python / MIT | **发送端 + 控制器** | Python 库，`atvremote` / `atvscript` | 可以（需 Python 运行时） |
| [owntone](https://github.com/owntone/owntone-server) | C / GPL-2.0 | **发送端**（AirPlay 1+2 多房间） | 守护进程 + HTTP JSON | Docker/brew |
| [shairport-sync](https://github.com/mikebrady/shairport-sync) | C / 非标准（GitHub 记为 NOASSERTION） | **接收端** | 守护进程 | 可以 |
| [AirConnect](https://github.com/philippe44/AirConnect) | C / 非标准（NOASSERTION） | **接收端 → 桥接**（AirPlay 进，UPnP/Sonos/Chromecast 出） | 守护进程 | 部分 |
| [airplay-cli](https://github.com/bpetrynski/airplay-cli) | Shell / **无许可证** | 发现 + AppleScript 点系统菜单 | **不是 API**（★1） | 可以 |
| [airplay2-receiver](https://github.com/openairplay/airplay2-receiver) | Python / 无许可证 | **接收端** | 脚本 | 部分 |
| [RPiPlay](https://github.com/FD-/RPiPlay) | C++ / GPL-3.0 | **接收端**（镜像） | 面向树莓派，2023 年后未更新 | 差 |
| [node_airtunes2](https://github.com/ciderapp/node_airtunes2) | JS / AGPL-3.0 | **发送端**（仅 RAOP/AirPlay 1） | 库 | 可以 |

- 上表的许可证、语言、项目方向与存在性于 2026-10-03 通过 GitHub API 逐仓复核（`license.spdx_id`）：pyatv `MIT`、owntone `GPL-2.0`、RPiPlay `GPL-3.0`、node_airtunes2 `AGPL-3.0`、airplay-cli 与 airplay2-receiver 无许可证、shairport-sync 与 AirConnect 为 `NOASSERTION`（非标准/混合）。
- `urish/node-raop` **不存在（404）**，不得引用。
- **本次未发现** AirPlay 专用的 Go/Rust/Swift 库；只有通用 mDNS（`grandcat/zeroconf`、Swift `NWBrowser`/`swift-mdns` 等），TXT 需自行解析。
- pyatv 的具体边界（已逐条对照 [pyatv Supported Features](https://pyatv.dev/documentation/supported_features/) 核实）：RAOP 音频流在 HomePod mini (v14.5)、Apple TV、AirPort Express 与 shairport-sync 上验证可用；**RAOP 的远程控制不工作，只有音量可调**（[issue #1068](https://github.com/postlund/pyatv/issues/1068)）；**HomePod 上无法做 Companion pairing**（该协议要求目标设备能显示 PIN，HomePod 不能）；HomePod 的元数据靠 AirPlay 2 隧道 MRP 取得；需要配对的设备（Apple TV 4 及以后、HomePod）必须先配对并提供凭据；**pyatv 目前未实现 HAP 加密，RAOP 只支持 legacy pairing，AirPlay 2 的 HAP 仅用于远程控制**——所以"用 pyatv 对 HomePod 做 AirPlay 2 全功能控制"并不成立；`atvremote scan` 打印型号而 `atvscript scan` 不打印（[issue #1789](https://github.com/postlund/pyatv/issues/1789)）。

**所以：只做"识别 + 图标"这件事，开源项目一分钱都用不上；做到"控制/投送"那一档时，历史调研中 pyatv（MIT）是候选路径，代价是 Python 运行时 + 配对凭据。接收端项目（shairport-sync / AirConnect / RPiPlay / airplay2-receiver）方向相反，不适用。**

## 6. 易错点

1. **仓库旧文档只记录了"5 秒发现 0 台设备"并把"授权/PIN 流程"列为未确认（[airpods-audio-feasibility.md:42](airpods-audio-feasibility.md#L42)），并未断言它是权限问题**。更可能的原因是结构性的——AirPlay 设备未建路由时不在 CoreAudio 表里，且 `AVOutputDeviceDiscoverySession` 在 macOS 上没有公开头文件。⚠️ 精确根因未实测（需要写探针）。
2. **不要为"发现"去申请 multicast entitlement**：macOS 不需要（TN3179）；真正需要的是本地网络授权。
3. **不要用"出现没出现在蓝牙配对表里"判断设备类型**：Apple TV / HomePod 同时广播 BLE，本机 `客厅` 就是例子。
4. **`AVRouteDetector` 给不了设备列表**，它只有一个布尔值——把它当发现 API 是常见误解。
5. **不要在设备未激活时指望 CoreAudio 里能看到它**：不能。
6. **接收端 ≠ 发送端**：把 shairport-sync / AirConnect 之类当"控制 HomePod"的方案是方向性错误。
7. **HomePod 控制必须配对**：没有凭据就没有音量/播放控制，且 HomePod 上没有 PIN 可做 Companion pairing。

## 7. 未实测 / 待验证

1. HomePod 的 `_airplay._tcp` TXT `model` 值（`AudioAccessory*`）与 `kAudioObjectPropertyName` 返回串——本网络无 HomePod。
2. HomePod 是否广播 `_homekit._tcp`。
3. "AirPlay 设备只有路由激活才进 CoreAudio 表"的机制性解释（本机只证明了现象，未定位到 `AirPlayUIAgent` 内部）。
4. `AVOutputDeviceDiscoverySession` 那 5 秒 0 台的精确根因。
5. pyatv 在 macOS 27 上对 HomePod 的配对/控制实测（本机未安装 pyatv）。
6. 本轮身份校验、取消/超时、权限提示、面板关闭/演示/睡眠唤醒与快速切换的实机流程；历史 Apple TV 路由已观测到 `'airp'`，不能再列为“未建立路由”。
7. HomePod 全尺寸/mini、多设备、AirPlay 1 与 macOS 26；当前 `canSetVolume` unknown 的接收端行为。

## 8. 来源

- 本机：`MacOSX.sdk/…/CoreAudio.framework/Headers/AudioHardwareBase.h:608-624`；`AVKit.framework/Headers/AVRoutePickerView.h`；`AVFoundation.framework/Headers/AVRouteDetector.h`；`AVRouting.framework/Versions/A/AVRouting.tbd`；`/System/Library/Audio/Plug-Ins/HAL/AirPlay.driver`；`dns-sd` 只读浏览/解析；CoreAudio 设备枚举探针（只读）
- Apple：[TN3179 Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)（原文已核实）· [AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview) · [AVRouteDetector](https://developer.apple.com/documentation/avfoundation/avroutedetector) · [NSBonjourServices](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices) · [NSLocalNetworkUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)
- 开源：[pyatv](https://github.com/postlund/pyatv) · [Supported Features](https://pyatv.dev/documentation/supported_features/)（协议能力与限制的权威来源）· [issue #1068](https://github.com/postlund/pyatv/issues/1068)（RAOP 远程控制不可用）· [issue #1789](https://github.com/postlund/pyatv/issues/1789)（`atvscript scan` 不打印型号）· [owntone](https://github.com/owntone/owntone-server) · [shairport-sync](https://github.com/mikebrady/shairport-sync) · [AirConnect](https://github.com/philippe44/AirConnect) · [airplay-cli](https://github.com/bpetrynski/airplay-cli) · [airplay2-receiver](https://github.com/openairplay/airplay2-receiver) · [RPiPlay](https://github.com/FD-/RPiPlay) · [node_airtunes2](https://github.com/ciderapp/node_airtunes2)
