# 中央图标支持 AirPlay / HomePod：实现与验证边界

整理：2026-10-04；实现与历史取证：2026-10-03。开发与历史取证环境为 macOS 27.0（Build 26A428）、Apple Silicon、自用 ad-hoc 原型。本文合并当前实现、历史 API 采集及面板切换研究；历史观测不代表当前流程重新验收。

## 1. 当前范围

| 能力 | 当前行为 | 验证边界 |
| --- | --- | --- |
| 当前输出识别 | CoreAudio 默认输出的 transport 为 `'airp'` 才进入 AirPlay 分类 | 历史 Apple TV 路由采集确认过；当前异步实现仍需实机回归 |
| 名称与图标 | helper 读取已建立路由的名称、机型；中央与输出列表共用同一结果 | Apple TV 历史值为 `AppleTV14,1` / `客厅`；HomePod 未实机验证 |
| 附近设备 | 用户首次点击“查找”后，`NWBrowser` 浏览 `_airplay._tcp` 及 TXT；点击结果打开系统声音设置 | 原始 Bonjour 采集可见 Apple TV；当前权限、生命周期与界面未完成端到端实机验证 |
| 建立全系统路由 | 保留系统声音设置入口，由用户选择 | 不承诺应用内一键连接未路由设备；`AVRoutePickerView` 也未验证可改系统默认输出 |
| 音量 | CoreAudio 软件输出音量与接收端设备音量分开说明 | 历史 Apple TV `canSetVolume = false`，显示“电视音量请用遥控器”；未知能力不画成支持或拒绝 |

旧版 Q1/Q2/Q8 中“只做识别、不发现、无需新增权限”已被当前范围替换：附近发现现在采用 Network.framework 与本地网络权限。Q3 的统一 AirPlay 符号已改为机型分类；Q5 的系统路由入口、Q4/Q6 的不捆绑第三方运行时继续适用。旧方案中的“不开 mDNS”“新增开销为零”不再适用。

## 2. 路由探测与身份

入口只看当前默认输出的 CoreAudio transport；蓝牙配对表、房间名与播放状态都不能替代它。蓝牙/BLE 与 AirPlay 是平级分支，内置、USB、HDMI 等不显示中央设备符号，既有电量与网络优先级保持不变。

已建立的 AirPlay 路由使用既有 `ComboAirPodsHelper` 与 `ComboAirPodsContext.dylib`，调用 `--route <deviceID> <UID SHA256>`。每次是短进程，宿主超时为 2 秒；回复必须通过 deviceID、UID token、关联 context 与 endpointID 校验。`AirPlayRoute.Request` 包含 UUID 序号，即使系统重用设备 ID，旧请求也不能回填新结果。新请求取消旧任务及进程；没有默认输出或离开 AirPlay 时取消并清缓存；唤醒先失效再重读。

helper 失败、缺失、超时、身份不匹配或 context 有多个输出接收端时，名称退回 CoreAudio、符号退回 `airplay.audio`。面板提供手动重新读取；没有具体机型信号时不猜 Apple TV / HomePod。结果的 `canSetVolume` 可为空，表示未知；Mac 软件输出音量可写不等于接收端硬件音量可控。

| `modelID` | 符号 | 依据 |
| --- | --- | --- |
| `AppleTV*` | `appletv` | 历史 Apple TV `AppleTV14,1` 实测 |
| `AudioAccessory5*` | `homepod.mini` | 第三方机型表推导，未实机验证 |
| 其它 `AudioAccessory*` | `homepod` | 当前家族映射；未来机型仍需复核 |
| 未知、空或探测失败 | `airplay.audio` | 通用回退 |

`.2` 后缀的 HomePod SF Symbol 表示两个设备，不表示二代；当前不按代际或多房间分组绘制。

## 3. 附近发现与权限

第一次必须由用户按“查找”启动，并保存 opt-in；此前打开面板不会浏览 Bonjour。此后仅在真实面板可见、场景为 live 且屏幕活动时自动恢复；关闭面板、进入演示或睡眠即停止。浏览器以实例身份防止已取消的旧回调更新新状态。附近列表由 `discovery.devices` 与当前路由动态推导；已路由设备不重复展示，切离 AirPlay 后立即回到附近列表。

| 状态 | 面板含义 |
| --- | --- |
| `idle` | 尚未开始或已停止，可查找 |
| `searching` | 正在查找 |
| `ready` | 浏览器就绪；有结果展示结果，空结果显示未发现 |
| `denied` | 仅 `DNSPolicyDenied` 归为本地网络权限不足，提供本地网络设置入口 |
| `failed` | 普通网络/浏览错误，显示失败并可重试，不误报权限拒绝 |

Info.plist 已加入 `NSLocalNetworkUsageDescription` 与 `_airplay._tcp` 的 `NSBonjourServices` 声明；macOS 不需要 multicast entitlement。首次发现记录 `askedAt`，浏览器 ready 或停止后清除；系统窗口出现前仅对应用切换提供一秒交接期，实际弹窗期间由系统授权窗口可见性保护，覆盖等待超过 5 秒的情况。自动化检查可验证这条保护逻辑，实际系统弹窗是否出现、是否保住面板仍需实机验证。ad-hoc 签名下授权身份的稳定性也未验证。

只浏览 `_airplay._tcp`，只播 `_raop._tcp` 的 AirPlay 1 老设备（如部分 AirPort Express / 第三方音箱）尚未覆盖。附近项用于发现与转交系统设置；发现 Bonjour 服务不等于取得可建立路由的 `AVOutputDevice` 对象。

## 4. 开销与检查

新增路由查询为按输出变化、手动重读或唤醒触发的短进程；附近浏览只在用户 opt-in 后的活动真实面板运行，不是常驻扫描。共享绘图缓存固定的 16 个 SF Symbol 原图，每次绘制应用当前颜色；未知符号名不进入缓存。没有实测耗电数字，不宣称新增开销为零。

`Tests/AirPlayRouteCheck.swift` 与 `Tests/AirPlayDiscoveryCheck.swift` 已接入 `./verify.sh`，覆盖异步取消、过期结果、路由切换、超时、权限拒绝与普通网络故障区分；`Tests/PanelMotionCheck.swift` 与 `Tests/PanelDismissCheck.swift` 覆盖不依赖 key 的外部点击、详情/图标内部点击、长时间授权保护、授权结束、应用/Space 切换、主动收起及动画。分类、符号回退与中央/列表一致性由现有输出设备及图标检查覆盖。检查结果以实际运行输出为准，历史 Apple TV 采集不代表当前功能已经实机通过。

待实机回归：首次本地网络弹窗与拒绝/重试、面板关闭/演示/睡眠及唤醒、快速切换与设备 ID 复用、HomePod 全尺寸/mini、多设备、AirPlay 1、蓝牙与 AirPlay 并存及 macOS 26。保留系统声音设置；不捆绑 pyatv/owntone 等运行时，不实现 HomePod 接收端播放控制或音频投送。

2026-10-03 历史验证：Debug 构建、路由进程检查、发现状态检查、helper 单接收端/多接收端回退检查、蓝牙回复验证、模拟本地网络失焦保护及其余状态/图标/本地化/helper/签名检查通过。后续面板关闭修复已移除对 key 的依赖；当时完整 `verify.sh` 已通过，包含 AppKit 本地点击监听与 Space 通知检查。当时未触发真实系统授权弹窗，系统代理窗口识别仍需实机复核。

相关：[蓝牙设备分类](bluetooth-audio-device-icon-research.md) · [设置规格](combo-settings.md#31-中央状态优先级2026-09-24) · [后续规划](combo-roadmap.md)。

## 5. API 证据与历史观测

以下为 2026-10-03 的取证记录，环境 macOS 27.0 build `26A428`。网络中只有 Apple TV（tvOS 26.6），没有 HomePod；本次整理未重新在线核查、建立路由或查询设备。

### 同一 Apple TV 的三条来源

| 来源 | 历史返回 | 可支持的结论 |
| --- | --- | --- |
| Bonjour `_airplay._tcp` | 实例名“客厅”，TXT `model=AppleTV14,1` | 免配对发现名称/机型；仍需要自建浏览及本地网络授权 |
| 已激活 CoreAudio 路由 | transport `'airp'`，名称 `AirPlay`，UID/ModelUID 为不透明 UUID | 当前输出可识别 AirPlay，但本机该路由未给房间名或机型 |
| AVRouting SPI，经 helper context 适配 | name/deviceName“客厅”，modelID `AppleTV14,1`，`canSetVolume=false` | 本机已建立路由可读名称/机型；设备自身音量不可控 |

Bonjour 的 deviceid/psi 与 SPI 的设备身份一致，AV context 的 associatedAudioDeviceID 与 CoreAudio UID 一致。当前仍需完整 token/context/endpoint 校验，不能拿历史单设备一致性替代多设备验证。未适配时 sharedSystemAudioContext 为 nil；helper 应在不初始化 AppKit 的宿主中运行。

未激活时 Bonjour 可见 Apple TV，普通 CoreAudio 数组没有 `'airp'`；激活后可列出，切回内置扬声器后设备消失。此现象只证明该客户端和当时路由行为，不能推出所有公开激活路径都不存在。

Mac 软件输出音量/静音历史可写，接收端 AVOutputDevice 的 canSetVolume/canMute 为 false；两者不可混称。历史方法表未找到接收端 play/pause/next/previous；MediaRemote 控本机播放源。发现会话的多种 SPI 构造曾返回 nil，尚未打通未路由设备的连接；有分组接口不等于多房间已验证。

### 公开与私有接口

| 接口 | 历史核查能力 | 对当前功能的含义 |
| --- | --- | --- |
| CoreAudio 普通 AudioDevice + 默认输出属性 | 已列出且合格的设备可按默认输出路径切换 | Bonjour 结果不是 AudioObjectID；默认系统提示输出也不是普通媒体默认输出 |
| `AVRouteDetector` | 只有 multipleRoutesDetected 布尔 | 不能取得接收器列表 |
| `AVRoutePickerView.player` | 原生 macOS 面向 `AVPlayer` 应用媒体路由 | player 为 nil 不保证控制系统默认输出；不是自定义列表数据源 |
| `AVOutputDevice` / Context / DiscoverySession | SDK 无公开头文件的 AVRouting SPI | 运行时存在、能读取、能连接、可长期兼容须分别验证 |
| `AVCustomRoutingController` | 历史 SDK 为原生 macOS unavailable | Catalyst 可用不等于原生 macOS可用 |
| `AVSystemRouteController` | 当时官方 metadata 为 iOS/iPadOS/Mac Catalyst 27 | 不作为当前原生 macOS 系统输出控制依据 |

### 全系统切换的公开候选与探针

公开 SDK 还有 AudioTransportManager/AudioEndPointDevice：先读 `kAudioHardwarePropertyTransportManagerList`、transportType、EndPointList，再用 `kAudioTransportManagerCreateEndPointDevice` 请求组合成 AudioDevice。即便通过 GetPropertyData selector 调用，create 本身有副作用；endpoint ID 不能直接当默认输出 ID。设备描述有 UID/Name/EndPointList/MainEndPoint，`IsPrivate=0` 表示全系统，1 表示仅本进程。

未连接时的只读探针：transport manager 查询 OSStatus=0、大小=0；存在 `com.apple.AirPlayXPCHelper` 插件对象，但其 `end#` 返回 unknown property (`2003332927`)，`cdev` 不存在。没有创建/销毁设备或改变输出。这说明当时没有可操作的公开 endpoint，不证明激活后的状态相同。

后续候选需证明接收器激活、默认输出回读和其他应用的实际音频传输；覆盖首次连接、配对重连、离线、取消 PIN/密码、面板关闭及恢复内置。可在系统 UI 激活后复测公开 manager/endpoint，或隔离验证私有系统路由。仅 selector 存在或调用无异常不算成功。辅助功能点击系统界面是另一路 UI 自动化，受权限/语言/布局影响，当前仍保留系统设置入口。

### 型号与发现范围

[libirecovery 机型表](https://cgit.libimobiledevice.org/libirecovery.git/plain/src/libirecovery.c)历史记录：HomePod `AudioAccessory1,1` / `1,2`，mini `5,1`，二代 `6,1`；这不是本机 HomePod 实测。`.2` 的 SF Symbol 表示两台设备，不表示二代，当前仅区分全尺寸/mini/Apple TV/通用。

本机 Apple TV 同时广播 `_airplay._tcp` 与 `_raop._tcp`，不能推广所有设备；本机自身也出现在 Bonjour 结果中，发现不证明远端可连接。`_homekit._tcp` 当时无结果，HomePod 是否广播未验收。蓝牙配对表中的 Apple TV 也不能作为蓝牙音频分类入口。

### 权限与发行边界

历史 [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) 核查指出自建 Bonjour 操作需要本地网络访问，macOS 不需要 multicast entitlement。高层 AirPlay 服务的豁免不能泛化为 Combo 自建浏览免授权。系统可能在用户作答前先拒绝操作，需要区分权限拒绝/普通故障并支持重试。

本地网络隐私用代码签名跟踪程序身份，历史 ad-hoc 开发环境不证明发行身份或重新编译后的授权稳定。首次真实弹窗、拒绝/重试与面板保护仍需当前签名应用实测。

### 上游研究与来源

历史调查中 [pyatv](https://github.com/postlund/pyatv) / [能力表](https://pyatv.dev/documentation/supported_features/) 是发送/控制候选，需 Python 与部分设备配对凭据；RAOP 控制、HomePod Companion pairing 与 HAP 能力有独立限制，不保证 HomePod 全功能。[owntone](https://github.com/owntone/owntone-server) 是发送守护进程；shairport-sync、RPiPlay、airplay2-receiver 等是接收端，不能据此承诺控制 HomePod。Combo 未捆绑这些运行时；[airplay-cli](https://github.com/bpetrynski/airplay-cli) 是 Bonjour 与系统 UI 自动化参考，不是通用路由 API。

主要公开来源：[AVRoutePickerView.player](https://developer.apple.com/documentation/avkit/avroutepickerview/player)、[默认输出属性](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice)、[TransportManager 列表](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertytransportmanagerlist)、[创建 EndPointDevice](https://developer.apple.com/documentation/coreaudio/kaudiotransportmanagercreateendpointdevice)、[设备私有范围](https://developer.apple.com/documentation/coreaudio/kaudioendpointdeviceisprivatekey)、[AVSystemRouteController](https://developer.apple.com/documentation/avsystemrouting/avsystemroutecontroller-18ns8)。本机 SDK 的 AudioHardware.h、AudioHardwareBase.h、AVRoutePickerView.h 与 AVRouting.tbd 补充历史头文件/导出符号证据。
