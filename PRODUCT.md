# Combo

<!-- impeccable:product-schema 1 -->

## Platform

macos

Combo 是 SwiftUI / AppKit 原生菜单栏应用。Impeccable 的平台枚举未包含 macOS；设计判断以项目 AGENTS.md、macOS Human Interface Guidelines 和 `build-macos-apps:swiftui-patterns` 为准。浏览器稿用于评审，不改变应用的平台身份。

## Product Purpose

以轻量菜单栏工具的方式，通过一个图标查看 Wi-Fi、电池和声音。应用包含总览面板、详情面板、独立设置窗口与使用引导。

## Capabilities and Constraints

- 总览采用一体式玻璃面板，集中显示媒体、电池、Wi-Fi 与声音；三页详情共用返回导航和系统设置入口。
- 设置使用顶部「通用／外观／关于」工具栏；外观提供实时菜单栏预览及 51 种效果总览，演示预览不修改系统。
- 引导帮助用户找到菜单栏右上角的 Combo 图标，理解点击打开面板、再次点击收起的操作，并反馈面板当前状态。
- 保留菜单栏排列示意及系统决定实际排列的说明；保留按住 Command 拖动图标的帮助，以及「设置 → 关于」的系统图标与其他说明指引。
- 「开始使用」始终可用，可按回车结束引导；不强制先完成演示，不增加账号、授权或其他设置步骤。
- 无内置电池的设备不展示电池相关引导内容。
- 设计原型中的设备、网络和电量为示例状态，不操作真实系统；实现与原生验证需独立完成。

## Brand Commitments

采用已确认的蓝白 AppIcon：电量弧、Wi-Fi 双弧与圆弧音乐柱；唯一主稿与导出见[品牌资源](docs/design/liquid-glass/icons/README.md)。面板、详情、设置与引导沿用 Liquid Glass 设计风格。保持 macOS 原生结构与工具栏；使用系统图标，主操作按钮采用中性色。

## Accessibility & Inclusion

保持桌面鼠标、键盘、焦点与菜单习惯；验证浅色、深色、减少动态效果、减少透明度、增强对比度和长文本。辅助功能的浏览器预览不能代替原生系统验证。

## Evidence on Hand

- 产品功能与约束：[当前产品行为](docs/product/behavior.md)、项目 AGENTS.md，以及 `PanelView.swift`、`SettingsView.swift` 和 `OnboardingView.swift` 的当前实现。
- 设计原稿、交互与验证边界：[界面与图标设计汇总](docs/design/liquid-glass/README.md)。
- [README 配图来源](docs/assets/ui-1.3.0/README.md)：从当前设计导出版截取总览、详情、设置和引导，使用示例数据。
- 设计资料整理于 2026-11-12；面板配图保留 1.3.0 快照，图标与音频设计持续更新，设计编号不代表当前发布状态。
