# 测试与检查入口

在仓库根目录运行 `./verify.sh`：构建应用，执行本目录的 24 个自动检查文件，并验证签名和品牌资源。检查覆盖状态规则、图标与动画、面板交互、设置与引导、本地化、网络、音频和电池控制。`main.swift` 是状态规则检查入口；`WiFiReference.png` 是 `IconTransitionCheck.swift` 使用的像素基准图。

下列文件按需手动使用，未纳入 `verify.sh`：

| 文件 | 用途 |
| --- | --- |
| `RenderIcons.swift` | 图标圆头、颜色和原生尺寸断言，以及 16 个演示状态的对照图。 |
| `RenderSettings.swift` | 全部设置页在不同语言、主题、尺寸与较大字号环境下的渲染。 |
| `LiveState.swift` | 实机读取、观察器、音量提示续期及退出清理检查；历史直接编译命令已失效，使用时需按面板检查的方式导入并链接构建后的 Combo 模块。 |
| `airpods-live-check.py` | 连接真实 AirPods 后检查 Helper；默认只读，显式 `--write` 才测试设置切换和恢复。命令见 `docs/airpods-audio-feasibility.md`。 |

已清理正式实现接入前的 `ChargeFullProbe.m`、不再参与构建的 `RenderBrand.swift`，以及被全设置页渲染工具覆盖的 `RenderMediaPage.swift`。
