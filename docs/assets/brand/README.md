# Combo 品牌与 AppIcon

当前应用图标为 2026-11-06 已确认的蓝白玻璃稿：开口电量弧、Wi-Fi 双弧和沿圆弧排列的四条音乐柱。当前资源不再以历史候选字母命名。

| 用途 | 资源 |
| --- | --- |
| 唯一可编辑 AppIcon 主稿 | [`liquid-glass/combo-app-icon.svg`](liquid-glass/combo-app-icon.svg) |
| 尺寸导出、浅深背景预览与导出工具 | [`liquid-glass/`](liquid-glass/README.md) |
| README 与设计素材引用的 1024px 分发件 | [`combo-app-icon.png`](combo-app-icon.png)，与主稿的 1024px PNG 完全一致 |
| 原生应用资源 | [`AppIcon.appiconset`](../../../Combo/App/Media.xcassets/AppIcon.appiconset/Contents.json)，由 Xcode 编译打包 |
| 透明静态标志 | [`combo-iris-logo.svg`](combo-iris-logo.svg)，保留音量圆点，用于透明标志及现有品牌检查 |

设置与引导读取原生应用图标；实时菜单栏图标由 `IconRenderer` 按本机状态绘制，独立于静态 AppIcon。品牌蓝色不规定界面按钮色；本版界面采用中性操作色与语义分类图标，颜色和几何以 `Combo/Views/Theme.swift` 为准。

更新 AppIcon 时，先改唯一 SVG 主稿并运行现有 `render.cjs`，再同步 1024px 分发件、原生 10 个图标文件以及三份设计源稿及其导出版内嵌的图像。保留 PNG 的来源元数据，并执行 `Tests/App/check-brand.sh` 和适用的原生构建检查。

旧候选、重复 SVG、未使用的 Logo 变体和旧品牌概念预览已移除。当前界面资料见 [1.3.0 设计说明](../../design/liquid-glass/README.md)，界面配图见 [配图来源](../ui-1.3.0/README.md)。
