# 菜单栏管理：当前行为与折叠研究

整理：2026-10-04。合并 2026-09-22 的手动隐藏研究、2026-09-23 的 macOS 27/Thaw 调研和本机实验。自动折叠继续暂停，研究记录不代表已授权恢复实现或开展系统写入试验。

## 当前行为

用户在 macOS“系统设置 → 菜单栏”手动取消 Wi-Fi、声音、电池等项目的显示。Combo 提供可跳过的指引、适用项目基线记录及用户确认后的恢复；具体权限、完整读取、不覆盖旧记录与失败项重试规则见 [设置规格](combo-settings.md#41-系统图标记录与手动恢复)。退出、重启及权限变化不自动恢复，也不自动启用折叠。

手动查看指引不需要授予 Combo 权限；读取、记录与恢复需对应权限和成功检测。勾选偏好、实际可见性、辅助功能权限分别表示不同信息，用户点击“已完成”不等于检测通过。

隐藏声音项可移除其 AirPods 常驻设备图标；连接/音量临时提示、隐私指示和其他应用耳机图标不是同一对象。隐藏入口不关闭 Wi-Fi/蓝牙/音频服务，控制中心和系统设置仍可用；Combo 数据源不依赖原图标，但完整签名应用仍需实机验收。

## 历史折叠实验与方案比较

2026-09-23，macOS 27.0 build `26A428` 上先前 ControlCenter/SystemUIServer 的 AX 根属性返回 `kAXErrorNoValue`，不能据此断言权限无效或所有入口不可用。后续 MenuBarAgent AX 树暴露 Wi-Fi、声音、电池独立标识；CGS 枚举只取得整块菜单栏窗口，未建立逐项窗口身份。

| 方案 | 机制 | 历史结果 / 产品限制 |
| --- | --- | --- |
| 系统设置手动隐藏 | 用户独立切换三个复选框 | 本机每次仅移除目标，Combo 与其他项保留；设置持久化，退出不自动恢复 |
| AppKit spacer / overflow | Combo 左侧加宽空白状态项，将连续左侧图标挤入系统 overflow | 按位置成组，不满足任意三个独立开关；拥挤/刘海/多屏可能连自身入口受影响，未通过本机完整验收 |
| MenuBarClientCore 私有 assertion | 系统项 ID + 应用 bundle 白名单；释放解除限制 | 本机单项排除同时令 Combo 从 AX 树消失，暂停；原生菜单点击也未确认成功 |
| Thaw 公开机制 | 大分隔项 + 窗口/AX 关联 + Command 合成拖拽 + 临时放出点击/拖回 | macOS 27 发行版来自另一私有仓库，公开分支不证明 27 上同机制可用；布局可能持久化，不保证崩溃后立即恢复 |

### 私有 assertion 的已知失败

旧逐项 8 秒实验观察目标约第 3 秒消失，释放后恢复；后续隔离 15 秒实验只排除 Wi-Fi ID 6 时，Wi-Fi 与 Combo 同时从 AX 树消失，其他目标及部分第三方图标保留。Combo 的 bundle ID 已在白名单，临时增加稳定 autosaveName 后同样失败。AX 树不是像素证明，但已不足以通过“恢复入口始终可见可点”的验收；`NSStatusItem.isVisible == true` 也不能代替视觉与点击检查。

历史 macOS 27.0 私有系统 ID：电池 0、声音 5、Wi-Fi 6、时钟 2、控制中心 8。它们不是 Apple 稳定协议。白名单按 bundle 管理第三方项目，不能保证精确控制同一应用的一枚图标。系统菜单打开可能需先释放限制、等待、再重放点击；本机 AXPress 与坐标点击未观察到原生菜单，不能只看动作返回码。

AppKit 只管理本应用 NSStatusItem，`removeStatusItem` 不可用于删除其他应用的系统图标。系统自身能独立隐藏不证明 Combo 获得了公开自动控制接口；自动点击设置是 UI 自动化，受语言/布局影响且留下持久设置，不能满足“退出/崩溃自动恢复”的旧折叠目标。

### Thaw 的可复核机制

公开研究固定到 [Thaw 提交 46a306a9](https://github.com/thaw-app/Thaw/tree/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4)：ControlItem 用约 10,000 pt 分隔项推走左侧项目；私有 `CGSGetProcessMenuBarWindowList` 取得窗口，XPC 将窗口几何与各应用 AX extras 关联；实时身份核查后合成 Command 拖动。临时展开记录原分区/位置，放出并点击，菜单结束再拖回，失败保留恢复记录。

[源码选择 action](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/.github/actions/checkout-source/action.yml#L1-L6)将 `thaw-next` 明确列为私有 macOS 27 仓库，不能用公开 README 的系统支持范围推导未运行的发行版内部机制。公开源码的辅助功能用于发现/移动/点击，录屏用于预览等功能；不能无证据为 Combo 额外要求录屏。项目为 GPL-3.0，研究机制不等于可直接移植到任意分发形态。

## 后续进入条件

重启折叠工作前，先完成当前进程只读定位，确认目标唯一且自身入口可观测；AXExtrasMenuBar、MenuBarAgent 容器与 overflow 几何是不同入口，不能仅按标题或固定坐标动作。

任何隔离试验必须同时证明：Combo 全程可见可点击、目标逐项独立、失败/退出后能恢复、原生菜单能打开。普通、拥挤、刘海、多显示器布局均需验证；一次短时成功不等于跨版本交付。不能靠写未公开 plist、关闭 SIP、重置全局 TCC 或重启系统代理作为常规恢复。

spacer 若只能连续折叠，需另行确定产品语义；私有路径需核实 ID、权限、assertion 释放与菜单重放。当前没有满足全部条件的方案，预选、授权和只读诊断都不自动恢复折叠。

## 历史来源

以下保留原核查来源，本次整理未重新在线验证上游 PR 状态：

- Apple：[macOS 26 菜单栏设置](https://support.apple.com/guide/mac-help/mchlad96d366/26/mac/26)、[macOS 27 手动整理](https://support.apple.com/guide/mac-help/customize-the-menu-bar-mchl4af84660/27/mac/27)、[NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)、[NSStatusItem.isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)。
- [Ice macOS 27 spacer 源码](https://github.com/WuColin-1/Ice/blob/macos-27/Ice/MenuBar/MacOS27NativeMenuBarHiding.swift)、[说明](https://github.com/WuColin-1/Ice/blob/macos-27/MACOS27.md)、[PR #997](https://github.com/jordanbaird/Ice/pull/997)、[原生点击 PR #995](https://github.com/jordanbaird/Ice/pull/995)：上游机制/观察，非 Combo 本机验收。
- [MenuBarHider bridge](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/Services/MenuBarAgentBridge.swift)、[系统 ID 表](https://github.com/happy666End/MenuBarHider/blob/main/MenuBarHider/Services/SystemItems.swift)、[Hidden Bar shim](https://github.com/dwarvesf/hidden/blob/develop/hidden/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.m)：私有运行时白名单与释放机制。
- [Thaw 分隔项](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/Thaw/MenuBar/ControlItem/ControlItem.swift)、[身份关联](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/MenuBarItemService/SourcePIDCache.swift)、[临时展开](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/Thaw/MenuBar/MenuBarItems/MenuBarItemManager/MenuBarItemManager%2BTemporaryShow.swift)、[许可](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/LICENSE)。
