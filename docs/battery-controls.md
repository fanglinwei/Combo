# 电池与高耗能应用：实现及验证边界

整理：2026-10-04；历史操作验证：2026-09-24。适用范围：当前 Combo 预览版；充电私有接口实测环境为 macOS 27.0（26A428）。

## 已批准的设计与执行结果

- [x] 低电量模式使用系统 `pmset`，点击时请求管理员授权；只修改点击时确定的电源类型，退出 Combo 后保留。
- [x] `Combo/App/State.swift` 解析电池与适配器配置，拒绝缺失、重复、未知模式；测试覆盖独立配置与支持高能耗的 `powermode`。
- [x] `PowerModeControl.swift` 异步读取、授权执行和回读验证。授权取消、读失败或不能确认结果时给出文字反馈，不乐观更新成功状态。
- [x] `Combo/Views/BatterySections.swift` 在真实状态主面板显示模式选择；演示场景不呈现写操作。`Combo/Stores/BatteryStore.swift` 在刷新电池时更新配置。
- [x] 主面板加入“立即充满电”：仅真实状态、接电、手动上限阻止充电、上限与电量均低于 100% 时可用，接口不可用则禁用并提供系统设置入口。
- [x] 私有调用在签名后的短时子进程 `ComboChargeHelper` 中执行；每次调用最多等待 8 秒，不需要提权或常驻服务。
- [x] 仅调用 `temporarilyDisableMCL:`，不改写永久上限，不操作优化充电开关，不在退出时恢复；恢复由 macOS 管理。

## 低电量切换

读取：`/usr/bin/pmset -g custom`。按电源类型使用 `-b` 或 `-c`，不使用会同时覆盖两者的 `-a`。模式值来自枚举，命令不拼接用户输入。

本机基线为电池 `lowpowermode 1`、适配器 `lowpowermode 0`。读取和相同值请求通过实机测试，相同值请求不弹授权。通过实际 `PowerModeControl` 完成适配器 0 → 1 → 0 两次写入及回读验证，电池模式仍为 1。授权路径直接完成操作，未验证全新授权环境下的取消分支；程序不保存凭据，也不修改授权规则。

界面检查：使用真实 `PanelView` 渲染，能耗模式显示“连接电源／自动”，菜单包含自动和低电量，说明文字显示授权与修改范围。主面板在恢复试验后仍正确显示 80% 充电上限。

## “立即充满电”探针结果

以下是早期独立探针的历史实测记录；探针已在正式 Helper 接入后清理。当前验证入口为 `./verify.sh`，其中 `Tests/ChargeControlCheck.swift` 使用模拟子进程检查控制流程，并只读检查打包 Helper 的 JSON。

早期探针的 `--temporary-charge` 和 `--temporary-mcl` 参数会更改临时充电行为，未纳入常规自动测试。探针在调用前检查方法是否存在及 ABI，并要求确认手动限制处于启用状态。

实测顺序：

1. 基线：80%，接电、未充电，`manualChargeLimit = 80`，`NotChargingReason = 16777216`。
2. `temporarilyEnableCharging:` 返回 true，无 NSError；优化充电状态从 1 变为 3，但手动 80% 限制继续生效。因此单独调用它不足以实现截图中的动作。
3. `temporarilyDisableMCL:` 返回 true，无 NSError；手动限制状态从 1 变为 3，`pmset -g battlimit` 变为无活动限制。稍后 `IsCharging = true`，`NotChargingReason = 0`。未请求管理员权限。
4. 系统电池设置显示正在充电，充电选项明确显示“充电上限将在06:00恢复至80%”。此时 getter `getMCLLimitWithError:` 返回有效临时值 100，不能把它误标为用户永久偏好。
5. 探针退出后上述临时状态仍由系统管理。结束试验后通过系统设置恢复原来的 80% 上限；复查 MCL 与优化充电状态均为 1，getter 返回 80。

## 正式面板接入

用户确认：沿用系统恢复规则、运行时能力检测与失败降级、首版仅覆盖手动上限。仅优化充电暂缓不在首版操作范围内。

后续独立补测：从 MCL=1、优化充电=1、手动上限80%的基线，只调用 `temporarilyDisableMCL:`。结果 MCL=3、优化充电仍为1、有效上限100%，实际开始充电。系统充电选项同时显示“充电上限将在06:00恢复至80%”和优化充电保持开启。测试后通过系统界面恢复80%。这证明本机无需先调用 `temporarilyEnableCharging:`；正式代码不使用前述两步组合。

真实 `PanelView` 点击流程分别在优化充电开启（状态1）和关闭（状态0）时通过：按钮先禁用并显示等待，随后显示“已确认开始充电”，上方电池状态显示正在充电。第二种场景也未修改优化充电状态。全部试验结束后恢复手动上限80%、优化充电开启；回读 MCL=1、优化充电=1、有效上限80。检测到限制重新启用时清除上次成功提示，避免将历史结果显示为当前状态。

`ChargeControl.swift` 接收子进程的结构化 JSON；进程缺失、异常、非零退出、响应无法解析或超过8秒均不会报告成功。点击时再次读取硬件状态，验证手动限制仍启用、有效上限与面板记录一致。操作进行中禁止重复点击，不自动重试写操作。

接口接受请求后先显示等待确认，再限时回读。只有同时读到 MCL=3、有效上限100%、接电且实际正在充电，才显示已确认开始充电。确认失败提示检查系统设置，且不承诺操作没有产生影响。没有读取到恢复时间时只说明由 macOS 管理，不显示固定时刻。

构建会运行 `Tests/ChargeControlCheck.swift` 的模拟子进程检查，覆盖成功回读、状态变化、请求失败、超时、重复点击、助手缺失，并只读检查真实打包助手的 JSON。常规构建测试不改变实际充电状态。`Tests/main.swift` 覆盖未知状态、演示、冲突上限等启用条件。

这里的状态 1、3 和 NotChargingReason bit24 是本机观察值，不是公开稳定契约。尚未验证其他机器、旧系统、拔插电源及实际到06:00自动恢复，因此保留能力检测与系统入口，不将本机结果宣传为全系统兼容。

参考：

- [Apple：充电优化与充电上限](https://support.apple.com/en-lb/102338)
- [Apple：能耗模式](https://support.apple.com/en-nz/101613)
- [Apple 开源 pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
- [Ampere 的 PowerUI 客户端调用](https://github.com/az-code-lab/ampere/blob/master/Sources/SMCWriter/main.swift)

## 高耗能应用

本节合并 2026-09-24 的独立能耗研究。当前名称是“高耗能应用”，不承诺瓦数排序或与系统菜单完全一致。

### 当前数据源与显示

[EnergyHelper.m](../Combo/Battery/EnergyHelper.m) 调用 ControlCenter 使用的私有 `systemstats_get_top_coalitions`。普通用户、无 sudo、无额外 entitlement 的历史探针读到有效字典；正式实现用签名短时 `ComboEnergyHelper`，仅允许 arm64 与 build `26A428`，发现 ControlCenter 自定义阈值时拒绝，避免错误套用默认参数。

主程序超时 8 秒，helper 15 秒兜底，JSON 上限 8 KiB；真实面板活动时每 30 秒查询，关闭/息屏/退出取消，演示不展示真实名单。符号缺失、响应结构变化、超时或任何无法确认归属的记录令整次查询不可用，不能伪装为空列表。

按非空 responsible bundle ID 优先归属到运行应用，用 `NSRunningApplication` 名称与图标，保留源顺序、按 ID 去重后应用最多 1/2/3 个的限制（默认 1）。不为凑数补应用，不用 CPU 阈值重排。加载、正常空名单、有效列表、不可获取是四种状态。后台进程、扩展及未知记录尚未完整复刻系统筛选。

### 历史 ABI 与来源证据

2026-09-24 的 ControlCenter 二进制 SHA-256 为 `01a86af5e3c328c3c3af7b7007ed240e4c336777011b354b0dc23d659a3a9c45`；导入 `_systemstats_get_top_coalitions`，arm64e 调用点 `0x1004e1ecc`。本机核查消费 `x0 = 120`、`x1 = 5`、`d0 = 60000.0`，采用 `NSDictionary *(*)(uint64_t, uint64_t, double)` ABI。常量 `500.0` 来自 `0x1006e5f20`；`BatteryPowerScoreInterval` / `BatteryPowerScoreMax` 可改变默认参数，历史读取未发现自定义值。

这是该构建的实测，不是公开头文件；第二参数 5 的精确语义未确认，不能当用户显示上限。返回 `bundle_identifiers`、`responsible_bundle_identifiers`、`display_names`、`energy_impacts` 平行数组及 `report_duration`。原始名称/归属可以为空，评分不是瓦数或电池百分比，统计窗口 120 也不是必须刷新周期。

ControlCenter 后处理涉及扩展关联、可显示性、名称/图标、去重；原始数组不等于最终菜单。产品未采用诊断时把第三参数设零的采样，也不改系统偏好。

### 历史验证与剩余验收

用户展开系统电池菜单后，辅助功能树显示空名单；相邻只读采样四数组为空且 duration=120，空状态对照通过。这不是原子快照，不证明非空顺序一致。历史采样曾返回 Codex 和 WindowServer，因后者缺少可验证归属规则显示不可获取；后续只返回 Codex 时，真实面板显示 ChatGPT 名称与图标。

`Tests/EnergyAppsCheck.swift` 覆盖空值、结构、顺序、归属、去重、上限、helper 失败/缺失/超时及旧结果取消。历史设置验证了默认 1、切换 3 和偏好持久化；失败文案未误报为空。

仍需对照单应用、多应用顺序、扩展/辅助进程筛选、应用退出及负载下降后的移除，以及其他系统/机器/沙盒。本次文档整理不表示重新执行实机检查。

历史参考：[libsystemstats 导出符号](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX11.3.sdk/usr/lib/libsystemstats.tbd)、[Mozilla 旧系统菜单研究](https://firefox-source-docs.mozilla.org/performance/activity_monitor_and_top.html#battery-status-menu)。[BatteryBar](https://github.com/isolson/BatteryBar/blob/main/BatteryBar/Utility/EnergyHogs.swift) 是 CPU 阈值方案，未采用为同源名单。
