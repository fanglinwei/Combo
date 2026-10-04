# 按蓝牙设备类型切换中央图标：实现与验证边界

整理：2026-10-04；实现与历史取证：2026-10-03。环境为 macOS 27.0（Build 26A428）、Apple Silicon、自用 ad-hoc 原型。本文合并当前分类实现与历史 API 证据；历史采集不代表连接态硬件已经验收。

## 1. 当前范围

CoreAudio 默认输出的 transport 为 `'blue'` / `'blea'` 才进入蓝牙分类；当前输出切到内置、USB 或 HDMI 时中央恢复既有网络/电量内容。播放与暂停只影响底部音柱，不能决定哪台设备是当前输出。配对表不能作为入口，因为 Apple TV / HomePod 也可能在表里。AirPlay 是另一条平级分支，见 [AirPlay / HomePod 实现](airplay-homepod-icon-research.md)。

中央、声音面板与输出列表共用 `OutputDeviceClassifier` 的分类结果；`outputIsAirPods` 保留为派生的耳机控制条件。类别不代表设备的具体产品型号，也不保证非 Apple 设备的类型正确。

## 2. 信号供给与身份

`classOfDevice` 已由现有 AirPods helper 的 `--status` 回复供给：读取对应已连接 `IOBluetoothDevice` 的公开 getter，复用 `outputAudioDeviceID` 与默认输出 UID SHA-256 token 匹配。回复在宿主复核设备 ID 与 token 后使用，避免给当前输出套上另一台已配对设备的类别。CoD 为 0、缺失或无效时忽略，既有名称分类仍可工作。

读取需蓝牙已授权，且真实 live 面板活动、屏幕未休眠；普通蓝牙输出每次活动/目标变化读取一次，当前 AirPods 复用原有每 3 秒状态更新。不另起 `system_profiler`，不在主进程增加 IOBluetooth 设备枚举。共享状态读取由 Store 管理，避免两个 `PanelView` 实例争抢同一个取消任务。具体权限复用、连接设备字段与面板生命周期仍需实机回归。

旧版“CoD 没有生产者”“必须先在主进程接入 IOBluetooth”已失效；旧版 `system_profiler` 产品 ID 增强是未采用的研究方案。当前不内置未经证实的产品 ID 表、不轮询系统报告；`0x2014` 的具体型号仍未确认。改名 AirPods 若没有产品型号信号，仅凭 CoD 不能恢复其型号，仍会显示通用类别。

## 3. 分类顺序与映射

分类顺序为 AirPods / Beats 品牌名称 → 非 0 且可分类的 CoD → 通用名称关键字 → unknown。品牌名保留机型族；CoD 可以优先于通用名称，但它是设备自报的弱信号，仍可能错报或为空。不能据此承诺音箱、车载、助听器百分之百正确。

| 类别 | 当前信号 | SF Symbol | 实机边界 |
| --- | --- | --- | --- |
| AirPods Pro | 名称含 `AirPods Pro` | `airpods.pro` | 型号族，不细分 Pro 代际 |
| AirPods Max | 名称含 `AirPods Max` | `airpods.max` | 名称可被用户改变 |
| 其它 AirPods | 名称含 `AirPods` | `airpods` | 不用未验证产品 ID 猜 3/4 代 |
| Beats | 名称含 `Beats` | `beats.headphones` | 不细分各产品型号 |
| 耳机 | Audio/Video CoD minor `0x01` / `0x02` / `0x06`；或 `Headphone` / `WH-` / `QC-` 等关键词 | `headphones` | CoD 自报弱信号 |
| 真无线 | `Buds` / `Earbuds` / `FreeBuds` 关键词 | `earbuds` | 通用名称规则，未逐设备实测 |
| 音箱 | Audio/Video CoD minor `0x05` / `0x0a`；或 `Speaker` / `SoundLink` / `Soundbar` | `hifispeaker` | 未实测蓝牙音箱 |
| 车载 | Audio/Video CoD minor `0x08`；或 `Car` / `车载` 关键词 | `car` | 未实测车载设备 |
| 助听器 | CoD major `0x09` | `hearingdevice.ear` | 未实测；不是所有 Health 设备的可靠身份保证 |
| 未知蓝牙 | 上述规则未命中 | `headphones` | 通用回退 |

CoD 为 24 位：`major = (cod >> 8) & 0x1F`，`minor = (cod >> 2) & 0x3F`；表里的 Audio/Video minor 只在 `major == 0x04` 时有效。英文通用关键词按词边界匹配，避免把 `Carl's Headphones` 当车载、把 `Rosebuds` 当真无线；带数字后缀的 `Buds2` 可命中。

## 4. 绘制与开销

设备类型符号仍位于音量/电源事件、Wi-Fi 连接/异常和优先电量之后，不改变状态机层级；仅连着耳机而默认输出在扬声器时不显示中央耳机符号。缺失资源统一退回 `headphones`，不能留下空白。

共享渲染缓存固定的 16 个 SF Symbol 原图，颜色在每次绘制时应用；未知符号名不缓存。没有新增第三方依赖、常驻分类 helper 或 `system_profiler` 查询；新增 CoD 字段复用已有 status 请求。耗电、CPU 与实际进程开销尚无测量，不写估算数字。

## 5. 检查与未实机验证项

`./verify.sh` 的输出设备、AirPods helper 与图标检查覆盖 transport 入口、品牌/CoD/通用名称顺序、CoD 位域与零值、改名回退、符号解析及中央/列表一致性。AirPlay 的异步路由与发现检查另见 [AirPlay 文档](airplay-homepod-icon-research.md#4-开销与检查)。自动化覆盖不等于各硬件类别已验收，测试通过与否以实际运行结果为准。

仍需真实连接设备确认：默认输出 transport/UID 与 helper 身份匹配、公开 CoD getter 的取值、蓝牙授权后回流、快速切换/断开/睡眠唤醒、两个面板实例的读取生命周期。音箱、车载、助听器、LE Audio、改名 AirPods 与 macOS 26 尚未完成实机回归。历史配对表采集只能证明字段当时存在，不能替代连接态读数或具体型号证据。

不解析 Apple BLE 广播、不用私有 `CBProductInfo` 推型号、不引入空间音频或接收端播放控制。需要精确产品型号时，先取得可复核的身份与型号证据，再增加映射。

相关：[声音与 AirPods](airpods-audio-feasibility.md) · [中央状态优先级](combo-settings.md#31-中央状态优先级2026-09-24)。

## 6. API 证据与历史观测

2026-10-03 取证时默认输出为内置扬声器，没有已连接蓝牙音频设备；配对表与头文件不是连接态实测。以下来源继承历史核查，本次未重新在线核查。

| 信息 | 接口 / 证据 | 限制 |
| --- | --- | --- |
| 当前输出身份 | `kAudioHardwarePropertyDefaultOutputDevice`、`kAudioDevicePropertyDeviceUID`、`kAudioObjectPropertyName` | UID 是身份线索，不是型号名；生产匹配须核对实时连接与 helper token |
| 蓝牙 / LE transport | 公开 SDK `AudioHardwareBase.h`：`'blue'` / `'blea'` | 两种不同传输；仅配对不能作为默认输出 |
| 类别 | 公开 `IOBluetoothDevice.classOfDevice` 与 `BluetoothAssignedNumbers.h` | 自报弱信号，0/缺失必须回退；CoreAudio 不直接提供耳机/车载等类别 |
| 精确型号 | 系统报告 `device_productID` 或私有 `CBProductInfo` | 当前未采用，不能把 HAL ModelUID 当型号 |
| 播放状态 | 当前 [MediaRemote helper](media-implementation-evidence.md) | 不提供输出设备身份，不能以 playing 判设备类型 |

CoD 公开常量：Audio/Video major `0x04`、Wearable `0x07`、Health `0x09`；Audio minor 中耳麦 `0x01`、Hands-free `0x02`、音箱 `0x05`、耳机 `0x06`、便携 `0x07`、车载 `0x08`、HiFi `0x0a`、游戏/玩具 `0x12`。这些标签本身不能保证精确产品类型，Health 不等于每台设备必为助听器。

### 系统报告的历史字段

`system_profiler SPBluetoothDataType -json` 按 `device_connected` / `device_not_connected` 分桶，无连接时前者可能整体缺失。历史配对的 Apple 设备有地址、vendor/product ID、minorType、固件，耳机另有盒子与左右耳字段；其他记录可能只有地址。`device_minorType` 不能区分 AirPods 代际，`device_rssi` 是运行时信号，不是类别。

当时实测到产品字段 `0x2027`、`0x2014`，并未验证完整型号表。IORegistry 采到 CoD 为 0 的条目，但未逐条确认归属，不能推广为“非 Apple 设备一律为 0”。系统音频偏好中蓝牙 UID 曾呈地址形式，仍不能代替当前默认输出的实时读取。名称可改，报告有枚举成本，不用于轮询。

### 符号与属性的易错边界

本机曾逐个调用 `NSImage(systemSymbolName:accessibilityDescription:)` 核查公开耳机/音箱/车载/AirPlay 符号；`airplay.audio.fill` 当时不存在。`airpodspro` / `airpodsmax` 旧别名可以解析，不能只查 `symbol_order.plist` 就判不存在；规范名为 `airpods.pro` / `airpods.max`。私有 `speaker.bluetooth` 不作为当前中央图标资源。

`CFStringGetFromAudioObject` 不是 SDK API，CFString 属性用 `AudioObjectGetPropertyData` 读取；ModelUID 不是人类型号。`kAudioDevicePropertyDataSource` 用于线路源选择，不作为蓝牙类型依据；`SPAudioDataType` 的 Transport 也可能 Unknown。

来源：[Apple IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice)、[Bluetooth SIG 类别表](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/Assigned_Numbers.pdf)、[蓝牙沙盒 entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.bluetooth)，以及历史 macOS SDK 头文件和本机符号解析。未启用沙盒的原型测试不证明沙盒发行能力。
