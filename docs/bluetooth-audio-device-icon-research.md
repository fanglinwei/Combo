# 按蓝牙设备类型切换中央图标：实现与验证边界

更新：2026-10-03。环境为 macOS 27.0（Build 26A428）、Apple Silicon、自用 ad-hoc 原型。本文同步当前实现；历史字段取证见 [蓝牙音频输出设备识别：API 与信号证据](bluetooth-audio-device-api-evidence.md)。

## 1. 当前范围

CoreAudio 默认输出的 transport 为 `'blue'` / `'blea'` 才进入蓝牙分类；当前输出切到内置、USB 或 HDMI 时中央恢复既有网络/电量内容。播放与暂停只影响底部音柱，不能决定哪台设备是当前输出。配对表不能作为入口，因为 Apple TV / HomePod 也可能在表里。AirPlay 是另一条平级分支，见 [AirPlay / HomePod 实现](airplay-homepod-icon-research.md)。

中央、声音面板与输出列表共用 `OutputDeviceClassifier` 的分类结果；`outputIsAirPods` 保留为派生的耳机控制条件。类别不代表设备的具体产品型号，也不保证非 Apple 设备的类型正确。

## 2. 信号供给与身份

`classOfDevice` 已由现有 AirPods helper 的 `--status` 回复供给：读取对应已连接 `IOBluetoothDevice` 的公开 getter，复用 `outputAudioDeviceID` 与默认输出 UID SHA-256 token 匹配。回复在宿主复核设备 ID 与 token 后使用，避免给当前输出套上另一台已配对设备的类别。CoD 为 0、缺失或无效时忽略，既有名称分类仍可工作。

读取需蓝牙已授权，且真实 live 面板活动、屏幕未休眠；普通蓝牙输出每次活动/目标变化读取一次，当前 AirPods 复用原有每 3 秒状态更新。不另起 `system_profiler`，不在主进程增加 IOBluetooth 设备枚举。共享状态读取由 Store 管理，避免两个 `PanelView` 实例争抢同一个取消任务。具体权限复用、连接设备字段与面板生命周期仍需实机回归。

旧版“CoD 没有生产者”“必须先在主进程接入 IOBluetooth”已失效；旧版 `system_profiler` 产品 ID 增强是未采用的研究方案。本轮不内置未经证实的产品 ID 表、不轮询系统报告；`0x2014` 的具体型号仍未确认。改名 AirPods 若没有产品型号信号，仅凭 CoD 不能恢复其型号，仍会显示通用类别。

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

`./verify.sh` 的输出设备、AirPods helper 与图标检查覆盖 transport 入口、品牌/CoD/通用名称顺序、CoD 位域与零值、改名回退、符号解析及中央/列表一致性。AirPlay 的异步路由与发现检查另见 [AirPlay 文档](airplay-homepod-icon-research.md#4-开销与检查)。自动化覆盖不等于各硬件类别已验收，测试通过与否以本轮实际运行结果为准。

仍需真实连接设备确认：默认输出 transport/UID 与 helper 身份匹配、公开 CoD getter 的取值、蓝牙授权后回流、快速切换/断开/睡眠唤醒、两个面板实例的读取生命周期。音箱、车载、助听器、LE Audio、改名 AirPods 与 macOS 26 尚未完成实机回归。历史配对表采集只能证明字段当时存在，不能替代连接态读数或具体型号证据。

不解析 Apple BLE 广播、不用私有 `CBProductInfo` 推型号、不引入空间音频或接收端播放控制。需要精确产品型号时，先取得可复核的身份与型号证据，再增加映射。

相关：[声音与 AirPods](airpods-audio-feasibility.md) · [AirPods API 证据](airpods-api-evidence.md) · [中央状态优先级](combo-settings.md#31-中央状态优先级2026-09-24)。
