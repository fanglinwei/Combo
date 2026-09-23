# macOS 27 菜单栏折叠：实现路径调查（2026-09-23）

> 2026-09-23 调整：本文的 Ice／MenuBarClientCore 路径作为备用方案。当前优先评估 [Thaw 的实现](thaw-menu-folding-research.md)，再决定 Combo 的最小实现。

## 结论

macOS 27 的状态项由 `MenuBarAgent` 合成绘制，旧的“每项一个 WindowServer 窗口”枚举和把分隔项放大到 10,000 pt 的隐藏法失效。因此，Combo 已获辅助功能权限，但只查询 `ControlCenter` / `SystemUIServer` 的 `AXMenuBar` 得到 `-25212`，**不能推断系统图标不可操作**；应该试 `MenuBarAgent` 和各项目所属应用的 `AXExtrasMenuBar`。Apple 公开的 `NSStatusItem.isVisible` 只控制本应用创建的状态项，并非隐藏别人的图标的 API。来源：[Apple NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)、[Apple AXExtrasMenuBar](https://developer.apple.com/documentation/applicationservices/kaxextrasmenubarattribute)、[Ice macOS 27 说明](https://github.com/WuColin-1/Ice/blob/macos-27/MACOS27.md)。

## 两条已存在的实现路径

| 路径 | 如何折叠／展开 | 优点 | Combo 的关键限制 |
| --- | --- | --- | --- |
| **A. 公开 AppKit + 系统 overflow** | 在 Combo 图标左边创建有 `autosaveName` 的窄空白 `NSStatusItem`。收起时把它扩至图标左侧的可用空间，使左边项目进入 macOS 自带的 `«` overflow；展开时撤掉 spacer。只需给 Combo 自己的项目定位；用户把要折叠的系统项手动 ⌘-拖到 Combo 左侧。 | 不使用私有 API；普通折叠不需要录屏；被折叠项目可通过系统 overflow 访问。 | 根据相对位置成组折叠，**不能只凭 Wi‑Fi／声音／电池三枚设置开关精确选中**；macOS 27 `MenuBarAgent` 托管的系统项由布局编辑器模拟拖动曾导致 agent 崩溃，不能安全承诺自动搬动。依赖屏幕宽度、刘海、系统 overflow 布局。 |
| **B. 私有 MenuBarClientCore 限制** | 动态加载 `MenuBarClientCore.framework` 的 `MBAssessmentModeConfiguration(initWithAllowedSystemItems:allowedBundleIdentifiers:)` 和 `MBAssessmentModeAssertion(activateWithConfiguration:completionHandler:)`。从系统项目白名单中排除目标 ID 即隐藏；`invalidate` 或进程退出后解除。 | 可按系统项目选择，理论上正好适配三个独立开关；不需要截图或挤占宽度。 | **未公开、不受兼容性保证**；在 assertion 生效时，`MenuBarAgent` 对时钟／电池／Wi‑Fi 的点击及 AXPress 可能无反应，打开原生面板前必须暂时解除限制，等待生效后点击，再恢复；需要真实机器验证。相关开源实现目前都默认保留全部系统项，故“隐藏 Wi‑Fi／声音／电池”尚无已证实的现成实现。 |

A 的具体实现与限制见 [Ice #997（开放 PR，尚未合并）](https://github.com/jordanbaird/Ice/pull/997)、[spacer 源码](https://github.com/WuColin-1/Ice/blob/macos-27/Ice/MenuBar/MacOS27NativeMenuBarHiding.swift) 和 [macOS 27 说明](https://github.com/WuColin-1/Ice/blob/macos-27/MACOS27.md)。Ice 会根据 Combo 按钮相对于刘海的位置计算 spacer 长度、合并 300 ms 内的变化；若自己的按钮也被挤出菜单栏则撤销隐藏；为了对齐只允许在明确用户操作后 ⌘-拖**自己的**边界项。B 的实际接口、动态符号检查、切换 assertion 顺序与释放逻辑见 [MenuBarHider bridge](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/Services/MenuBarAgentBridge.swift) 和 [Hidden Bar shim](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m)；[Ice #995（开放 PR，尚未合并）](https://github.com/jordanbaird/Ice/pull/995) 报告了原生系统项目点击需要“解除限制再重放”的实机结果。

## 系统项识别、权限和恢复

- 在 macOS **27.0 (26A428)**，开源项目记录的 `MBSystemItemIdentifier` 实验值为：电池 `0`、音量 `5`、Wi‑Fi `6`，时钟 `2`、控制中心 `8`。这些是**非公开运行时值，不是 Apple 稳定协议**；必须启动时验证目标 ID 唯一、可见性变化与恢复，失败时释放 assertion，保持系统图标可用。来源：[MenuBarHider SystemItems.swift](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/Services/SystemItems.swift)、[Hidden Bar NativeVisibilityEngine.swift](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/NativeVisibilityEngine.swift)。
- `AXExtrasMenuBar` 在 **每个状态项所属应用**的根元素上读取；`MenuBarAgent` 自己的 AX 树可读项目实际容器／overflow 几何。只读定位需辅助功能权限；若要做第二菜单栏缩略图才需要屏幕录制权限。现有 Combo 只查两个系统进程并以 `AXMenuBar` 为入口，遗漏了这条路径。来源：[Ice #997 的读取器](https://github.com/WuColin-1/Ice/blob/macos-27/Ice/MenuBar/MenuBarItems/MacOS27MenuBarItemProvider.swift)、[Ice macOS 27 说明](https://github.com/WuColin-1/Ice/blob/macos-27/MACOS27.md)、[Hidden Bar AX inventory](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Layout/AccessibilityMenuBarInventory.swift)。
- **B 路径的系统菜单展开**不是 AXPress 就能保证：Ice #995 报告 clock/battery/Wi‑Fi 必须在限制撤销后重放完整 mouse-down/mouse-up；Control Center 有时可 AXPress。须以面板真的出现为成功条件，窗口／UI 消失后恢复限制。前置等待、点击放行与失败回退不能靠固定坐标或仅靠点击返回码。来源：[Ice #995](https://github.com/jordanbaird/Ice/pull/995)。
- B 的 assertion 是进程持有的临时状态：应用退出会使限制失效；主动退出、权限被撤销或任何验证失败时仍须明确 `invalidate`，并保留系统设置的手动恢复入口。不要修改系统偏好 plist、关闭 SIP 或 `killall` 系统代理作为常规恢复策略。来源：[MenuBarHider bridge](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/Services/MenuBarAgentBridge.swift)、[Hidden Bar bridge](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/Native/NativeVisibilityBridge.swift)。
- Apple 的 macOS 27 用户指南允许用户在“菜单栏”设置中加入／移除系统图标；这是可靠的**手动兜底**，不等于 Combo 可以用公开 API 替用户切换。来源：[Apple macOS 27 菜单栏指南](https://support.apple.com/guide/mac-help/customize-the-menu-bar-mchl4af84660/27/mac/27)。

## 对 Combo 的建议执行顺序

1. 在**当前已授权 Combo 进程**里做只读探针：枚举 `com.apple.MenuBarAgent` 与各 app 的 `AXExtrasMenuBar`，记录**标识／角色／动作和匿名几何**，先确认本机 Wi‑Fi、音量、电池的对象与 0/5/6 的对应关系；不要读菜单内容或发点击。当前 `-25212` 仅说明旧入口不存在。
2. 先做 A 路径的一个可撤销切换实验，验证该机器能否用 Combo 自己的 spacer 折叠**用户手动移到左侧**的三个系统图标并通过系统 overflow 打开原生菜单。如果成功，可作为无需私有 API 的首个可用版本；UI 应明确“按位置折叠”而非冒称独立自动折叠。
3. 若产品坚持三枚图标自动独立选择与不显示系统 overflow，再隔离试验 B：一次只排除一个已验证 ID，保证 Combo、时钟与控制中心始终在白名单；先测试隐藏／释放，再测试打开 Wi‑Fi 选网、声音／AirPods、电池原生界面，最后才连接设置开关。若断言激活失败或面板打不开，自动释放并显示手动恢复。**不能直接复制开源项目的完整代码**：需核查 GPLv3 许可证与项目分发方式；只参考事实与接口后独立实现。

以上是开源项目对 macOS 27.0 的实测与源码推断，**不是本机 Combo 已实现或已经通过验证**。同一 27.x 后续更新需回归；特别是系统项 ID、AX 层级、assertion 行为与多显示器／刘海布局。
