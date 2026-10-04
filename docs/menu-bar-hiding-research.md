# Combo：隐藏系统菜单栏图标的可行性

核查日期：2026-09-22。目标 macOS 26；仅调研，未修改用户系统设置。原手动隐藏建议保留为调研记录；后续已确认可选折叠模式，见末节。

## 结论

用户可以在“系统设置 → 菜单栏”取消显示 Wi-Fi、电池、声音、蓝牙、正在播放等项目。新增 Combo 本身不会自动隐藏它们，也不需要为手动隐藏授予 Combo 任何额外权限。

AirPods 形状的常驻声音图标属于声音菜单的设备化呈现，Apple 的 AirPods 指南明确通过菜单栏设置中的 Sound 启用它；隐藏声音项可移除这一入口。但设备连接/音量等临时提示、隐私指示、其他应用的耳机图标不是同一对象，不能承诺全部随之消失。

隐藏菜单入口不等于关闭 Wi-Fi、蓝牙或音频服务。用户仍可通过控制中心或系统设置操作；Combo 的系统状态采集不依赖原图标是否显示。后一句是依据现有 API 架构的工程判断，仍应在签名产品验收中测试。

## 自动隐藏的边界

AppKit NSStatusBar / NSStatusItem 提供本应用状态项的创建与管理；此次未找到 Apple 文档支持的、可按名称隐藏其他进程系统状态项的通用公开 API。removeStatusItem 不是删除任意系统图标的接口。

辅助功能自动点击系统设置属于 UI 自动化，受设置页布局、语言、系统小版本影响；读取播放器的既有辅助功能用途不应默认为同时允许改系统设置。写入未公开 defaults / plist 键也不是稳定支持接口。因此不建议把“一键自动隐藏系统图标”列为首版已保证能力。

## 原手动隐藏建议（不适用于原生菜单折叠模式）

提供可跳过的“整理菜单栏”引导，列出 Wi-Fi、电池、声音（耳机）、可选蓝牙及正在播放，指导用户在系统设置取消勾选。提供恢复说明；不要求额外权限，不自动改设置，不把用户点“已完成”当作已经检测到隐藏成功。

保留控制中心作为高级操作入口：Combo 首版不包含 Wi-Fi 选网、AirPods 降噪/空间音频、完整媒体控制。用户手动隐藏的系统项目不会因为退出或卸载 Combo 自动恢复，应明确说明如何重新勾选。

“打开菜单栏设置”的深链接需目标系统实测；无法稳定直达时打开系统设置并显示文字路径，不宣称存在已保证的公共导航 API。

验收：隐藏/恢复各项；AirPods 连接/断开；Combo 退出；睡眠唤醒；控制中心功能保留；基础数据仍可读取；系统临时提示不纳入永久隐藏承诺。

## 官方依据

- [macOS 26 菜单栏设置](https://support.apple.com/guide/mac-help/mchlad96d366/26/mac/26)：列出 Wi-Fi、Bluetooth、Battery、Sound、Now Playing 的显示选项。
- [macOS 26 自定菜单栏](https://support.apple.com/guide/mac-help/mchl4af84660/26/mac/26)：取消选中移除，重新选中恢复。
- [AirPods 空间音频与头部跟踪](https://support.apple.com/en-me/guide/airpods/-dev00eb7e0a3/web)：AirPods 菜单图标通过 Sound 项显示。
- [NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)：应用状态项管理 API。未找到通用跨进程隐藏 API 是本次调研结论，不是证明所有私有或自动化手段都不存在。

## 当前决定与保留的研究

当前版本由用户在系统设置中手动隐藏图标，Combo 提供记录、指引和确认恢复，不自动折叠或在退出时恢复。行为以 [设置规格](combo-settings.md#41-系统图标记录与手动恢复) 为准。

Ice 的占位折叠、临时移动与点击机制仅保留为研究证据，不作为当前实施要求。macOS 实测边界见 [菜单折叠研究](macos27-menu-folding-research.md)。

- [Ice 折叠控制项](https://github.com/jordanbaird/Ice/blob/main/Ice/MenuBar/ControlItem/ControlItem.swift)
- [临时展开和点击](https://github.com/jordanbaird/Ice/blob/main/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift)
- [权限定义](https://github.com/jordanbaird/Ice/blob/main/Ice/Permissions/Permission.swift)
- [私有接口声明](https://github.com/jordanbaird/Ice/blob/main/Ice/Bridging/Shims/Private.swift)
