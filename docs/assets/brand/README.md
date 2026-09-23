# Combo 品牌资源

当前主题为鸢尾紫。Logo 保留开口电量弧、中央 Wi-Fi 弧线与底部沿浅弧排列的四个圆点。菜单栏图标仍按实时状态单色绘制，品牌 Logo 只用于应用身份。

| 用途 | 颜色 |
| --- | --- |
| 品牌主色 / 应用图标背景 | `#7561C9` |
| 浅色界面强调色 | `#6650B4` |
| 深色界面强调色 | `#B9A5F5` |
| 浅色背景 | `#F5F3F8` |
| 深色背景 | `#26222F` |

`combo-iris-logo.svg` 是透明标志，`combo-iris-app-icon.svg` 是应用图标源文件。`Tests/RenderBrand.swift` 生成用于构建的 PNG，`build.sh` 将其打包成 `Combo.icns`。`render.py` 生成设计预览、通用 SVG 和 PNG；`combo-brand-preview.png` 是概念示意，不是 APP 截图。

白字与浅色强调色对比度 6.23:1；深色强调色与深色背景对比度 7.22:1。此前的蓝色与 C 形紫色预览保留在单独的 PNG 文件中。
