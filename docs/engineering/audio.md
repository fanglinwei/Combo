# 音频：输出身份、AirPods、蓝牙与 AirPlay

整理：2026-11-12。中央图标、声音面板和输出列表共用默认输出身份与分类；只有默认输出的蓝牙/BLE、AirPlay transport 进入设备图标分支。配对、连接和播放状态均不能替代默认输出身份。外圈始终表示 Mac 本机电量。历史硬件证据来自 macOS 27.0 build `26A428` 的 ad-hoc 原型，不替代当前发行版验收。

<a id="airpods"></a>

## 声音与 AirPods

### 当前能力

| 功能 | 当前实现 | 验证边界 |
| --- | --- | --- |
| 输出设备、音量、静音 | CoreAudio；主通道不可读时回退左右声道；默认输出列表与事件监听 | 设备切换及不同硬件仍需实机回归 |
| 蓝牙音频电量 | IOBluetooth 私有整机/左右耳/充电盒 getter；总览和详情共用同一组圆环 | 字段独立；盒子休眠、歧义零值、不支持保留未知；未采集可靠充电/入仓信号 |
| 聆听模式 | 通透、自适应、降噪；私有 AVOutputDevice 写后回读 | 本机往返切换曾通过；Normal/关闭模式未独立确认，面板不提供 |
| 对话感知 | 两段关闭/打开，写后回读 | 本机关闭→开启→关闭曾通过 |
| 空间音频 | 不监控、不展示、不提供写操作 | 早期写入未确认；最终已移除全部字段与查询 |
| AirPlay | 默认路由识别与附近发现另见 [AirPlay 文档](audio.md#airplay) | 未路由设备的面板直连未实现 |

实现入口：[AudioStore.swift](../../Combo/Stores/AudioStore.swift)、[AudioVolume.swift](../../Combo/Audio/AudioVolume.swift)、[AirPodsControl.swift](../../Combo/Audio/AirPodsControl.swift)、[AirPodsHelper.m](../../Combo/Audio/AirPodsHelper.m)、[AirPodsContext.c](../../Combo/Audio/AirPodsContext.c)、[SoundSections.swift](../../Combo/Views/SoundSections.swift)。

### 身份、生命周期与失败处理

只在真实面板可见、屏幕活动且蓝牙已授权时读取；当前蓝牙音频输出每 3 秒一次。关闭面板、睡眠、权限失效或切换蓝牙设备会取消请求并清除旧快照。切回非蓝牙输出时，仅保留上一台设备最后一次读取的电量；15 秒后变为未知，不再显示旧值。蓝牙类别复用同一 status 请求，见 [蓝牙分类](audio.md#bluetooth)。

helper 用 `IOBluetoothDevice.outputAudioDeviceID` 匹配默认输出，通过 associatedAudioDeviceID 与 CoreAudio UID translation 将 AV context 映射到同一输出；请求携带设备 ID 和 UID 的 SHA-256 摘要，不按名称匹配。写前复查 CoreAudio/UID/AV 端点，写后约 1.5 秒回读；设备变化、超时、损坏 JSON、未确认状态都不能显示成功。

后台读取与用户写入的 busy 分开；相同快照不重复发布更新，避免每 3 秒禁用/闪烁控件。点击可以取消只读查询并优先写入；重复写入拒绝。待确认选中值与真实快照分开，拒绝/失败/超时回退，关闭或换设备清除。

`AirPodsContext.c` 只在新启动 helper 中适配私有 entitlement 查询，其他查询转回原函数；不注入系统进程、不修改 SIP。本地打包运行曾验证，Developer ID、公证和沙盒未验证。

### 控件的最终行为

输出设备使用真实列表与共享类别，选中项强调色、整行悬浮背景；AirPods 可展开/收起，收起保留电量，关闭面板停止读取。

聆听模式三段、对话感知两段：图标在胶囊内，名称在下方，单个选中胶囊以 220 ms ease-in-out 滑动；减少动态效果时停止滑动。水平拖动须从当前胶囊开始，只预览位置，松开按最近项提交一次请求，原项不写入，两端限位。保留点击、原生辅助功能按钮、确认期间禁用与失败回退。

### 分类图标与电量显示（2026-11-12）

`AppIcon` 按 audio、network、power、device、sound、status 分类。调用 `AppIcons.image(.audio(.airPodsPro2, part: .left))` 获取 AppKit 图像，或 `AppIcons.swiftUIImage` 获取保持字体上下文的 SwiftUI 图像。库只负责图标资源及系统缺失资源时的语义回退，不包含圆环、电量、业务优先级或交互。原图缓存不会被调用者修改；菜单栏外圈仍表示 Mac 本机电量。

音频目录保留 25 类设备的 76 个型号/部件映射（74 个不同符号），包括没有电池的 Solo Buds 仓图标；资源存在不代表应创建电量槽位。参考来自 [音频设计稿](codex://threads/01a1ca08-c30b-7bd1-bfcf-8130d29f94b7) 和 [全部中央图标](codex://threads/01a1ca07-6564-7d40-bce3-3f3afabb99ef)，映射与 39 个状态保存在 `Tests/Fixtures/AudioSymbols.json`、`AudioDeviceScenes.json`。

总览 44pt、详情 64pt，圆心半径 36/82、线宽 5.7/82，部件间距 34pt。设计稿的图标遮罩框为直径的 75%，框内原始素材还有 84/112 的留白比例；原生符号按两者相乘拟合，保留原始宽高比。`AudioSymbolBounds.json` 记录批准素材的实际可见边界，用于逐型号/左右/仓验证总览和详情的光学尺寸。阈值为 0–20 红、21–40 黄、41–100 绿；未知常显破折号；悬停显示无百分号数字，点击切换数字显示，控件不获取键盘焦点、不绘制焦点圈，减少动态效果时直接切换。

`AudioBatteryDevice` 仅在双耳值均已知、明确均入仓、且同时充电或同时确认充满时合并，取较低电量；混合状态保持分耳。充电、充满和入仓均须独立信号，100 不推导充满。**当前 helper 只读取百分比及产品元数据，没有可靠的充电/入仓采集路径，因此真实设备不会显示推测的闪电或合并状态。** 模型与视图已覆盖这些状态，接入新来源时须先验证字段语义与设备身份。

产品 ID 表覆盖 18 个图标族、34 个产品 ID；Apple vendor `76` / `1452` 才能命中，改名或粗略 CoD 不覆盖产品身份。另 7 个目录项（通用头戴、耳塞、入耳、无柄、骨传导、助听器、音箱）是类别资源，不代表能自动识别每个品牌型号。Beats Solo/Studio 等头戴型号共用设计稿指定的 `beats.headphones`，BeatsX/Flex 共用 `beats.earphones`，AirPods 1/2 共用 `airpods`；一一对应指型号落到其批准图标族和正确部件，不承诺每个产品 ID 有独立图形。

2026-11-12 的对应关系复核补齐：

| 产品 / 图标族 | 产品 ID | 证据 |
| --- | --- | --- |
| AirPods 4 | `2019 / 201B / 201C / 201E / 2020` | CoreTypes-0019 的 `com.apple.airpods-gen4`，含全部左右/仓符号；不按 ANC 分图 |
| AirPods Pro 3 | `2027 / 2028` | 用户确认、本机报告与 helper 实读 `2027`；CoreTypes-0028；SFHeadphoneProduct 的 alternate ID `2028` |
| Powerbeats Pro 2 | `201D` | CoreTypes-0016 的 `com.apple.power-beats-pro-gen2`；MagicPodsCore 及 omapods 交叉确认 |
| Beats Solo Buds | `2026` | CoreTypes-0018 的 `com.apple.beats-solo-buds` 及完整部件符号；SFHeadphoneProduct 明确仓无电池 |
| Beats Pill | `201A` | CoreTypes-0018 的 `com.apple.beats-pill`，指定 `beats.pill.fill` |
| Beats Solo 4 / Beats 360 | `2025 / 2038` | CoreTypes-0015 / 0039；沿用 Beats 头戴图标族 |
| AirPods Max 2 / Powerbeats Fit | `202D / 202F` | CoreTypes-0038 / 0027 分别继承 `com.apple.airpods-max` / `com.apple.beats-fit-pro` 的图标族 |

以上 ID 以十六进制表示。本机只读证据来自 `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/CoreTypes-*.bundle/Contents/Info.plist` 的 `public.bluetooth-vendor-product-id`、`UTTypeIcons` 和 `UTTypeConformsTo`，以及 Sharing.framework 静态产品元数据；生产代码不依赖这些私有查询。既有型号参考 [AirBattery](https://github.com/lihaoyun6/AirBattery/blob/main/AirBattery/Supports/Supports.swift)；新增 Beats 交叉来源为 [MagicPodsCore](https://github.com/steam3d/MagicPodsCore/commit/7a74e68fec4a6a3c2dbc093b0b7a94926fadfa58)、[omapods](https://github.com/cempack/omapods/commit/887db96520f570b696d6e0b17fef261db4e23da4) 和 [pods-control](https://github.com/raulgg/pods-control/commit/48c3c2db0382f16f3922ceca09f260fac22f85a0)。其他未列入批准目录的代数或未知 ID 保持通用，不凭名字猜代际。

助听器请求左右部件时保持助听器图标，没有仓的设备不返回虚构仓；系统缺失资源时，Apple TV、HomePod、车载和音箱维持各自类别。Solo Buds 仓图标保留，但忽略任何仓电量字段。`AudioProductIDs.json` 的回归逐项覆盖所有已确认 ID、两个 vendor、设备改名/误导 CoD、中央与电量部件一致性以及单电池/无仓电池语义。

当前实机确认仅为 AirPods Pro 3：vendor `0x004C`、product `0x2027`、固件 `9B47`；其他型号映射证据不替代连接态测试。legacy getter 的 0 仍按未知处理；显式且可靠的 0 值可由数据边界接受。读取时间只表示主机最近成功查询，不能保证设备固件已刷新其缓存。

后台验证覆盖符号映射/回退/副本隔离、39 个设计场景、144 组合的合并约束、阈值、过期、取消、异常元数据、原生辅助 helper，以及浅深色离屏渲染。后台测试不替代真实连接、充电/入仓、开合盖、休眠恢复或实际键盘焦点验收。

### 本机历史观测与验证

未适配时共享音频 context 不可用；适配后可读模式与对话感知。降噪↔通透、降噪↔自适应、对话感知关闭↔开启经独立进程回读通过并恢复原状态。Normal 未确认，空间音频多种 setter 未确认持久变化，这些失败不计入通过项。

日常检查用 `./verify.sh`；`Tests/Audio/AirPodsTests.swift` 覆盖声道选择、异常字段、身份/旧设备、重复操作、未确认写入、损坏 JSON、进程失败、超时、取消、静默轮询、待确认与拖动几何。真实设备脚本默认只读，`--write` 会改变设置并逐项恢复，需在明确开展硬件验证时使用：

```sh
python3 Tests/Tools/airpods-live-check.py '<已构建 Combo.app 的路径>'
python3 Tests/Tools/airpods-live-check.py '<已构建 Combo.app 的路径>' --write
```

多耳机、改名、断开重连、睡眠唤醒、不同型号/固件与系统版本仍需实机覆盖；历史构建通过不表示本次重新测试。

### 电量来源与扩展研究

2026-09-22 的资料研究并入本节，用于更多型号与 [关联设备外圈规划](../research/roadmap.md)，不是“AirPods 电量尚未实现”的计划。

| 路线 | 已核查证据 | 取舍与限制 |
| --- | --- | --- |
| IOBluetooth 私有 getter | Hammerspoon 声明 `batteryPercentLeft/Right/Case/Single`；PairPods 0.7.0 按地址匹配后读取 | 当前采用同类私有路线；公开框架不令私有 selector 成为公共 API |
| `system_profiler SPBluetoothDataType -json -timeout 10` | MacSweep/AirBattery 解析 Main/Left/Right/Case 字段 | 未采用轮询；报告可能缺字段或缓存，不是专门电量 SDK |
| CoreBluetooth 厂商广播 | AirBattery 解析 `CBAdvertisementDataManufacturerDataKey` 与缺失标记 | 公开扫描不等于 Apple 公开协议；型号、精度、开合盖与权限仍需维护 |

Hammerspoon 注释提醒充电盒休眠常返回零，左右耳字段可能只反映出盒时读数。PairPods 非正数当缺失的策略不能证明真实 0% 与未知已完全区分。来源设备、采集时间与设备上报时间不同；扩展时须分别保存左右耳/盒子、有效/未知/过期/断开，不用未知值参与最低电量，不把盒子纳入双耳主显示。固定绑定、身份和外圈空态仍属规划。

### 来源

以下为历史来源，本次整理未重新在线核查或安装上游项目：

- [Hammerspoon 固定电量源码](https://github.com/Hammerspoon/hammerspoon/blob/c317acb9c46ae9f91c0e39cf06e39eade9333614/extensions/battery/libbattery.m#L158-L213)、[Apple IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice)：公开连接字段与私有电量属性的边界。
- [PairPods 0.7.0](https://github.com/wozniakpawel/PairPods/releases/tag/v0.7.0)、[查询源码](https://github.com/wozniakpawel/PairPods/blob/ba8aece8f1378b42768cfead705404ba2ae04761/PairPods/AudioDevice.swift#L368-L408)：地址匹配与私有字段容错。
- [AirBattery 固定 BLE/报告源码](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift)、[MacSweep](https://github.com/VincentShipsIt/macsweep.dev/blob/master/MacSweep/Sources/Core/Monitoring/ConnectedDevice.swift)：未采用的其他电量路径。
- [airpods-control 私有接口](https://github.com/raulgg/airpods-control/blob/main/Sources/AirPodsControl/PrivateAudio.swift)、[安全模型](https://github.com/raulgg/airpods-control/blob/main/SECURITY.md)、[兼容矩阵](https://github.com/raulgg/airpods-control/blob/main/docs/compatibility.md)：模式字符串、进程内适配与上游硬件验证，不替代 Combo 验收。
- [AudioSwitch 音量回退](https://github.com/iamzifei/audioswitch/blob/main/Sources/AudioSwitchCore/VolumeController.swift)、[switchaudio-osx](https://github.com/deweller/switchaudio-osx)：CoreAudio 参考，未引入整个应用。
- [Apple App Review 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)：第三方可实现与私有路线可提交商店是不同结论，不保证审核结果。

<a id="bluetooth"></a>

## 蓝牙设备分类

### 1. 当前范围

CoreAudio 默认输出的 transport 为 `'blue'` / `'blea'` 才进入蓝牙分类；当前输出切到内置、USB 或 HDMI 时中央恢复既有网络/电量内容。播放与暂停只影响底部音柱，不能决定哪台设备是当前输出。配对表不能作为入口，因为 Apple TV / HomePod 也可能在表里。AirPlay 是另一条平级分支，见 [AirPlay / HomePod 实现](audio.md#airplay)。

中央、声音面板与输出列表共用 `OutputDeviceClassifier` 的分类结果；`outputIsAirPods` 保留为派生的耳机控制条件。类别不代表设备的具体产品型号，也不保证非 Apple 设备的类型正确。

### 2. 信号供给与身份

`classOfDevice` 已由现有 AirPods helper 的 `--status` 回复供给：读取对应已连接 `IOBluetoothDevice` 的公开 getter，复用 `outputAudioDeviceID` 与默认输出 UID SHA-256 token 匹配。回复在宿主复核设备 ID 与 token 后使用，避免给当前输出套上另一台已配对设备的类别。CoD 为 0、缺失或无效时忽略，既有名称分类仍可工作。

读取需蓝牙已授权，且真实 live 面板活动、屏幕未休眠；所有蓝牙音频输出复用每 3 秒的状态更新。不另起 `system_profiler`，不在主进程增加 IOBluetooth 设备枚举。共享状态读取由 Store 管理，避免两个 `PanelView` 实例争抢同一个取消任务。具体权限复用、连接设备字段与面板生命周期仍需实机回归。

### 3. 分类顺序与映射

分类顺序为 AirPods / Beats 品牌名称 → 非 0 且可分类的 CoD → 通用名称关键字 → unknown。CoD 只识别为耳机时，允许名称中的真无线、入耳式、无柄式或骨传导描述进一步细分；音箱、车载与助听设备的 CoD 分类仍优先。品牌名保留机型族；CoD 是设备自报的弱信号，仍可能错报或为空，不能据此承诺分类百分之百正确。

| 类别 | 当前信号 | SF Symbol | 实机边界 |
| --- | --- | --- | --- |
| AirPods Pro | 名称含 `AirPods Pro` | 型号未知时 `earbuds` | 具体代数须有结构化产品 ID |
| AirPods Max | 名称含 `AirPods Max` | `airpods.max` | 名称可被用户改变 |
| 其它 AirPods | 名称含 `AirPods` | 型号未知时 `earbuds` | 不按名称猜 1/2/3/4 代 |
| Beats | 名称含 `Beats` | 型号未知时 `headphones` | 结构化产品 ID 或独立左右数据可细分 |
| 耳机 | Audio/Video CoD minor `0x01` / `0x02` / `0x06`；或 `Headphone` / `WH-` / `QC-` 等关键词 | `headphones` | CoD 自报弱信号 |
| 真无线 | `Buds` / `Earbuds` / `FreeBuds` 关键词 | `earbuds` | 通用名称规则，未逐设备实测 |
| 入耳式 | `In-ear` / `InEar` / `入耳`；排除 `Non-in-ear`、`Not in ear`、`半入耳` 与 `非入耳` | `earbuds.in.ear` | 名称明确描述外形时识别，不按品牌推断 |
| 无柄式 | `Stemless` / `无柄` | `earbuds.stemless` | 名称明确描述外形时识别，优先于泛称入耳式 |
| 骨传导 | `Bone conduction` / `骨传导` | `earbuds.bone.conduction` | 不将所有开放式耳机或整个 Shokz 品牌视为骨传导 |
| 音箱 | Audio/Video CoD minor `0x05` / `0x0a`；或 `Speaker` / `SoundLink` / `Soundbar` | `hifispeaker.fill` | 未实测蓝牙音箱 |
| 车载 | Audio/Video CoD minor `0x08`；或 `Car` / `车载` 关键词 | `car.fill` | 未实测车载设备 |
| 助听器 | CoD major `0x09` | `hearingdevice.ear` | 未实测；不是所有 Health 设备的可靠身份保证 |
| 未知蓝牙 | 上述规则未命中 | `headphones` | 通用回退 |

CoD 为 24 位：`major = (cod >> 8) & 0x1F`，`minor = (cod >> 2) & 0x3F`；表里的 Audio/Video minor 只在 `major == 0x04` 时有效。英文通用关键词按词边界匹配，避免把 `Carl's Headphones` 当车载、把 `Rosebuds` 当真无线；带数字后缀的 `Buds2` 可命中。

外形描述忽略英文大小写，词间空格与连字符等分隔符按词边界处理；拿不到明确描述时仍用已有通用图标，不增加未经核实的第三方产品 ID。细分类别同时传入已有状态读取的图标家族回退，避免下一次蓝牙状态更新把中央符号覆盖成通用耳机。Apple / Beats 的可靠产品 ID 仍优先于名称描述。此处仅补整副设备的分类与中央图标映射，不新增单耳或充电盒功能，也不改变中央尺寸、位置、优先级与转场。

### 4. 绘制与开销

常驻设备类型符号仍位于 P4 事件、Wi-Fi 连接/异常和优先电量之后；仅连着耳机而默认输出在扬声器时不显示中央耳机符号。默认输出设备 ID 实际改变时新增 P4 提示，暂时显示新输出已有的图标，包含内置、显示器及其他输出；首次读取与同设备元数据更新不触发，沿用现有单事件替换与电源提示时序。具体型号优先使用通过 vendor/product ID 确认的 `AudioIconFamily`，中央和电量区域共用结果；仅有名称时不选择具体代数。缺失资源按部件语义回退，保留左右部件标识。

`AppIcons` 缓存中性 SF Symbol 原图与缺失名称，每次返回独立配置副本；颜色在业务绘制时应用。没有新增第三方依赖、常驻分类 helper 或 `system_profiler` 查询；新增 CoD 字段复用已有 status 请求。耗电、CPU 与实际进程开销尚无测量，不写估算数字。

### 5. 检查与未实机验证项

`./verify.sh` 的输出设备、AirPods helper 与图标检查覆盖 transport 入口、品牌/CoD/通用名称顺序、CoD 位域与零值、改名回退、符号解析及中央/列表一致性。AirPlay 的异步路由与发现检查另见 [AirPlay 文档](audio.md#airplay)。自动化覆盖不等于各硬件类别已验收，测试通过与否以实际运行结果为准。

仍需真实连接设备确认：默认输出 transport/UID 与 helper 身份匹配、公开 CoD getter 的取值、蓝牙授权后回流、快速切换/断开/睡眠唤醒、两个面板实例的读取生命周期。音箱、车载、助听器、LE Audio、改名 AirPods 与 macOS 26 尚未完成实机回归。历史配对表采集只能证明字段当时存在，不能替代连接态读数或具体型号证据。

不解析 Apple BLE 广播、不用私有 `CBProductInfo` 推型号、不引入空间音频或接收端播放控制。需要精确产品型号时，先取得可复核的身份与型号证据，再增加映射。

### 6. API 证据与历史观测

2026-10-03 取证时默认输出为内置扬声器，没有已连接蓝牙音频设备；配对表与头文件不是连接态实测。以下来源继承历史核查，本次未重新在线核查。

| 信息 | 接口 / 证据 | 限制 |
| --- | --- | --- |
| 当前输出身份 | `kAudioHardwarePropertyDefaultOutputDevice`、`kAudioDevicePropertyDeviceUID`、`kAudioObjectPropertyName` | UID 是身份线索，不是型号名；生产匹配须核对实时连接与 helper token |
| 蓝牙 / LE transport | 公开 SDK `AudioHardwareBase.h`：`'blue'` / `'blea'` | 两种不同传输；仅配对不能作为默认输出 |
| 类别 | 公开 `IOBluetoothDevice.classOfDevice` 与 `BluetoothAssignedNumbers.h` | 自报弱信号，0/缺失必须回退；CoreAudio 不直接提供耳机/车载等类别 |
| 精确型号 | 系统报告 `device_productID` 或私有 `CBProductInfo` | 当前未采用，不能把 HAL ModelUID 当型号 |
| 播放状态 | 当前 [MediaRemote helper](media.md) | 不提供输出设备身份，不能以 playing 判设备类型 |

#### 系统报告的历史字段

`system_profiler SPBluetoothDataType -json` 按 `device_connected` / `device_not_connected` 分桶，无连接时前者可能整体缺失。历史配对的 Apple 设备有地址、vendor/product ID、minorType、固件，耳机另有盒子与左右耳字段；其他记录可能只有地址。`device_minorType` 不能区分 AirPods 代际，`device_rssi` 是运行时信号，不是类别。

#### 符号与属性的易错边界

本机曾逐个调用 `NSImage(systemSymbolName:accessibilityDescription:)` 核查公开耳机/音箱/车载/AirPlay 符号；`airplay.audio.fill` 当时不存在。`airpodspro` / `airpodsmax` 旧别名可以解析，不能只查 `symbol_order.plist` 就判不存在；规范名为 `airpods.pro` / `airpods.max`。私有 `speaker.bluetooth` 不作为当前中央图标资源。

`CFStringGetFromAudioObject` 不是 SDK API，CFString 属性用 `AudioObjectGetPropertyData` 读取；ModelUID 不是人类型号。`kAudioDevicePropertyDataSource` 用于线路源选择，不作为蓝牙类型依据；`SPAudioDataType` 的 Transport 也可能 Unknown。

来源：[Apple IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice)、[Bluetooth SIG 类别表](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/Assigned_Numbers.pdf)、[蓝牙沙盒 entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.bluetooth)，以及历史 macOS SDK 头文件和本机符号解析。未启用沙盒的原型测试不证明沙盒发行能力。

<a id="airplay"></a>

## AirPlay 路由与附近发现

### 1. 当前范围

| 能力 | 当前行为 | 验证边界 |
| --- | --- | --- |
| 当前输出识别 | CoreAudio 默认输出的 transport 为 `'airp'` 才进入 AirPlay 分类 | 历史 Apple TV 路由采集确认过；当前异步实现仍需实机回归 |
| 名称与图标 | helper 读取已建立路由的名称、机型；中央与输出列表共用同一结果 | Apple TV 历史值为 `AppleTV14,1` / `客厅`；HomePod 未实机验证 |
| 附近设备 | 用户首次点击“查找”后，`NWBrowser` 浏览 `_airplay._tcp` 及 TXT；点击结果打开系统声音设置 | 原始 Bonjour 采集可见 Apple TV；当前权限、生命周期与界面未完成端到端实机验证 |
| 建立全系统路由 | 保留系统声音设置入口，由用户选择 | 不承诺应用内一键连接未路由设备；`AVRoutePickerView` 也未验证可改系统默认输出 |
| 音量 | CoreAudio 软件输出音量与接收端设备音量分开说明 | 历史 Apple TV `canSetVolume = false`，显示“电视音量请用遥控器”；未知能力不画成支持或拒绝 |

### 2. 路由探测与身份

已建立的 AirPlay 路由使用既有 `ComboAirPodsHelper` 与 `ComboAirPodsContext.dylib`，调用 `--route <deviceID> <UID SHA256>`。每次是短进程，宿主超时为 2 秒；回复必须通过 deviceID、UID token、关联 context 与 endpointID 校验。`AirPlayRoute.Request` 包含 UUID 序号，即使系统重用设备 ID，旧请求也不能回填新结果。新请求取消旧任务及进程；没有默认输出或离开 AirPlay 时取消并清缓存；唤醒先失效再重读。

helper 失败、缺失、超时、身份不匹配或 context 有多个输出接收端时，名称退回 CoreAudio、符号退回 `airplay.audio`。面板提供手动重新读取；没有具体机型信号时不猜 Apple TV / HomePod。结果的 `canSetVolume` 可为空，表示未知；Mac 软件输出音量可写不等于接收端硬件音量可控。

| `modelID` | 符号 | 依据 |
| --- | --- | --- |
| `AppleTV*` | `appletv` | 历史 Apple TV `AppleTV14,1` 实测 |
| `AudioAccessory5*` | `homepod.mini` | 第三方机型表推导，未实机验证 |
| 其它 `AudioAccessory*` | `homepod` | 当前家族映射；未来机型仍需复核 |
| 未知、空或探测失败 | `airplay.audio` | 通用回退 |

`.2` 后缀的 HomePod SF Symbol 表示两个设备，不表示二代；当前不按代际或多房间分组绘制。

### 3. 附近发现与权限

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

### 4. 开销与检查

路由查询在输出变化、手动重读、唤醒或活动面板触发；初始失败按 0.5/1/2 秒有限重试，真实活动面板默认每 3 秒重新确认路由，以覆盖 CoreAudio 身份未变而接收端切换的情况。每次为短进程；附近浏览只在用户 opt-in 后的活动真实面板运行，不是常驻扫描。共享绘图缓存固定的 16 个 SF Symbol 原图，每次绘制应用当前颜色；未知符号名不进入缓存。没有实测耗电数字，不宣称新增开销为零。

`Tests/Audio/AirPlayRouteTests.swift` 与 `Tests/Audio/AirPlayDiscoveryTests.swift` 已接入 `./verify.sh`，覆盖异步取消、过期结果、路由切换、超时、权限拒绝与普通网络故障区分；`Tests/Views/PanelMotionTests.swift` 与 `Tests/Views/PanelDismissTests.swift` 覆盖不依赖 key 的外部点击、详情/图标内部点击、长时间授权保护、授权结束、应用/Space 切换、主动收起及动画。分类、符号回退与中央/列表一致性由现有输出设备及图标检查覆盖。检查结果以实际运行输出为准，历史 Apple TV 采集不代表当前功能已经实机通过。

待实机回归：首次本地网络弹窗与拒绝/重试、面板关闭/演示/睡眠及唤醒、快速切换与设备 ID 复用、HomePod 全尺寸/mini、多设备、AirPlay 1、蓝牙与 AirPlay 并存及 macOS 26。保留系统声音设置；不捆绑 pyatv/owntone 等运行时，不实现 HomePod 接收端播放控制或音频投送。

### 5. API 证据与历史观测

以下为 2026-10-03 的取证记录，环境 macOS 27.0 build `26A428`。网络中只有 Apple TV（tvOS 26.6），没有 HomePod；本次整理未重新在线核查、建立路由或查询设备。

#### 同一 Apple TV 的三条来源

| 来源 | 历史返回 | 可支持的结论 |
| --- | --- | --- |
| Bonjour `_airplay._tcp` | 实例名“客厅”，TXT `model=AppleTV14,1` | 免配对发现名称/机型；仍需要自建浏览及本地网络授权 |
| 已激活 CoreAudio 路由 | transport `'airp'`，名称 `AirPlay`，UID/ModelUID 为不透明 UUID | 当前输出可识别 AirPlay，但本机该路由未给房间名或机型 |
| AVRouting SPI，经 helper context 适配 | name/deviceName“客厅”，modelID `AppleTV14,1`，`canSetVolume=false` | 本机已建立路由可读名称/机型；设备自身音量不可控 |

Bonjour 的 deviceid/psi 与 SPI 的设备身份一致，AV context 的 associatedAudioDeviceID 与 CoreAudio UID 一致。当前仍需完整 token/context/endpoint 校验，不能拿历史单设备一致性替代多设备验证。未适配时 sharedSystemAudioContext 为 nil；helper 应在不初始化 AppKit 的宿主中运行。

未激活时 Bonjour 可见 Apple TV，普通 CoreAudio 数组没有 `'airp'`；激活后可列出，切回内置扬声器后设备消失。此现象只证明该客户端和当时路由行为，不能推出所有公开激活路径都不存在。

Mac 软件输出音量/静音历史可写，接收端 AVOutputDevice 的 canSetVolume/canMute 为 false；两者不可混称。历史方法表未找到接收端 play/pause/next/previous；MediaRemote 控本机播放源。发现会话的多种 SPI 构造曾返回 nil，尚未打通未路由设备的连接；有分组接口不等于多房间已验证。

#### 公开与私有接口

| 接口 | 历史核查能力 | 对当前功能的含义 |
| --- | --- | --- |
| CoreAudio 普通 AudioDevice + 默认输出属性 | 已列出且合格的设备可按默认输出路径切换 | Bonjour 结果不是 AudioObjectID；默认系统提示输出也不是普通媒体默认输出 |
| `AVRouteDetector` | 只有 multipleRoutesDetected 布尔 | 不能取得接收器列表 |
| `AVRoutePickerView.player` | 原生 macOS 面向 `AVPlayer` 应用媒体路由 | player 为 nil 不保证控制系统默认输出；不是自定义列表数据源 |
| `AVOutputDevice` / Context / DiscoverySession | SDK 无公开头文件的 AVRouting SPI | 运行时存在、能读取、能连接、可长期兼容须分别验证 |
| `AVCustomRoutingController` | 历史 SDK 为原生 macOS unavailable | Catalyst 可用不等于原生 macOS可用 |
| `AVSystemRouteController` | 当时官方 metadata 为 iOS/iPadOS/Mac Catalyst 27 | 不作为当前原生 macOS 系统输出控制依据 |

#### 全系统切换的公开候选与探针

公开 SDK 还有 AudioTransportManager/AudioEndPointDevice：先读 `kAudioHardwarePropertyTransportManagerList`、transportType、EndPointList，再用 `kAudioTransportManagerCreateEndPointDevice` 请求组合成 AudioDevice。即便通过 GetPropertyData selector 调用，create 本身有副作用；endpoint ID 不能直接当默认输出 ID。设备描述有 UID/Name/EndPointList/MainEndPoint，`IsPrivate=0` 表示全系统，1 表示仅本进程。

未连接时的只读探针：transport manager 查询 OSStatus=0、大小=0；存在 `com.apple.AirPlayXPCHelper` 插件对象，但其 `end#` 返回 unknown property (`2003332927`)，`cdev` 不存在。没有创建/销毁设备或改变输出。这说明当时没有可操作的公开 endpoint，不证明激活后的状态相同。

后续候选需证明接收器激活、默认输出回读和其他应用的实际音频传输；覆盖首次连接、配对重连、离线、取消 PIN/密码、面板关闭及恢复内置。可在系统 UI 激活后复测公开 manager/endpoint，或隔离验证私有系统路由。仅 selector 存在或调用无异常不算成功。辅助功能点击系统界面是另一路 UI 自动化，受权限/语言/布局影响，当前仍保留系统设置入口。

#### 型号与发现范围

[libirecovery 机型表](https://cgit.libimobiledevice.org/libirecovery.git/plain/src/libirecovery.c)历史记录：HomePod `AudioAccessory1,1` / `1,2`，mini `5,1`，二代 `6,1`；这不是本机 HomePod 实测。`.2` 的 SF Symbol 表示两台设备，不表示二代，当前仅区分全尺寸/mini/Apple TV/通用。

本机 Apple TV 同时广播 `_airplay._tcp` 与 `_raop._tcp`，不能推广所有设备；本机自身也出现在 Bonjour 结果中，发现不证明远端可连接。`_homekit._tcp` 当时无结果，HomePod 是否广播未验收。蓝牙配对表中的 Apple TV 也不能作为蓝牙音频分类入口。

#### 权限与发行边界

历史 [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) 核查指出自建 Bonjour 操作需要本地网络访问，macOS 不需要 multicast entitlement。高层 AirPlay 服务的豁免不能泛化为 Combo 自建浏览免授权。系统可能在用户作答前先拒绝操作，需要区分权限拒绝/普通故障并支持重试。

本地网络隐私用代码签名跟踪程序身份，历史 ad-hoc 开发环境不证明发行身份或重新编译后的授权稳定。首次真实弹窗、拒绝/重试与面板保护仍需当前签名应用实测。

#### 上游研究与来源

历史调查中 [pyatv](https://github.com/postlund/pyatv) / [能力表](https://pyatv.dev/documentation/supported_features/) 是发送/控制候选，需 Python 与部分设备配对凭据；RAOP 控制、HomePod Companion pairing 与 HAP 能力有独立限制，不保证 HomePod 全功能。[owntone](https://github.com/owntone/owntone-server) 是发送守护进程；shairport-sync、RPiPlay、airplay2-receiver 等是接收端，不能据此承诺控制 HomePod。Combo 未捆绑这些运行时；[airplay-cli](https://github.com/bpetrynski/airplay-cli) 是 Bonjour 与系统 UI 自动化参考，不是通用路由 API。

主要公开来源：[AVRoutePickerView.player](https://developer.apple.com/documentation/avkit/avroutepickerview/player)、[默认输出属性](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice)、[TransportManager 列表](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertytransportmanagerlist)、[创建 EndPointDevice](https://developer.apple.com/documentation/coreaudio/kaudiotransportmanagercreateendpointdevice)、[设备私有范围](https://developer.apple.com/documentation/coreaudio/kaudioendpointdeviceisprivatekey)、[AVSystemRouteController](https://developer.apple.com/documentation/avsystemrouting/avsystemroutecontroller-18ns8)。本机 SDK 的 AudioHardware.h、AudioHardwareBase.h、AVRoutePickerView.h 与 AVRouting.tbd 补充历史头文件/导出符号证据。
