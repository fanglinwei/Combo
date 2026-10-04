# Combo DMG 打包

在项目根目录执行：

```sh
./Releases/package-dmg.sh
```

也可进入 `Releases` 文件夹后执行 `./package-dmg.sh`。脚本会根据自身位置定位项目，输出仍放在同一个 `Releases` 文件夹中。

脚本先增量构建当前源码的 Release App，再生成 `Releases/Combo-<版本号>-arm64.dmg` 和 `Releases/安装指南.html`。版本号、build 号及最低 macOS 版本均取自本次 App 的 `Info.plist`。首次完整构建之后，Xcode 会复用 `build/dmg-release` 中的构建缓存。

已有构建产物时，可跳过构建：

```sh
./Releases/package-dmg.sh --app "/absolute/path/to/Combo.app"
```

`--app` 需要完整的 Combo App，主程序具有执行权限，主程序和内置辅助程序均为纯 `arm64`。脚本复制 App 后，在临时副本上重新生成 ad-hoc 签名；不会修改传入的 App。

## 运行环境

- macOS 和完整 Xcode。默认从源码构建需要 Apple Silicon Mac，以及支持项目最低系统版本的 macOS SDK。
- Python 3.10 或更高版本，且可使用 `venv` 和 `pip`。
- 首次运行自动创建 `build/dmg-venv`，从 Python 包仓库安装 `requirements.txt` 中固定的两个依赖。环境就绪后，后续打包不需要联网，不使用 Codex 的运行时或缓存。
- 默认 Xcode 路径为 `/Applications/Xcode.app/Contents/Developer`。不同安装位置可使用已有构建入口的环境变量：

```sh
COMBO_DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer" ./Releases/package-dmg.sh
```

## 生成内容与检查

DMG 使用 HFS+ 和 UDZO 压缩，沿用当前浅色 Retina 背景、放大的 Combo → Applications 拖动安装布局，以及下排三个辅助入口：安装指南、允许任意来源、清除下载隔离。指南使用浅灰文档图标，两个脚本共用缩小的深灰终端图标；Finder 隐藏这三个文件的扩展名。DMG 内提供 HTML 指南，不生成 Markdown 指南。

发布前自动检查全部 Mach-O 文件的架构、App 签名、主程序执行权限、文件内容、Applications 链接、Finder 布局、图标资源与脚本执行权限，并验证压缩镜像的完整性。两个安装辅助脚本仅做语法检查，打包过程中不会执行它们，也不会修改本机 Gatekeeper 设置。

本流程使用 ad-hoc 签名，没有 Apple 开发者身份签名，也不进行公证；首次启动的放行方法仍保留在安装指南中。

## 输出与失败处理

同版本重复运行会替换同名 DMG，只有新镜像全部校验通过后才发布。构建或校验失败时，已有 DMG 和指南会保留。发布前会检查两份目标是否锁定，并在 `Releases/.combo-publish-*` 临时目录中备份旧文件及图标资源；任一替换失败，或发布期间收到 INT、TERM、HUP 信号，会恢复旧文件。首次发布失败时会移除已生成的部分输出。如果恢复也失败，会保留备份目录并显示位置。

目标 DMG 正在挂载时，脚本会停止并提示先在 Finder 中弹出；它只自动卸载本次创建的临时镜像。即使挂载成功后解析设备信息失败，也会按本次临时镜像的完整路径找回设备并卸载。

构建日志位于 `build/dmg-release-build.log`，最近一次通过的镜像校验日志位于 `build/dmg-package-verify.log`。中断或失败时会清理本次临时工作目录；如果无法确认临时镜像已卸载，会保留该目录并显示位置。两份文件各自使用原子重命名，常规错误会回滚；断电或 `kill -9` 无法触发清理与回滚，可能留下发布备份、临时镜像和 `build/dmg-package.lock`。此时先确认没有打包任务运行，恢复备份并弹出遗留临时镜像，再移除空锁目录重试。

## 回归检查

完成首次打包、自动安装布局依赖后，可运行：

```sh
./build/dmg-venv/bin/python Releases/packaging/test-dmg.py
```

检查覆盖主程序缺少执行权限、指南锁定、第二份文件替换失败、首次发布失败、发布期间终止，以及真实临时镜像的设备解析失败和首次卸载失败。测试使用独立临时目录，不运行安装辅助脚本，也不替换正式发行文件。

## 修改资源

`安装指南.template.html` 是指南来源；保留其中的 `@VERSION@`、`@BUILD@`、`@MINIMUM_MACOS@` 和 `@DMG_NAME@` 占位符。

`assets/` 保存最终背景和两枚图标。图标不在每次打包时重绘；如果修改 `render-icons.swift`，可先重新生成 PNG：

```sh
xcrun swift Releases/packaging/render-icons.swift Releases/packaging/assets
```

`set-icons.swift` 在每次打包时给实际文件安装图标和隐藏扩展名。`dmg.py` 从零生成 `.DS_Store`，并对最终镜像进行检查。入口脚本位于 `Releases/package-dmg.sh`，全部打包资源位于 `Releases/packaging/`，清理 `build/` 后仍可重新打包。
