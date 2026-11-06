# Combo 界面设计

Combo 是使用 SwiftUI 和 AppKit 的 macOS 原生菜单栏应用，包含总览面板、详情面板和独立设置窗口。

- 设计或调整界面时，以 `build-macos-apps:swiftui-patterns` 和 macOS Human Interface Guidelines 为基础；用 `emilkowalski-skills:apple-design` 参考即时反馈、空间连续性、可中断动效和克制原则。
- 使用 Codex 全局技能 `~/.codex/skills/impeccable/SKILL.md` 辅助设计审查、布局调整和细节打磨。应用界面采用 Impeccable 的 Operate 模式，优先保证扫读效率、状态清晰和操作可靠。
- Impeccable 的平台选项没有 macOS；保持 Combo 的真实平台身份，将通用设计建议落实到 SwiftUI/AppKit，按 macOS 规范判断适用性。
- 改进现有界面时延续已有视觉语言，复用 `Combo/Views/Theme.swift` 的主题与几何定义、现有组件及状态模型。
- 保持鼠标、键盘、焦点和菜单交互符合桌面习惯；尊重系统辅助功能设置，并验证浅色、深色、减少动态效果及长文本下的表现。
- 界面改动后执行与范围相符的构建和视觉验证；无法运行或查看时，明确标注未验证的部分。
