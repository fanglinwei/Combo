# Combo

<!-- impeccable:product-schema 1 -->

## Platform

macos

Combo 是 SwiftUI / AppKit 原生菜单栏应用。Impeccable 的平台枚举未包含 macOS；设计判断以项目 AGENTS.md、macOS Human Interface Guidelines 和 `build-macos-apps:swiftui-patterns` 为准。浏览器稿用于评审，不改变应用的平台身份。

## Product Purpose

以轻量菜单栏工具的方式，通过一个图标查看 Wi-Fi、电池和声音。应用包含总览面板、详情面板、独立设置窗口与使用引导。

## Capabilities and Constraints

- 引导帮助用户找到菜单栏右上角的 Combo 图标，理解点击打开面板、再次点击收起的操作，并反馈面板当前状态。
- 保留菜单栏排列示意及系统决定实际排列的说明；保留按住 Command 拖动图标的帮助，以及「设置 → 关于」的系统图标与其他说明指引。
- 「开始使用」始终可用，可按回车结束引导；不强制先完成演示，不增加账号、授权或其他设置步骤。
- 无内置电池的设备不展示电池相关引导内容。
- 设计原型中的设备、网络和电量为示例状态，不操作真实系统；实现与原生验证需独立完成。

## Brand Commitments

延续 Combo 现有标识及本次用户指定的 Liquid Glass 面板、详情和设置设计风格。保持 macOS 原生结构与工具栏；使用系统图标，主操作按钮采用中性色。

## Accessibility & Inclusion

保持桌面鼠标、键盘、焦点与菜单习惯；验证浅色、深色、减少动态效果、减少透明度、增强对比度和长文本。辅助功能的浏览器预览不能代替原生系统验证。

## Evidence on Hand

- 产品功能与约束：用户本轮「引导功能不变」的要求、项目 AGENTS.md、`Combo/Onboarding/OnboardingView.swift`。
- 设计原稿、交互与验证边界：[Liquid Glass 设计说明](docs/design/liquid-glass/README.md)。
- 品牌资产：`docs/assets/brand/`；引导稿复用现有面板中的壁纸、菜单栏图标与 SF Symbols 导出素材。
