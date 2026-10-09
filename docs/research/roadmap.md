# Combo 后续版本规划

整理：2026-10-09。本文保留尚未完成的功能方向与实机验证条件，不指定发布日期或产品版本号。

## 当前基线与延后方向

当前 MacBook 功能与验证边界见 [产品行为](../product/behavior.md)、[设置规格](../product/behavior.md#settings) 和 [README](../../README.md)。AirPods 左右耳电量、聆听模式与对话感知已接入声音面板，见 [声音与 AirPods](../engineering/audio.md#airpods)；外圈仍为 Mac 本机电量。

| 延后方向 | 状态与进入条件 |
| --- | --- |
| 台式 Mac 与无内置电池形态 | 保留外圈的方向尚待交互定稿，不因一次读取失败切换电量来源 |
| 关联设备作为外圈电量来源 | 当前没有来源选择入口；需确定绑定、空态、身份和过期数据规则 |
| iPhone 电量 | USB／网络／蓝牙路径仍为研究，需要信任配对、可达性和失效场景验证 |
| 耳机电量覆盖与外圈来源 | 面板已有 AirPods 电量；更多型号、充电盒可靠性与外圈来源仍需验证 |

## 台式机后续设计方向

- 保留外圈，继续让它表示电量，避免改为音量后在两类 Mac 之间改变含义。
- 无本机电池时，可使用用户选定的手机或耳机电量作为来源；实际可用设备以技术验证结果为准。
- 底部沿用音量圆点和固定播放动效，无需为台式机发明另一套播放动画。
- 中央设备图标与外圈来源必须避免错配；当中央仍需显示 Wi-Fi 或网络异常时，怎样持续说明电量属于谁，需在后续设计中确定。
- 必须区分“没有内置电池”和“本机电量暂时不可读取”，不能因一次读取失败自动切换为台式机形态。

### 后续仍需决定的规则

1. 没有任何可读关联设备时，外圈的空态如何呈现。
2. 固定绑定与自动选择是否都提供；不得把此前建议的固定绑定当作已最终确认。
3. 左右耳电量合成、单耳使用、充电盒单独显示的具体规则。
4. 数据过期、设备断开、重新连接时外圈与提示如何变化；不能让旧值冒充实时值。
5. 外圈来源图标、音频输出设备图标、Wi-Fi 提示之间的优先级。
6. 是否允许 MacBook 用户在未来手动选择外部电量来源；当前没有承诺此扩展，首版始终使用本机电量。

## 当前功能的待验收项

AirPods 电量、蓝牙分类、AirPlay 已路由探测与附近发现已接入，不作为未来待实现功能。后续硬件、权限、生命周期及 macOS 26 回归见 [音频工程说明](../engineering/audio.md)。更多型号与耳机外圈来源应先验证身份、电量缺失、左右耳/盒子、断连和过期数据规则。

## 建议推进顺序

1. 完成当前 MacBook 功能的实机回归，外圈继续使用本机电量。
2. 扩展关联电量来源前，验证已有耳机读取边界和手机配对／查询能力。
3. 根据真实数据能力定稿台式机外圈来源、空态及来源选择设置，再安排后续版本开发。
4. 对已实现的蓝牙/AirPlay 共享分类与生命周期做实机回归：身份匹配、快速切换、权限拒绝/重试、面板失焦、睡眠唤醒与 macOS 26；自动化检查不能替代硬件验收。
5. 非 Apple 蓝牙设备精确型号、HomePod 控制与全系统路由建立保持延后；附近发现已实现，下一步先验证权限与实际设备覆盖，再决定是否加入 `_raop._tcp`。

此顺序是规划建议，不表示已授权实现、安装依赖、配对设备或改变系统设置。

<a id="iphone"></a>

## iPhone 电量研究

历史调研：2026-09-22，未安装依赖或配对实测；关联电量来源尚未交付。

### 结论

**可行，已有第三方实现；优先验证“首次 USB 信任／配对，之后在局域网查询”的方案。** 不需要把“安装 iPhone 配套 App”作为唯一前提，也不能把“同一 Apple 账户”当成足以读取电量的条件。

### 方案比较

| 路径 | 手机端 App | 条件与证据 | 对 Combo 的判断 |
| --- | --- | --- | --- |
| USB + libimobiledevice | 不要求 | 设备连线，完成信任和配对；源码有实际电量查询 | 最小实测起点 |
| 网络 + libimobiledevice | 不要求 | 信任／配对、无线连接启用、设备能被发现且可达；AirBattery 要求初次连线配对及同局域网 | 优先评估的日常体验 |
| 蓝牙发现 + GATT 读取 | 不要求 | AirBattery 有特定 iPhone／蜂窝 iPad 路径；需蓝牙权限和适配验证 | 补充路径，不作为普遍保证 |
| iPhone App 读取后同步 | 需要 | 手机使用公开 UIDevice 电量 API；同步与后台更新需自行设计 | 官方手机端 API 清晰，但后台时效不可保证 |

前两条是第三方库访问设备协议，不是 Apple 提供的通用跨设备电池 SDK；开源工具能运行不代表任意沙盒或商店发布形态都可直接照搬。[libimobiledevice](https://libimobiledevice.org/)、[ideviceinfo 上游源码](https://github.com/libimobiledevice/libimobiledevice/blob/master/tools/ideviceinfo.c)。

### USB／网络路径的调用方式

以下是供后续验证的命令示例，本次没有执行。`DEVICE_UDID` 必须替换为用户选定、已配对设备的标识。

```sh
# USB 设备的电量与充电状态
ideviceinfo -u DEVICE_UDID -q com.apple.mobile.battery

# 已配对且可以通过网络发现的设备
ideviceinfo -n -u DEVICE_UDID -q com.apple.mobile.battery
```

上游 `ideviceinfo.c` 明确支持 `-n` 网络模式、`-u` 指定设备、`-q` 指定查询域，并通过 lockdownd 会话取得值。AirBattery 使用该查询读取当前电量和充电布尔值；这不是电池健康度或最大容量百分比。[上游源码](https://github.com/libimobiledevice/libimobiledevice/blob/master/tools/ideviceinfo.c)、[AirBattery 调用](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/IDeviceBattery.swift#L47-L86)。

AirBattery 在 USB 路径另外执行自带的 `wificonnection` 工具启用无线连接。因此不能把该项目的“插过一次线后可无线查询”误解成所有用户只点一次信任后便自动具备无线查询条件。Combo 若采用此路径，应明确引导并验证无线连接启用状态，不能悄悄修改设置。[同一调用文件](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/IDeviceBattery.swift#L70-L85)。

### 蓝牙路径：不能仅描述为被动读取广播中的电量

AirBattery 的 BLE 实现以特定 Apple 广播类型发现设备，随后调用 `centralManager.connect`、发现服务并读取 `180F` 服务下的 `2A19` 特征。也就是说，观察到广播只是发现步骤，后续还有连接与读取，不宜承诺“扫描一下就能拿到所有 iPhone 的准确电量”。项目 README 限定该功能用于 iPhone／蜂窝版 iPad，并要求开启蓝牙。[BLE 源码](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift#L147-L237)、[项目 README](https://github.com/lihaoyun6/AirBattery)。

该分支的充电状态推断代码被注释，不能据此声称蓝牙路径与 USB／网络路径具有同等充电状态能力。设备识别、允许连接的条件、锁屏与后台广播行为均需实测；不能从项目存在推出无需任何前提即可读取附近所有手机。

### 配套 iPhone App 路径

手机 App 可开启 `UIDevice.current.isBatteryMonitoringEnabled` 后读取 `batteryLevel`。官方规定其范围为 0 到 1；未开启监测时可能返回 -1，不能显示成真实电量。该 API 读取运行 App 的本机电量，不是让 Mac 直接读取远端 iPhone 的 API。[batteryLevel](https://developer.apple.com/documentation/uikit/uidevice/batterylevel)、[isBatteryMonitoringEnabled](https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled)。

手机再把数据同步给 Mac 是可设计的方案，但普通后台刷新由系统决定启动时机，不支持据此承诺每分钟固定更新或锁屏后持续实时上报。此方案增加手机端应用与同步维护，不是 Combo 首次验证的最短路径。[Apple 后台执行策略](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)。

### 对产品的建议

1. 将 iPhone 列为“需要设置的关联电量来源”，而不是登录同一账户后自动可用的承诺。
2. 设置流程：选择手机 → USB 信任／配对 → 首次电量查询成功 → 引导确认无线连接 → 拔线验证 → 才允许作为无线电量来源。
3. 网络不通、锁屏后会话失败、手机重启或信任失效时，显示“未连接／数据不可用”，保留淡色外圈。手机重启后的首次解锁等场景必须单独验收，当前未证明可连续查询。
4. 正常时显示电量、充电状态和明确的设备名称；过期时展示上次成功读取的时间，不把缓存当成实时状态。
5. Mac 可以通过以太网连接局域网，iPhone 使用 Wi-Fi；产品需要的是可发现且互通的网络路径，不应只检查 Mac 是否开了 Wi-Fi。具体混合网络环境仍需验证，尤其访客网络和客户端隔离。
6. 先做一个 USB + 网络查询探针验证目标设备，不同时搭建云同步、iPhone App 和多条蓝牙回退路径。

### 实测与边界

必须覆盖：USB 已信任／未信任；无线启用／未启用；同网可达／网络隔离；锁屏、长时间闲置、低电量模式、手机重启后首次解锁前后；Mac 睡眠唤醒；充电、未充电、满电；两台手机和设备改名；最终签名与沙盒环境。

### 查询证据与信任条件

[ideviceinfo 固定源码](https://github.com/libimobiledevice/libimobiledevice/blob/bcced6c4f6a79e09ed3961632b2faf81fe873137/tools/ideviceinfo.c) 将 `com.apple.mobile.battery` 列为已知查询域：`-u` 指定 UDID，`-n` 选择网络设备，`-q` 指定域，`-k` 指定字段，通过带握手 lockdownd 会话读取。命令退出成功或空输出不能等于有效电量；必须校验返回字段、类型、范围和缺失。

[Apple 信任电脑说明](https://support.apple.com/en-us/109054)要求首次连线、解锁并在手机与 Mac 上确认；信任授权范围大于电量读取，应如实解释。[Finder Wi-Fi 说明](https://support.apple.com/en-us/102471)的无线设置需先 USB 连接，在通用页勾选“连接 Wi-Fi 时显示此设备”并应用。接通电源是自动同步条件，不能误写成所有网络查询必须充电；Finder 可发现也不证明第三方查询必定成功。

未证实持续锁屏、重启首次解锁前、睡眠、跨网段、信任撤销和系统升级后的查询可靠性；不承诺同一 Apple 账户自动持续读取。以太网 Mac 与 Wi-Fi 手机混合网络需另行验收。本次整理仅合并既有资料，未安装依赖、查询设备或重新在线核查。

<a id="menu-bar"></a>

## 自动折叠研究（暂停）

当前采用系统设置手动隐藏、基线记录和确认恢复，见 [产品规格](../product/behavior.md#settings)。以下历史实验来自 2026-09-23、macOS 27.0 build `26A428`，不代表已授权重新试验。

### 历史折叠实验与方案比较

2026-09-23，macOS 27.0 build `26A428` 上先前 ControlCenter/SystemUIServer 的 AX 根属性返回 `kAXErrorNoValue`，不能据此断言权限无效或所有入口不可用。后续 MenuBarAgent AX 树暴露 Wi-Fi、声音、电池独立标识；CGS 枚举只取得整块菜单栏窗口，未建立逐项窗口身份。

| 方案 | 机制 | 历史结果 / 产品限制 |
| --- | --- | --- |
| 系统设置手动隐藏 | 用户独立切换三个复选框 | 本机每次仅移除目标，Combo 与其他项保留；设置持久化，退出不自动恢复 |
| AppKit spacer / overflow | Combo 左侧加宽空白状态项，将连续左侧图标挤入系统 overflow | 按位置成组，不满足任意三个独立开关；拥挤/刘海/多屏可能连自身入口受影响，未通过本机完整验收 |
| MenuBarClientCore 私有 assertion | 系统项 ID + 应用 bundle 白名单；释放解除限制 | 本机单项排除同时令 Combo 从 AX 树消失，暂停；原生菜单点击也未确认成功 |
| Thaw 公开机制 | 大分隔项 + 窗口/AX 关联 + Command 合成拖拽 + 临时放出点击/拖回 | macOS 27 发行版来自另一私有仓库，公开分支不证明 27 上同机制可用；布局可能持久化，不保证崩溃后立即恢复 |

#### 私有 assertion 的已知失败

旧逐项 8 秒实验观察目标约第 3 秒消失，释放后恢复；后续隔离 15 秒实验只排除 Wi-Fi ID 6 时，Wi-Fi 与 Combo 同时从 AX 树消失，其他目标及部分第三方图标保留。Combo 的 bundle ID 已在白名单，临时增加稳定 autosaveName 后同样失败。AX 树不是像素证明，但已不足以通过“恢复入口始终可见可点”的验收；`NSStatusItem.isVisible == true` 也不能代替视觉与点击检查。

历史 macOS 27.0 私有系统 ID：电池 0、声音 5、Wi-Fi 6、时钟 2、控制中心 8。它们不是 Apple 稳定协议。白名单按 bundle 管理第三方项目，不能保证精确控制同一应用的一枚图标。系统菜单打开可能需先释放限制、等待、再重放点击；本机 AXPress 与坐标点击未观察到原生菜单，不能只看动作返回码。

AppKit 只管理本应用 NSStatusItem，`removeStatusItem` 不可用于删除其他应用的系统图标。系统自身能独立隐藏不证明 Combo 获得了公开自动控制接口；自动点击设置是 UI 自动化，受语言/布局影响且留下持久设置，不能满足“退出/崩溃自动恢复”的旧折叠目标。

#### Thaw 的可复核机制

公开研究固定到 [Thaw 提交 46a306a9](https://github.com/thaw-app/Thaw/tree/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4)：ControlItem 用约 10,000 pt 分隔项推走左侧项目；私有 `CGSGetProcessMenuBarWindowList` 取得窗口，XPC 将窗口几何与各应用 AX extras 关联；实时身份核查后合成 Command 拖动。临时展开记录原分区/位置，放出并点击，菜单结束再拖回，失败保留恢复记录。

[源码选择 action](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/.github/actions/checkout-source/action.yml#L1-L6)将 `thaw-next` 明确列为私有 macOS 27 仓库，不能用公开 README 的系统支持范围推导未运行的发行版内部机制。公开源码的辅助功能用于发现/移动/点击，录屏用于预览等功能；不能无证据为 Combo 额外要求录屏。项目为 GPL-3.0，研究机制不等于可直接移植到任意分发形态。

### 后续进入条件

重启折叠工作前，先完成当前进程只读定位，确认目标唯一且自身入口可观测；AXExtrasMenuBar、MenuBarAgent 容器与 overflow 几何是不同入口，不能仅按标题或固定坐标动作。

任何隔离试验必须同时证明：Combo 全程可见可点击、目标逐项独立、失败/退出后能恢复、原生菜单能打开。普通、拥挤、刘海、多显示器布局均需验证；一次短时成功不等于跨版本交付。不能靠写未公开 plist、关闭 SIP、重置全局 TCC 或重启系统代理作为常规恢复。

spacer 若只能连续折叠，需另行确定产品语义；私有路径需核实 ID、权限、assertion 释放与菜单重放。当前没有满足全部条件的方案，预选、授权和只读诊断都不自动恢复折叠。

### 历史来源

以下保留原核查来源，本次整理未重新在线验证上游 PR 状态：

- Apple：[macOS 26 菜单栏设置](https://support.apple.com/guide/mac-help/mchlad96d366/26/mac/26)、[macOS 27 手动整理](https://support.apple.com/guide/mac-help/customize-the-menu-bar-mchl4af84660/27/mac/27)、[NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)、[NSStatusItem.isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)。
- [Ice macOS 27 spacer 源码](https://github.com/WuColin-1/Ice/blob/macos-27/Ice/MenuBar/MacOS27NativeMenuBarHiding.swift)、[说明](https://github.com/WuColin-1/Ice/blob/macos-27/MACOS27.md)、[PR #997](https://github.com/jordanbaird/Ice/pull/997)、[原生点击 PR #995](https://github.com/jordanbaird/Ice/pull/995)：上游机制/观察，非 Combo 本机验收。
- [MenuBarHider bridge](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/Services/MenuBarAgentBridge.swift)、[系统 ID 表](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/Services/SystemItems.swift)、[Hidden Bar shim](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m)：私有运行时白名单与释放机制。
- [Thaw 分隔项](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/Thaw/MenuBar/ControlItem/ControlItem.swift)、[身份关联](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/MenuBarItemService/SourcePIDCache.swift)、[临时展开](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/Thaw/MenuBar/MenuBarItems/MenuBarItemManager/MenuBarItemManager%2BTemporaryShow.swift)、[许可](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/LICENSE)。
