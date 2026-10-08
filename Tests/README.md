# 测试与检查入口

在仓库根目录运行 `./verify.sh`：构建应用，执行本目录的 25 个自动检查文件，并验证签名和品牌资源。检查覆盖状态规则、图标与动画、面板交互、设置与引导、本地化、网络、音频、电池控制和更新检查状态。`main.swift` 是状态规则检查入口；`WiFiReference.png` 是 `IconTransitionCheck.swift` 使用的像素基准图。

下列文件按需手动使用，未纳入 `verify.sh`：

| 文件 | 用途 |
| --- | --- |
| `RenderIcons.swift` | 图标圆头、颜色和原生尺寸断言，以及 16 个演示状态的对照图。 |
| `RenderSettings.swift` | 全部设置页在不同语言、主题、尺寸与较大字号环境下的渲染。 |
| `LiveState.swift` | 实机读取、观察器、音量提示续期及退出清理检查；历史直接编译命令已失效，使用时需按面板检查的方式导入并链接构建后的 Combo 模块。 |
| `airpods-live-check.py` | 连接真实 AirPods 后检查 Helper；默认只读，显式 `--write` 才测试设置切换和恢复。命令见 `docs/airpods-audio-feasibility.md`。 |

已清理正式实现接入前的 `ChargeFullProbe.m`、不再参与构建的 `RenderBrand.swift`，以及被全设置页渲染工具覆盖的 `RenderMediaPage.swift`。

## Sparkle 安装检查

发布产物准备脚本的版本防护检查：`python3 Releases/updates/test-prepare-update.py`。实际签名、DMG 与生成清单还应按发布清单使用隔离包验证；这组单元检查不替代正式版本验收。

`AppUpdaterCheck.swift` 已纳入 `verify.sh`，验证 Debug 不启动更新、失败不覆盖成功检查时间、成功时间持久保存。

`SparkleFeedCheck.swift` 是按需使用的线上 HTTPS 清单检查工具，需要编译进带有更新源和公钥的独立测试 Bundle；不创建安装会话。

使用真实 Release App 和 Sparkle 官方工具，运行隔离安装测试：

```sh
python3 Tests/check-sparkle-install.py --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
python3 Tests/check-sparkle-install.py --invalid-signature --app build/dmg-release/Build/Products/Release/Combo.app --sparkle "$SPARKLE_DIR"
```

`SPARKLE_DIR` 指向同时包含 `Sparkle.framework` 和 `bin/sign_update` 的官方工具目录；签名使用本机钥匙串 `combo-updates` 账户。此检查创建临时测试 Bundle 与回环 HTTP 源，仅为该测试源关闭 ATS；正式 Info.plist 保持 HTTPS。测试完成后删除临时包，不修改原 App、不上传正式 appcast。正向测试验证替换和最终嵌套签名，负向测试验证错误签名被拒绝；标准窗口中的自重启和干净 Mac 首次下载验收仍需单独执行。
