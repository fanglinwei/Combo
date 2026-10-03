# 中央图标支持 AirPlay / HomePod：实现与验证边界

更新：2026-10-03。开发与历史取证环境为 macOS 27.0（Build 26A428）、Apple Silicon、自用 ad-hoc 原型。本文以当前实现为准；历史 API 采集见 [配套证据](airplay-homepod-api-evidence.md)。

## 1. 当前范围

| 能力 | 当前行为 | 验证边界 |
| --- | --- | --- |
| 当前输出识别 | CoreAudio 默认输出的 transport 为 `'airp'` 才进入 AirPlay 分类 | 历史 Apple TV 路由采集确认过；本轮异步实现仍需实机回归 |
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

`Tests/AirPlayRouteCheck.swift` 与 `Tests/AirPlayDiscoveryCheck.swift` 已接入 `./verify.sh`，覆盖异步取消、过期结果、路由切换、超时、权限拒绝与普通网络故障区分；`Tests/PanelMotionCheck.swift` 与 `Tests/PanelDismissCheck.swift` 覆盖不依赖 key 的外部点击、详情/图标内部点击、长时间授权保护、授权结束、应用/Space 切换、主动收起及动画。分类、符号回退与中央/列表一致性由现有输出设备及图标检查覆盖。新增检查的执行结果以本轮实际命令输出为准，历史 Apple TV 采集不代表本轮功能已经实机通过。

待实机回归：首次本地网络弹窗与拒绝/重试、面板关闭/演示/睡眠及唤醒、快速切换与设备 ID 复用、HomePod 全尺寸/mini、多设备、AirPlay 1、蓝牙与 AirPlay 并存及 macOS 26。保留系统声音设置；不捆绑 pyatv/owntone 等运行时，不实现 HomePod 接收端播放控制或音频投送。

2026-10-03 本轮验证：Debug 构建、路由进程检查、发现状态检查、helper 单接收端/多接收端回退检查、蓝牙回复验证、模拟本地网络失焦保护及其余状态/图标/本地化/helper/签名检查通过。后续面板关闭修复已移除对 key 的依赖；完整 `verify.sh` 现已通过，包含 AppKit 本地点击监听与 Space 通知检查。真实系统授权弹窗未在本轮触发，系统代理窗口识别仍需实机复核。

相关：[蓝牙设备分类](bluetooth-audio-device-icon-research.md) · [设置规格](combo-settings.md#31-中央状态优先级2026-09-24) · [后续规划](combo-roadmap.md)。
