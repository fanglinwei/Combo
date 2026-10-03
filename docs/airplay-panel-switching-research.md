# Combo 面板内切换 AirPlay 设备：API 调研

调研日期：2026-10-03。目标平台是原生 macOS，目标行为是在 Combo 声音面板点击截图中的“客厅（AirPlay）”，把 Mac 默认音频输出切过去，包括尚未连接的接收器。此目标比让 Combo 自己的播放器使用 AirPlay 更广。

## 结论

**可以研究实现，但不能把 `AVRoutePickerView` 当成已验证的全系统 AirPlay 切换 API。** 它是公开的应用媒体路由控件；原生 macOS 的 `player` 属性明确针对一个 `AVPlayer` 执行路由。已经出现在 Core Audio 设备列表且可作为默认输出的 AirPlay 音频设备，可以走默认输出切换路径。对于尚未成为音频设备的接收器，公开 Core Audio 还存在值得验证的 `AudioTransportManager` / `AudioEndPointDevice` 路径，不能仅凭普通设备列表没有目标就断言公开 API 完全不可行。[Apple：AVRoutePickerView.player](https://developer.apple.com/documentation/avkit/avroutepickerview/player)、[Apple：默认输出设备](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice)、[Apple：创建 EndPointDevice 的 selector](https://developer.apple.com/documentation/coreaudio/kaudiotransportmanagercreateendpointdevice)。

**当前证据不足以承诺“直接点附近设备即可连接并切换系统输出”。** 关键待验证项是：系统 AirPlay transport manager 是否向第三方客户端公开尚未连接的 endpoints，以及公开创建接口是否接受这些 endpoints 并处理接收器认证。私有系统路由接口是另一条实验路径，其运行时存在性、调用成功和未来兼容性需要分别证明，不能由符号名称推导出完整可用性。

本机当前未连接状态的只读探针没有取得可用 transport managers/endpoints，因此公开 endpoint 路径目前没有可以操作的目标。**若要实现截图中的设备行直接连接并切换，下一步优先做私有系统路由 SPI 的概念验证，同时保留公开 endpoint 路径在设备激活后的复测。** 这项建议是根据当前运行时证据的工程判断，不是 Apple 的兼容性承诺。

## 公开 API 的能力与边界

| API / 能力 | 已确认的公开契约 | 对 Combo 目标的含义 |
| --- | --- | --- |
| `AVRoutePickerView` | 显示附近媒体接收器，用户选择后路由媒体；macOS 10.15 起可用。 | 可把系统提供的媒体路由弹层入口嵌入面板。它不是自定义设备列表的数据源。 |
| `AVRoutePickerView.player` | 原生 macOS 属性，执行路由的目标是 `AVPlayer`。 | 对 Combo 自己播放的音频有效；没有“必然修改 Mac 默认输出”的公开保证。 |
| `kAudioHardwarePropertyDevices` | 当前系统可用的 `AudioObjectID` 数组。 | 发现 Bonjour 接收器不等于目标已进入这个数组。 |
| `kAudioHardwarePropertyDefaultOutputDevice` | 默认输出 `AudioDevice` 的 ID。 | 已有、可默认输出的 AirPlay AudioDevice 可以沿用普通输出设备切换。 |
| `AudioTransportManager` 与 `AudioEndPointDevice` | 公开抽象包含 AirPlay；可列出 endpoint，并通过创建 selector 请求组合成 AudioDevice。 | 是首次连接流程的公开候选，仍需验证系统实现是否向 Combo 暴露目标和创建能力。 |
| `AVCustomRoutingController` / `customRoutingController` | 为第三方非 AirPlay 协议集成路由；原生 macOS 不可用。 | 不能用它绕过 AirPlay 首次连接限制。 |
| `AVSystemRouteController` | 新接口用于媒体设备扩展的应用媒体路由；官方当前平台为 iOS / iPadOS / Mac Catalyst 27.0。 | 不能作为当前原生 macOS 面板控制系统音频输出的实现依据。 |

来源：[AVRoutePickerView 官方文档](https://developer.apple.com/documentation/avkit/avroutepickerview)、[WWDC19：Reaching the Big Screen with AirPlay 2](https://developer.apple.com/videos/play/wwdc2019/501/)、[Core Audio 设备列表](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydevices)、[AVCustomRoutingController](https://developer.apple.com/documentation/avrouting/avcustomroutingcontroller)、[AVSystemRouteController](https://developer.apple.com/documentation/avsystemrouting/avsystemroutecontroller-18ns8)、[AVSystemRouting 概览](https://developer.apple.com/documentation/avsystemrouting)。

### AVRoutePickerView：应用媒体路由

Apple 的公开 macOS SDK `AVRoutePickerView.h` 把其作用描述为选择播放路由，讨论部分明确媒体来自 `AVPlayer`。`player` 的类型是可空的 `AVPlayer`，但公开说明没有给 `nil` 定义“操作全系统默认输出”的语义。因此“创建一个空播放器”“把 player 留空”“连接后也许出现 AudioDevice”等方案都应标为实验，不能当作官方保证。[player 官方文档](https://developer.apple.com/documentation/avkit/avroutepickerview/player)。

公开 delegate 只提供开始显示、结束显示两个展示事件；核对的公开头文件没有按设备名称/ID 直接连接的方法，也没有导出附近接收器数组的属性。适合用系统 picker 让用户选择 Combo 播放目标，不适合直接用它实现截图中自定义接收器行的全系统切换。[AVRoutePickerView 官方文档](https://developer.apple.com/documentation/avkit/avroutepickerview)。

### Core Audio：已有 AudioDevice 与未激活 endpoint

`AudioHardware.h` 将普通设备列表定义为当前系统可用设备；默认输出属性保存的是 `AudioDevice` ID。`AudioHardwareBase.h` 同时公开 `kAudioDeviceTransportTypeAirPlay`，说明 AirPlay 可以表现为普通音频设备。实际切换前要确认输出通道、默认设备资格、属性可写性，并检查调用返回值和最终默认设备。另一个属性 `kAudioHardwarePropertyDefaultSystemOutputDevice` 指系统提示等声音，它与普通默认输出不同，不应因名称中含有 “System” 而误认成用户想要的全系统音乐输出。[默认输出属性](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice)、[系统提示输出属性](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultsystemoutputdevice)。

尤其不能忽略公开 transport manager 接口。Apple SDK 给出以下组合：

1. `kAudioHardwarePropertyTransportManagerList`：取得系统 transport managers。
2. `kAudioTransportManagerPropertyTransportType`：识别传输类型。
3. `kAudioTransportManagerPropertyEndPointList`：取得该 manager 追踪的 endpoints。
4. `kAudioTransportManagerCreateEndPointDevice`：通过 `AudioObjectGetPropertyData` 读取这个 selector，在 qualifier 中传入设备描述的 `CFDictionary`，返回创建出的 `AudioObjectID`。虽然是 get/read 接口，**调用本身会创建音频设备，属于有副作用的实验**。
5. `kAudioEndPointDeviceUIDKey`、`NameKey`、`EndPointListKey`、`MainEndPointKey` 描述设备；endpoint 项有 UID、名称和通道数量。
6. `kAudioEndPointDeviceIsPrivateKey` 为 0 表示发布给全系统，为 1 表示仅创建进程私有；省略按公开头文件为全系统发布。

这些不是逆向出来的字符串，而是 Apple 公开 SDK 声明。头文件把 `AudioTransportManager` 明确描述为管理 AirPlay 或 AVB 等传输的对象，组合出的 `AudioEndPointDevice` 可按普通 `AudioDevice` 使用。endpoint 本身没有独立 IO 路径，不能直接把 endpoint ID 当默认输出设备。[transport manager 列表](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertytransportmanagerlist)、[endpoint 列表](https://developer.apple.com/documentation/coreaudio/kaudiotransportmanagerpropertyendpointlist)、[创建设备 selector](https://developer.apple.com/documentation/coreaudio/kaudiotransportmanagercreateendpointdevice)、[设备私有范围](https://developer.apple.com/documentation/coreaudio/kaudioendpointdeviceisprivatekey)。

**推断与未证实部分：** 上述抽象让“公开 API 激活 AirPlay endpoint，再设置默认输出”成为合理候选；它不保证每个 macOS 版本的 AirPlay manager 会公开附近未连接设备，也没有从现有官方说明确认密码/PIN 配对的完整流程。需要以 Combo 支持的 macOS 版本和实际接收器验证。

### AVRouting 与更新的 AVSystemRouting

`AVCustomRoutingController` 的用途是让自定义传输协议参与系统媒体 picker，连接的具体工作交给应用。核对的原生 macOS SDK 标为 `API_UNAVAILABLE(macos)`，`AVRoutePickerView.customRoutingController` 同样不可用。Mac Catalyst 的可用性不等于原生 macOS。[AVRouting 官方文档](https://developer.apple.com/documentation/avrouting)、[AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview)。

截至调研时，Apple 官方 DocC 的 `AVSystemRouteController` 平台 metadata 是 iOS、iPadOS、Mac Catalyst 27.0；流程是用户在 picker 选择设备，应用收到事件，再创建 URL 或远程应用播放 session。官方契约没有提供任意第三方应用设置 Mac 默认音频输出的能力。[AVSystemRouteController](https://developer.apple.com/documentation/avsystemrouting/avsystemroutecontroller-18ns8)、[Routing media to third-party devices](https://developer.apple.com/documentation/avsystemrouting/routing-media-to-third-party-devices)。

## 私有 API 与自动操作系统界面的边界

本调研没有找到公开 `AVOutputDevice` / `AVOutputContext` 的原生 macOS 开发契约，Apple 当前 DocC 对对应 AVFoundation 路径返回 404。这是“本次没有公开契约证据”，不是数学意义证明所有 SDK 永远不存在类似能力。运行时能发现的路由对象、`setOutputDevices:`、系统音频 context 或 MediaRemote 接口，需与公开 API 清楚区分。

若 Combo 的分发路线允许探索私有接口，可以先做隔离原型，验证实际连接和默认输出变化。不能只验证 selector 存在或 setter 返回；成功标准应包括其他正在播放的应用转向目标接收器。

通过辅助功能自动点击控制中心的“声音”设备，理论上可以代替用户操作系统 UI；这不是 AirPlay 专用连接 API，受权限、系统 UI 结构、本地化和版本变动影响。将其作为独立退路评估，不应假定比系统设置入口更可靠。

## 验证记录与建议

此次公开接口调研做了官方网页和 DocC 核对，以及本机 macOS 27.0 SDK 头文件只读检查。尚未创建 endpoint device、连接接收器、改变默认输出或验证实际音频传输。运行中的系统与 SDK 版本应分别记录，不能用编译 SDK 的版本代替运行时版本。

### 当前 Combo 实现

当前源码与截图一致：

- [AudioStore.swift](/Users/fun/Documents/ChatGPT/Combo/Combo/Stores/AudioStore.swift:213) 的 `setOutput` 只接受 `refreshOutputs` 设备列表中的合法 ID，再写默认输出。
- [SoundSections.swift](/Users/fun/Documents/ChatGPT/Combo/Combo/Views/SoundSections.swift:139) 的附近 AirPlay 行会打开系统声音设置。
- [AirPlayDiscovery.swift](/Users/fun/Documents/ChatGPT/Combo/Combo/Audio/AirPlayDiscovery.swift:71) 通过 `NWBrowser` / `bonjourWithTXTRecord` 发现附近服务。该发现信息并非可直接设置为默认输出的 Core Audio 设备 ID。

旧调研中“未打通私有发现”的记录是当时实验结果，不能扩大为“所有私有实现或公开实现均不可能”。当前缺口仍是从发现出的接收器到可用系统音频输出的连接/激活流程。

### 本机只读运行时探针

本轮在 macOS 27.0、build `26A428` 上执行只读探针，未连接接收器时取得：

| 读取项 | 结果 | 可以支持的结论 |
| --- | --- | --- |
| 当前默认输出 | ID 72，MacBook Air 扬声器，`bltn` | 当前输出为内置设备。 |
| `kAudioHardwarePropertyDevices` | ID 84 连续互通麦克风 `ccwd`、79 内置麦克风、72 内置扬声器、48 多输出设备 `grup` | 当前普通设备数组没有 `airp`。 |
| `kAudioHardwarePropertyTransportManagerList` | `OSStatus = 0`，返回大小 0 | 当前客户端没有可枚举的 transport manager。 |
| plug-in 列表 | ID 33，class `aplg`，bundle `com.apple.AirPlayXPCHelper` | 存在 AirPlay 音频插件对象；它本身不是已取得的 transport manager。 |
| 对该插件读取 `end#` | `OSStatus = 2003332927`，`'who?'`，unknown property | 此插件没有接受该 endpoint-list 读取。 |
| 对该插件 `AudioObjectHasProperty(cdev)` | `false` | 不能把这个对象直接当成公开创建 endpoint device 的对象。 |

这是一次特定系统、客户端与未连接状态的快照，不证明其他系统版本、客户端授权或激活后状态相同。探针源暂存在 `/tmp/combo-airplay-api-research/TransportProbe.swift`；没有调用 create/destroy，没有设置系统输出。

建议按成本和证据顺序验证：

1. 根据当前只读结果，先做私有系统路由原型，证明 Combo 点击目标后能激活接收器、让其成为系统音频输出并实际传输其他应用的音频。至少覆盖首次连接、已配对重连、接收器离线、取消认证、面板关闭、恢复内置扬声器及系统版本差异。
2. 接收器经系统 UI 激活后，再只读比较 transport managers、endpoints 与普通 AudioDevices，确认是否出现可以走公开接口的状态。若未连接目标能出现在公开 endpoint 列表，再尝试公开创建 EndPointDevice 的隔离实验；记录返回码、默认设备资格、PIN/密码行为与销毁/回退。
3. `AVRoutePickerView` 可作为应用媒体路由入口；未经系统默认输出和其他应用音频的验证，不能把它升级成全系统切换方案。
4. 辅助功能是系统 UI 操作退路，需要用户授予权限；即使动作成功，也可能显示控制中心等系统界面，和完整留在 Combo 面板内的直接切换体验有距离。
5. 在验证前保留现有系统声音设置入口，文案不能宣称已经支持面板直连。只有默认输出观察和实际音频证明成功之后，才应把对应设备行升级成直接切换按钮。

## 本地一手证据位置

以下为本机 SDK，只读核对；SDK 位于 `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`，`SDKSettings.json` 标示 27.0。在线页面有时不展示注释，因此以 Apple SDK 注释补充精确行为：

- [AVRoutePickerView.h](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/AVKit.framework/Versions/A/Headers/AVRoutePickerView.h:72)：类作用、`player` 与平台可用性。
- [AudioHardware.h](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h:471)：当前设备列表、默认输出、系统提示输出；同文件 720 行起定义创建 endpoint device 的副作用接口。
- [AudioHardwareBase.h](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardwareBase.h:422)：transport manager 对 AirPlay/AVB 的描述；同文件 841 行起定义 endpoint device 的字典、发布范围和 endpoint 无独立 IO 的边界。
- [AVCustomRoutingController.h](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/AVRouting.framework/Headers/AVCustomRoutingController.h:41)：原生 macOS 不可用。
