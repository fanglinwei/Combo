# 电池操作：实现与本机验证

日期：2026-09-24。适用范围：当前 Combo 预览版；充电私有接口实测环境为 macOS 27.0（26A428）。

## 已批准的设计与执行结果

- [x] 低电量模式使用系统 `pmset`，点击时请求管理员授权；只修改点击时确定的电源类型，退出 Combo 后保留。
- [x] `State.swift` 解析电池与适配器配置，拒绝缺失、重复、未知模式；测试覆盖独立配置与支持高能耗的 `powermode`。
- [x] `PowerModeControl.swift` 异步读取、授权执行和回读验证。授权取消、读失败或不能确认结果时给出文字反馈，不乐观更新成功状态。
- [x] `Views.swift` 在真实状态主面板显示模式选择；演示场景不呈现写操作。`Store.swift` 在刷新电池时更新配置。
- [x] 主面板加入“立即充满电”：仅真实状态、接电、手动上限阻止充电、上限与电量均低于 100% 时可用，接口不可用则禁用并提供系统设置入口。
- [x] 私有调用在签名后的短时子进程 `ComboChargeHelper` 中执行；每次调用最多等待 8 秒，不需要提权或常驻服务。
- [x] 仅调用 `temporarilyDisableMCL:`，不改写永久上限，不操作优化充电开关，不在退出时恢复；恢复由 macOS 管理。

## 低电量切换

读取：`/usr/bin/pmset -g custom`。按电源类型使用 `-b` 或 `-c`，不使用会同时覆盖两者的 `-a`。模式值来自枚举，命令不拼接用户输入。

本机基线为电池 `lowpowermode 1`、适配器 `lowpowermode 0`。读取和相同值请求通过实机测试，相同值请求不弹授权。通过实际 `PowerModeControl` 完成适配器 0 → 1 → 0 两次写入及回读验证，电池模式仍为 1。授权路径直接完成操作，未验证全新授权环境下的取消分支；程序不保存凭据，也不修改授权规则。

界面检查：使用真实 `PanelView` 渲染，能耗模式显示“连接电源／自动”，菜单包含自动和低电量，说明文字显示授权与修改范围。主面板在恢复试验后仍正确显示 80% 充电上限。

## “立即充满电”探针结果

构建和默认只读运行：

```sh
xcrun clang -fobjc-arc -framework Foundation Tests/ChargeFullProbe.m -o build/charge-full-probe
./build/charge-full-probe
```

显式传入 `--temporary-charge` 或 `--temporary-mcl` 会更改临时充电行为，不能作为常规自动测试运行。探针在调用前检查方法是否存在及 ABI，并要求确认手动限制处于启用状态。

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
