# 蓝牙音频输出设备识别：API 与信号证据

调研与只读取证日期：2026-10-03。环境：macOS 27.0（Build 26A428），Apple Silicon，`MacOSX.sdk`（Command Line Tools）。

本文只做 API 与信号的核查，不修改产品代码、不修改耳机设置、不安装依赖。它是[按蓝牙设备类型切换中央图标](bluetooth-audio-device-icon-research.md)的配套证据文档，对应仓库既有的“证据 + 可行性”成对惯例（见 [airpods-api-evidence.md](airpods-api-evidence.md) 与 [airpods-audio-feasibility.md](airpods-audio-feasibility.md)）。AirPlay / HomePod 的同题研究见 [中央图标支持 AirPlay / HomePod](airplay-homepod-icon-research.md) 与 [AirPlay / HomePod API 与信号证据](airplay-homepod-api-evidence.md)。

⚠️ **取证时的硬前提**：本机当时**没有任何蓝牙音频设备处于连接状态**（`system_profiler` 只有 `device_not_connected` 段，默认输出为内置扬声器）。因此蓝牙侧的**取值**来自 SDK 头文件、系统内建表与引用来源，而不是本次实测；本机实测项单独标 ✅。源码存在不等于所有 macOS 版本、所有耳机与音箱都可用。

## 结论摘要

| 想知道 | 机制 | 状态 |
| --- | --- | --- |
| 当前输出设备是哪台 | `kAudioHardwarePropertyDefaultOutputDevice` | **公开** ✅ 实测（取证时默认输出为内置扬声器） |
| 它是不是蓝牙 | `kAudioDevicePropertyTransportType` = `'blue'` / `'blea'` | **公开** ✅ 头文件实测 |
| 输出设备名 | `kAudioObjectPropertyName` | **公开**（名称形态与配对表一致；连接态未实测） |
| 与蓝牙层的连接键 | `kAudioDevicePropertyDeviceUID`（蓝牙时是 MAC 形式） | **公开** ✅ 系统 plist 已实测 MAC 形态的键（见 §1）；仅"连接态实际读取"未做 |
| 设备类别（耳机 / 音箱 / 车载 / 助听） | `IOBluetoothDevice.classOfDevice` + `BluetoothAssignedNumbers.h` 常量 | **公开，但自报不可靠** ⚠️ 本机 ioreg 中 grep 到的条目为 `ClassOfDevice = 0`（未逐条确认归属设备，见 §7） |
| 从 CoreAudio 拿类别 | — | **不可能** |
| 类别（命令行） | `system_profiler SPBluetoothDataType` 的 `device_minorType` | **公开工具，只可解析** ✅ 实测 |
| 具体机型 / 产品 ID | 私有 `CBProductInfo productInfoWithProductID` | **私有且易碎** |
| 机型（可解析路径） | `system_profiler SPBluetoothDataType -json` 的 `device_productID` + 社区机型表 | **公开工具，表需自建** ✅ 字段实测 |
| 播放 / 正在播放状态 | `MediaRemote.framework` | **私有**，macOS 15.4 起受限 |
| 沙盒内访问蓝牙 | `com.apple.security.device.bluetooth` | **entitlement**（本项目自用 ad-hoc、未开沙盒，不适用） |
| `CFStringGetFromAudioObject` | 不存在 | **不是真实 API**（CoreAudio / AudioToolbox 头文件中均无） |

## 1. CoreAudio：公开且够用

- `kAudioHardwarePropertyDefaultOutputDevice`（`kAudioObjectSystemObject` 作用域）→ 当前默认输出的 `AudioObjectID`。✅ 实测。
- `kAudioDevicePropertyTransportType` → FourCC。本机 SDK 头文件 `MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Headers/AudioHardwareBase.h` 第 614–615 行：`kAudioDeviceTransportTypeBluetooth = 'blue'`、`kAudioDeviceTransportTypeBluetoothLE = 'blea'`。两者是**不同**的 transport：`'blue'` 是经典蓝牙（A2DP/HFP），`'blea'` 是 LE Audio。✅ 头文件实测。
- `kAudioObjectPropertyName` → 用户看到的友好名，例如 `"方林威的AirPods Pro"`（该字符串取自配对表，**连接态未实测**）。
- `kAudioDevicePropertyDeviceUID` → 蓝牙设备的 UID 是 **MAC 地址**形式，而且就是 `/Library/Preferences/Audio/com.apple.audio.DeviceSettings.plist` 使用的键。✅ 本机实测（`plutil -p` 可见 `"20-52-1D-7E-9F-13:output"` 与 `:input`，以及另外两台配对设备的 `"44-1B-88-D0-66-88:…"`、`"A4-C6-F0-C0-E7-42:…"`）。⚠️ 仍未做的是"连接态下默认输出设备的 UID 实际取值"（见 §8 第 2 条）；机制本身已由系统 plist 佐证。这是把 CoreAudio 设备与蓝牙层设备对上号的**最佳连接键**。
- 变化监听用公开的 `AudioObjectAddPropertyListenerBlock`，同时挂在 `kAudioHardwarePropertyDefaultOutputDevice` 与 `kAudioHardwarePropertyDevices` 上。

**关键限制：CoreAudio 只能回答“是不是蓝牙”和“叫什么”，永远给不出类别。**

## 2. 蓝牙层：类别轴存在，但只有 IOBluetooth

`IOBluetooth` 与 `CoreBluetooth` 都是公开框架。`IOBluetoothDevice` 公开暴露 `classOfDevice`、`name`、`addressString`；类别常量在公开头文件 `BluetoothAssignedNumbers.h` 中（本机 SDK：`MacOSX.sdk/System/Library/Frameworks/IOBluetooth.framework/Headers/BluetoothAssignedNumbers.h`，major class 在 338–343 行、audio minor class 在 400–418 行 ✅ 实测；下表取值逐一核过）：

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `kBluetoothDeviceClassMajorAudio` | `0x04` | Audio/Video |
| `kBluetoothDeviceClassMajorWearable` / `MajorHealth` | `0x07` / `0x09` | 穿戴 / 健康（助听器） |
| `kBluetoothDeviceClassMinorAudioHeadset` | `0x01` | Wearable Headset |
| `kBluetoothDeviceClassMinorAudioHandsFree` | `0x02` | Hands-free |
| `kBluetoothDeviceClassMinorAudioLoudspeaker` | `0x05` | 音箱 |
| `kBluetoothDeviceClassMinorAudioHeadphones` | `0x06` | 耳机 |
| `kBluetoothDeviceClassMinorAudioPortable` | `0x07` | 便携音频 |
| `kBluetoothDeviceClassMinorAudioCar` | `0x08` | 车载 |
| `kBluetoothDeviceClassMinorAudioHiFi` | `0x0a` | HiFi |
| `kBluetoothDeviceClassMinorAudioGamingToy` | `0x12` | 游戏 / 玩具 |

这就是“耳机 / 音箱 / 车载”这条轴，但它由**设备自己上报**：很多耳机报 `0x00` 或一个笼统的耳机值。本机 `ioreg` 中 grep 到的条目为 `ClassOfDevice = 0`（见 §7 的限定：未逐条确认归属设备），所以它是**弱提示**，不能当判据。

`CoreBluetooth` 只能看到 LE 设备：经典蓝牙（BR/EDR）的 A2DP 耳机不会作为 `CBPeripheral` 出现（⚠️ 本次未复测）。沙盒应用需要 `com.apple.security.device.bluetooth` entitlement，缺了会被 App Review 拒（本项目不开沙盒，故不适用）。

## 3. 命令行取证：`system_profiler`（公开工具）

`system_profiler SPBluetoothDataType` 是公开的系统工具，只读。JSON 模式下结构为 `SPBluetoothDataType[0]`，键按连接状态分桶：`device_connected` / `device_not_connected`（**没有任何设备连接时 `device_connected` 键整体不存在**，✅ 实测）。每台设备的字段名 ✅ 实测：

| 键 | 本机 Apple 设备 | 本机非 Apple 设备 |
| --- | --- | --- |
| `device_address` | ✅ | ✅ |
| `device_vendorID` | ✅ (`0x004C`) | ✗ |
| `device_productID` | ✅ (`0x2027`) | ✗ |
| `device_minorType` | ✅（`Headphones` / `Keyboard` / `Magic Trackpad`） | ✗ |
| `device_firmwareVersion` | ✅ | ✗ |
| `device_caseVersion` / `device_serialNumber` / `...Left` / `...Right` | **只有耳机有**（本机 Apple 键鼠均无） | ✗ |
| `device_rssi` | 运行时字段（取决于设备是否正在广播），**不是类型信号** | 同左 |

要点：

1. 非 Apple 设备可能**一个类型字段都没有**，只有地址（本机的 `客厅`、`方林威的iPad`、`轻舟已过万重山` 就是如此）。这意味着“非 Apple 蓝牙设备分类”没有字段级依据。
2. 该工具**不提供 `classOfDevice` 字段**，只给已翻译好的 `device_minorType` 字符串。
3. 输出的设备名是**用户可改的**，不能当归一化键；做匹配要用 `device_address`（或 CoreAudio 的 MAC 形式 UID）。
4. 该命令有秒级开销（需枚举），不适合轮询。

## 4. 私有与不稳定接口

- `MediaRemote.framework`：私有，二进制在 dyld shared cache 中，对路径 `nm` 无输出；macOS 15.4 起受到限制（[PlayerLink 修复提交](https://github.com/EinTim23/PlayerLink/commit/9821b6a294873f975852f06419a0baf2fe404800)）。社区替代：`mediaremote-adapter`、`nowplaying-cli`。本项目已在用（[MediaPlaybackHelper.m](../Combo/Audio/MediaPlaybackHelper.m)），但只拿标题/艺人/封面/播放中，**不含输出设备**。
- `/usr/sbin/bluetoothd` 内含字符串 `CBProductInfo productInfoWithProductID`、`Error Apple Default Name not in dictionary CBProductInfo productInfoWithProductID`，以及 `AirPods Pro`、`Beats Studio Pro` 等型号串——说明存在一个私有的“产品 ID → 型号名”表。⚠️ 签名未解（二进制在 dyld cache 中），**不作为方案路径**。
- 其他私有：`BluetoothServices`、`BluetoothAudio`、`CoreBluetoothUI`、`MobileBluetooth`。
- `defaults read com.apple.bluetooth` 暴露 `lastNowPlayingTargetHeadsetAddress`（未文档化，本机实测存在）。它是“最近作为播放目标的耳机地址”，可作为“播放中”语义的附录信号，但未文档化、不纳入推荐路径。
- 磁盘上存在 `BTAudioHALPlugin.driver` 与 `HearingAudioPlugin.driver`（mach service `com.apple.accessibility.heard`）——助听器是独立的 CoreAudio 路径。
- **Apple 自家的通用蓝牙输出符号 `speaker.bluetooth` 在私有 bundle `CoreGlyphsPrivate.bundle` 里**（2020 年引入 = macOS 11），Control Center 用它，第三方不能发布。

## 5. SF Symbols 可得性（本机逐个实测）

本机用 `NSImage(systemSymbolName:accessibilityDescription:)` 逐个验证，下列全部返回非空（公开可用）：`airpods`、`airpods.pro`、`airpods.pro.gen1`、`airpods.pro.gen3`、`airpods.gen3`、`airpods.gen4`、`airpods.max`、`airpodspro`(旧别名)、`airpodsmax`(旧别名)、`airpods.pro.left`、`airpods.gen4.left`、`beats.headphones`、`beats.earphones`、`beats.powerbeats`、`beats.powerbeats.pro`、`beats.studiobuds`、`headphones`、`headphones.over.ear`、`headphones.circle`、`earbuds`、`earbuds.stemless`、`hifispeaker`、`hifispeaker.fill`、`homepod`、`hearingdevice.ear`、`gamecontroller`、`car`、`speaker.wave.2`、`airplay.audio`、`airplay.video`。（反面例子：`airplay.audio.fill` 实测返回 false，不要用它。）

容易误判的一点：`CoreGlyphs.bundle/Contents/Resources/symbol_order.plist` **只列规范名**，不含旧别名；旧别名改写记录在 `name_availability.plist`。所以按 `symbol_order.plist` 检索会得出“`airpodspro`/`airpodsmax` 不存在”的错误结论——实际两者都能解析（实测 `true`）。反过来，规范名是带点的 `airpods.pro` / `airpods.max`。

**没有任何公开 API 会告诉你“这台设备该用哪个符号”，映射表必须自建。**

## 6. 易错点清单

1. `CFStringGetFromAudioObject` **不是真实 API**（本机 SDK 全树未找到）。正确做法是 `AudioObjectGetPropertyData` 取 `CFString`。
2. 读 CFString 类属性前先查 `AudioObjectGetPropertyDataSize == sizeof(CFString)` 是稳妥做法。调查报告称直接读 `kAudioDevicePropertyDeviceManufacturer` 会让朴素探针崩溃（**本次未复现**）；但本项目现有代码读 `kAudioObjectPropertyName` 时并没有调用 `AudioObjectGetPropertyDataSize`，而是直接按 `sizeof(CFString)` 设好 size 再读，且工作正常（[AudioStore.swift:45-48](../Combo/Stores/AudioStore.swift#L45-L48)），所以触发条件很可能与具体属性/类型有关，**不宜当成普适结论**。
3. `kAudioDevicePropertyModelUID` 是 HAL UID，**不是型号名**。
4. `kAudioDevicePropertyDataSource`（`'ssrc'`）对蓝牙是**红鲱鱼**：它服务于内置/USB 设备的线路源选择，蓝牙设备通常没有该属性。
5. `'blea'`（LE Audio）与 `'blue'` 是不同的 transport。现有代码把两者合并判断，对“是不是蓝牙”无影响，但文档需记录该差异。
6. `system_profiler SPAudioDataType` 中的 `Transport` 并不总能把无线设备标成蓝牙：本机 `"轻舟已过万重山"的麦克风` 显示 `Transport: Unknown`。**不要只用 SPAudioDataType 的 Transport 做分类依据。**

## 7. 本机实测观测（✅ 只读）

- 默认输出：内置（`MacBook Air扬声器`），`Default Output Device: Yes`；取证时**无**蓝牙音频设备连接。
- 配对表中 Apple 设备带类型字段：`方林威的AirPods Pro` → `device_vendorID 0x004C` / `device_productID 0x2027` / `device_minorType Headphones` / `device_caseVersion 9A348`；`大风起兮云飞扬` → `0x2014` / `Headphones`。两个不同产品都是 `Headphones`，说明 **`device_minorType` 无法区分 AirPods 代际，只有 `device_productID` 能**。
- 配对表中非 Apple 设备只有 `device_address`（`客厅`、`方林威的iPad`、`轻舟已过万重山`）；`device_rssi` 时有时无（**运行时字段**，取决于设备当前是否在广播/可达，同一台 `客厅` 两次采集就不一致），**不能当类型信号**。
- `ioreg -r -c IOBluetoothDevice -l` 中实际 grep 到的条目 `ClassOfDevice = 0`，**未出现**任何带非零 CoD 的设备条目（本次未逐条确认每个条目的归属设备，因此不能断言非 Apple 设备一律为 0）。
- 本机实测到配对设备的字段值 `0x2027`；**`0x2027 → AirPods Pro 3` 这一型号对应来自社区资料**（[airpods-audio-feasibility.md:30](airpods-audio-feasibility.md#L30) 自己也注明"型号映射来自社区资料"），**未经验证**。

## 8. 未实测 / 待验证

1. 连接真实耳机时 `transportType` 是否为 `'blue'`（未观测；头文件值已确认）。
2. 连接真实耳机时**默认输出设备**的 `kAudioDevicePropertyDeviceUID` 取值（MAC 形态已在系统 plist 中实测，见 §1；连接态的实际读取未做）。
3. 真实耳机的 `classOfDevice` 取值（本机只测到 `ClassOfDevice = 0`）。
4. 连接态下 `system_profiler` 的 `device_connected` 桶字段形态（未观测，只有 `device_not_connected` 的字段清单）。
5. 私有 `CBProductInfo` 的选择子签名与产品表内容。
6. `device_productID` → 机型的映射表：本机只实测到两个**字段值**（`0x2027`、`0x2014`，且都取自 `device_not_connected` 桶），型号对应全部来自社区资料、**未验证**。
7. `github.com/keneci/AirPodsStatus` 返回 404，该项目名**未经证实**，本文不引用它作为依据。

**只读补测方式**（不改仓库、不改任何设置）：把耳机设为默认输出后依次采集 ① 默认输出设备的 transport / UID / 名称（CoreAudio 只读查询）；② `system_profiler SPBluetoothDataType -json`；③ `ioreg -r -c IOBluetoothDevice -l`。采集前后都不写入，测完恢复原输出。

## 9. 来源

- Apple：[IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice) · [蓝牙 entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.bluetooth) · [App Review 相关讨论](https://developer.apple.com/forums/thread/769362) · 本机 SDK 头文件 `AudioHardwareBase.h:614-615`
- [Bluetooth SIG Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/Assigned_Numbers.pdf)（类别常量）
- [Apple.SE：私有 SF Symbols 的存放位置](https://apple.stackexchange.com/questions/455485/where-does-macos-store-private-sf-symbols-such-as-icons-on-the-control-center) · 本机 `CoreGlyphs.bundle/…/name_availability.plist` 与 `symbol_order.plist`
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) · [nowplaying-cli](https://github.com/kirtan-shah/nowplaying-cli)
- [LibrePods](https://github.com/librepods-org/librepods)（AAP 协议）· [AirBattery](https://github.com/lihaoyun6/AirBattery)（BLE 广播解码）
- [SO：检测蓝牙音频设备](https://stackoverflow.com/questions/8185378/how-do-i-detect-if-a-bluetooth-audio-device-is-connected-in-mac-os-x) · [SO：输出设备类型](https://stackoverflow.com/questions/46075637/type-of-an-output-device-headphones-etc)
