# 系统高耗能应用名单：本机可行性验证

验证日期：2026-09-24。目标：macOS 27.0，build 26A428。

## 结论与完成边界

已找到并成功调用 ControlCenter 使用的私有数据源 `systemstats_get_top_coalitions`。
普通用户、无 sudo、无额外 entitlement 的独立 Objective-C 探针能得到有效字典，
实际观察到了空名单和非空名单。此前仅凭 GitHub 检索未能确定的数据源，现已由本机二进制与执行结果补证。

**尚不能声称最终显示与系统菜单完全一致。** ControlCenter 在调用后还做应用归属、
扩展关联、名称/图标、可显示性、去重等处理；最终筛选和顺序仍需完整核对。
首次通过计算机 UI 工具读取 ControlCenter 两次均报 `timeoutReached`，SystemUIServer 同样超时。
用户手动展开系统电池菜单后，成功读取其辅助功能树，并完成同一时段的空状态对照。
非空名单、多个应用的顺序和应用退出后的移除行为仍未完成对照。
已按用户“接入正式功能”的指示接入 Combo。当前支持普通前台应用的归属；遇到无法确认归属的扩展、后台进程或未知记录时，整个结果显示不可获取，避免伪造空名单或截断后的名单。

## 已确认的产品约定

- 名称“高耗能应用”，不承诺瓦数排序或“耗电最高”。
- 优先与系统电池菜单名单一致，接受验证后的私有接口与版本兼容维护。
- 保留经验证的系统显示顺序，不以 CPU 或另一套指标重排。
- 默认最多 1 个，设置面板可选 1 / 2 / 3；立即应用并持久化。
- 实际可为 0 个，不为凑数补充应用。
- 正常空名单：“没有使用大量能耗的 App”。
- 加载中：“正在获取能耗信息…”。
- 获取失败或不支持：“暂时无法获取能耗信息”。不得把错误归为空名单。

## 本机证据

对象：`/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter`。

SHA-256：`01a86af5e3c328c3c3af7b7007ed240e4c336777011b354b0dc23d659a3a9c45`。

1. `nm -um` 显示 `_systemstats_get_top_coalitions (from libsystemstats)`。
2. arm64e 调用点 `0x1004e1ecc` 进入该函数。
3. 调用前默认寄存器值：`x0 = 120`，`x1 = 5`，`d0 = 120 * 500 = 60000`。
   `0x1006e5f20` 的 double 常量经 Mach-O 段映射读取为 `500.0`。
   `BatteryPowerScoreInterval` 与 `BatteryPowerScoreMax` 可覆盖对应默认值。
   本机读取这两个 defaults key 均不存在，未写入或修改它们。
4. 在自有探针进程中使用 LLDB 反汇编加载后的 libsystemstats，确认函数消费
   `x0`、`x1` 和 `d0`，返回 Objective-C 对象，经同步调用取得数据。
   探针采用 `NSDictionary *(*)(uint64_t, uint64_t, double)` 的 ABI。
   这是该构建的实测 ABI，不是 Apple 公布的头文件；第二参数 5 的精确语义仍未确认。
5. ControlCenter 随后读取 `bundle_identifiers`、`responsible_bundle_identifiers`、
   `display_names`，检查对应数组长度。后续调用点还涉及 `LSApplicationExtensionRecord`、
   `NSWorkspace`、`NSFileManager`、显示标记与集合去重。

不能把原始返回数组直接等同于最终可见菜单，也不能把内核/服务参数中的 5 当成用户设置的显示上限。
用户的 1～3 必须在最终应用归属、筛选和去重后执行。

## 实测返回

### 系统菜单空状态对照（用户展开菜单后）

通过计算机 UI 工具读取 `com.apple.controlcenter`，获得“控制中心”系统对话框，
其中电池区域明确显示“没有使用大量能耗的App”。随后立即执行仓库中的只读探针，
退出码为 0，`bundle_identifiers`、`responsible_bundle_identifiers`、`display_names`、
`energy_impacts` 四个数组均为空，`report_duration` 为 120。

结论：此时段的**空状态对照通过**。这是相邻读取，不是原子快照；
不能据此推广为非空名单、顺序、进程归属和全部系统版本都已验证。

### 此前数据源采样

标准参数 `(120, 5, 60000.0)` 初次返回所有数组为空，`report_duration = 120`。
后续同参数查询返回 `bundle_identifiers = ["com.openai.codex"]`，能耗评分约 84846。
两次采样并非同一时间，不以这个变化推断精确的入榜延迟。

仅在临时诊断探针中把第三参数设为 0，返回 Codex、WindowServer、VS Code 及其评分，
用于确认数据可用和服务侧的筛选差异。没有改动系统偏好，也没有将诊断参数用于产品方案。
原始 `display_names` 和 `responsible_bundle_identifiers` 可以是空字符串，
不能直接作为 UI 标题，也不能因此把正常记录认定为失败。

返回字段：

```text
bundle_identifiers              NSArray
responsible_bundle_identifiers  NSArray
display_names                   NSArray
energy_impacts                  NSArray
report_duration                 NSNumber
```

这些 energy impact 值不是瓦数，也不是电池消耗百分比。120 是请求统计窗口，
不代表应用必须每 120 秒刷新一次；刷新周期尚未验证。

## 可复现探针

在仓库根目录执行：

```sh
clang -fobjc-arc -framework Foundation prototypes/system-energy-query.m -o /tmp/combo-system-energy-query
/tmp/combo-system-energy-query
```

探针只读、输出 JSON；含符号、响应结构、平行数组长度和窗口检查，15 秒进程级超时。
为避免把推导的 ABI 当成跨版本契约，主动拒绝未经验证的系统构建。
退出 0 仅表示数据源与响应结构检查通过，不表示系统菜单一致性已通过。
未在沙盒应用或其他 macOS 构建上验证。

## 选型与剩余验收

选择：同源 `libsystemstats` 查询 + 复现已核实的 ControlCenter 展示后处理 + 显示上限。
不引入 mxmon、osquery、CPU 阈值，也不以 top/powermetrics 冒充同源名单。

正式实现使用签名短时辅助进程 `ComboEnergyHelper`，以进程超时、符号缺失、结构变化作为明确不可用状态。
目前仅允许 arm64、build 26A428；ControlCenter 自定义阈值存在时也会拒绝，避免沿用默认参数产生不同名单。
主程序 8 秒超时，助手 15 秒兜底，JSON 上限 8 KiB。面板显示期间每 30 秒查询，关闭面板、息屏及退出时取消；演示模式不展示真实能耗名单。
普通运行中的应用按 responsible ID（非空）优先归属，使用 NSRunningApplication 名称/图标，保留源顺序、按 ID 去重后取前 N 个。
该处理仍不是完整复刻 ControlCenter 的全部后处理。任何无法解析的记录都会让整次查询不可用，包含 WindowServer 等后台进程。

仍需验收：

1. 空状态已完成一次同一时段对照；仍需对照单应用、多应用及顺序。
2. 核对扩展/辅助进程的归属、可显示性筛选和去重，避免仅做路径启发式。
3. 验证应用退出、负载下降后的移除行为；考虑服务采样和菜单刷新时间差。
4. 列表、1～3 设置及错误状态已接入；`Tests/EnergyAppsCheck.swift` 覆盖空值、结构校验、顺序、归属、去重、上限、子进程失败/缺失/超时及取消后的旧结果隔离。
5. 本次打包助手曾返回 Codex 和 WindowServer；因后者未实现可验证的系统筛选规则，按约定显示不可获取。后续采样仅返回 Codex，独立验证窗口中的真实 `PanelView` 正确显示 ChatGPT 名称和图标。
6. 使用真实 `SettingsView` 验证默认 1、切换 3 及 UserDefaults 持久化；界面可访问性树和截图均通过。验证采用独立 bundle ID，未改动用户的正式偏好。随后真实面板也观察到获取失败文案，未误显示空名单。

## 外部参考

- [Apple SDK 镜像的 libsystemstats.tbd](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX11.3.sdk/usr/lib/libsystemstats.tbd)：历史导出符号佐证，无签名或兼容保证。
- [Mozilla 的 Battery status menu 研究](https://firefox-source-docs.mozilla.org/performance/activity_monitor_and_top.html#battery-status-menu)：旧版 OS X 的时间窗口观察，不可直接用作当前阈值。
- [BatteryBar 的 EnergyHogs.swift](https://github.com/isolson/BatteryBar/blob/main/BatteryBar/Utility/EnergyHogs.swift)：实为 CPU 阈值方案，已排除。
