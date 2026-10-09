# Sparkle 更新与发布维护

整理：2026-10-09。适用范围：macOS 26+、Apple Silicon、稳定版全量 DMG。客户端已接入 Sparkle；此文统一现行发布流程、签名恢复和验证边界，不再维护早期接入任务与部署流水账。

## 当前基线

| 项目 | 仓库现状 |
| --- | --- |
| 应用身份 | `local.combo.app`；菜单栏应用，保持 bundle ID 连续性 |
| 版本 | [Info.plist](../../Combo/App/Info.plist) 为 `1.2.0 / 102`；后续以文件实际值为准 |
| 框架 | 远端 SPM Sparkle，Package.resolved 锁定 2.10.0 |
| 固定更新源 | [HTTPS appcast](https://fanglinwei.github.io/Combo/updates/appcast.xml) |
| 本地清单 | [appcast.xml](../updates/appcast.xml) 已有 `1.1.0 / 101`、`1.2.0 / 102` 两条项 |
| 说明地址 | `updates/notes/Combo-版本-arm64.html`，已被清单以绝对 URL 引用 |
| 包地址 | GitHub Releases 的版本固定 DMG；现有标签是 `1.1.0`、`1.2.0`，无 `v` 前缀 |
| 签名 | 当前流程为 ad-hoc 应用签名 + Sparkle EdDSA 包签名；无 Developer ID、公证 |

本地条目和版本不证明线上部署、包可下载或用户升级已成功。2026-10-08 的历史记录曾验证固定 Pages HTTPS 地址；当前 Pages 来源分支与部署状态需发布时重新查询，不沿用旧 `feature/update` 来源断言。保持公开 URL 不变，并在删除任何来源分支前检查 Pages 配置。

## 客户端行为与职责

一个应用生命周期内的共享 [AppUpdater](../../Combo/App/AppUpdater.swift) 持有标准更新器。Sparkle 管理调度、版本选择、下载、校验、安装与标准窗口；Combo 管理关于页、自动检查偏好与轻量提醒。选择框架可避免维护自建安装器；早期 Ice、MonitorControl、Stats 的比较仅作为选型背景，不构成当前实施任务。

- “设置 → 关于与帮助”提供检查／查看更新与自动检查开关；按钮随 `canCheckForUpdates`，避免重复会话。
- 自动检查默认开启，间隔 86400 秒；禁止自动下载安装，关闭系统概况上传。Debug 不启动更新器。
- 手动或自动成功获取结果后，将时间存为 `lastSuccessfulUpdateCheck`；失败保留旧成功时间，从未成功时显示“尚未检查”。
- 后台发现更新时，面板设置入口显示小圆点，关于页显示版本；不抢焦点、不申请系统通知，不改变核心图标语义。结束会话后清除提醒。
- 用户确认后由标准窗口下载、安装和重启；关闭设置窗口不取消下载。恢复显示偏好不重置更新偏好。
- 检查失败不能显示“已是最新版本”；签名不匹配终止安装，不提供绕过校验入口。不可更新路径、权限不足、DMG 运行与 App Translocation 的反馈仍需真实验收。

检查更新会向托管服务发送网络请求，服务可能看到 IP 和常规请求信息；不上传电量、网络状态、音量或媒体内容。完整交互规格见 [产品行为](../product/behavior.md#settings)。不增加 Beta、delta、强制升级、账户或自建提权脚本。

## 每次发布流程

1. 确定展示版本与更高的独立内部构建号，写完整 HTML 说明；说明使用新增／改进／修复，明确权限与最低系统变化。
2. 执行现有源码验证和核心功能回归，使用 [DMG 打包器](../../Releases/package-dmg.sh) 生成最终 Release arm64 包；检查嵌套签名、符号链接、权限与包内版本。
3. 对最终 DMG 使用原 `combo-updates` 私钥生成 EdDSA 签名和候选 appcast；生成后不再改包字节。
4. 先上线版本固定安装包与说明，验证匿名 HTTPS 下载、实际大小、签名、架构和最低系统要求。
5. 用旧版和测试源演练同一个候选包：替换、重启、偏好与权限连续性。测试源在测试构建／配置中覆盖，不重新修改已签名最终包。
6. 最后发布正式 appcast，确认 Pages 部署后匿名 HTTPS 读取到正确内容，再从旧版复核发现与升级。

上传 Releases 不等于发布自动更新；客户端读取固定 appcast。包有问题时停止清单发布，不覆盖已公开同名包。保留已验证旧兼容项，修复使用更高 build，不自动降级。没有 Sparkle 的更早安装版本需要手动安装一次支持更新的版本。

Git 分支、暂存、提交、标签、推送与线上发布均遵守项目的具体操作授权规则；文档或本地准备脚本不能自动授予这些权限。

## 本地候选准备工具

[prepare-update.py](../../Releases/updates/prepare-update.py) 接收打包器生成的最终 DMG 与完整 HTML 说明，只读核对线上清单和同标签 Release，验证递增版本/build、包内版本、固定更新源、公钥、arm64 架构与嵌套签名，再调用官方工具生成并复核清单。任何非 404 的 Release 查询错误都停止，不把鉴权或限流视为未发布。

以下为参数模板，版本、构建号和文件应替换为本次已审核值；不是指定下一个版本：

```sh
python3 Releases/updates/prepare-update.py \
  --dmg /absolute/path/to/final-Combo-version-arm64.dmg \
  --version VERSION --build BUILD --tag TAG \
  --notes /absolute/path/to/reviewed-notes.html \
  --output /absolute/path/to/new-candidate-directory
```

输出为最终 DMG、`appcast.xml`、`notes/Combo-VERSION-arm64.html` 与 `release-validation.json`。JSON 记录 SHA-256、大小、线上清单基线、版本与 URL，不代替源码检查、功能验收或发布记录。目录不得已存在；线上清单变化后须重新准备候选。脚本不创建/导出密钥、不修改生产清单、不执行 Git 或 GitHub 写操作。

默认官方工具目录为 `~/Library/Caches/Combo/Sparkle/2.10.0/spm`，指定账户 `combo-updates`，不生成 delta。打包器重复打包会替换本地同名文件；上传必须用候选目录中摘要已记录的精确 DMG。说明复制至 `docs/updates/notes/`、清单部署至 `docs/updates/appcast.xml`，均在包和说明上线且升级验收后执行。

## 密钥、备份与恢复

以下位置来自 2026-10-08 的准备记录，不包含私钥或密码；换机器时核对实际环境。

| 内容 | 位置／标识 |
| --- | --- |
| 官方工具 | `/Users/fun/Library/Caches/Combo/Sparkle/2.10.0/bin`；准备脚本使用同版本 `spm` 工具目录 |
| 私钥 service / account | `https://sparkle-project.org` / `combo-updates` |
| 公钥 | [public-ed-key.txt](../updates/public-ed-key.txt)，必须与客户端 `SUPublicEDKey` 一致 |
| 加密备份 | `/Users/fun/Library/Application Support/Combo/ReleaseBackups/combo-updates-private-ed-key-2026-10-08.enc` |
| 恢复密码 service / account | `Combo Sparkle Backup Recovery` / `combo-updates` |

历史记录已验证本机备份加解密逐字节一致，参数为 AES-256-CBC、PBKDF2-HMAC-SHA256、600000 次迭代，备份仅当前用户可读写。工具缓存清理后可重下载并验证同版官方工具，不能因此重建发布密钥。

**独立外部备份与另一台 Mac 的恢复导入演练仍待完成。** 加密备份与恢复密码同在一台 Mac，不能抵御整机丢失。将 `.enc` 保存到外部介质或受保护的备份服务；经本人解锁钥匙串后将密码保存到独立密码管理器。两者不要一起放在普通目录，不上传仓库或聊天。

所有官方工具指定 `--account combo-updates`，避免误用默认账户。日常公钥核对／签名示例：

```sh
"/path/to/Sparkle/bin/generate_keys" --account combo-updates -p
"/path/to/Sparkle/bin/sign_update" --account combo-updates "/path/to/final.dmg"
```

新 Mac 下载并验证官方工具，从独立备份取回 `.enc` 与密码。解密到受保护临时目录，密码在 OpenSSL 交互提示中输入，不写进命令、脚本或 shell 历史：

```sh
umask 077
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 \
  -in "/path/to/combo-updates-private-ed-key-2026-10-08.enc" \
  -out "/protected/temp/private-ed-key.txt"
"/path/to/Sparkle/bin/generate_keys" --account combo-updates \
  -f "/protected/temp/private-ed-key.txt"
"/path/to/Sparkle/bin/generate_keys" --account combo-updates -p
```

先确认目标账户没有不同密钥；导入后公钥必须与仓库文件完全一致，再删除临时明文。当前只验证了加解密一致性，未在另一台 Mac 导入。无 Developer ID 时不能假定有备用信任路径进行自动密钥轮换；丢失私钥先恢复备份，必要时让用户手动安装带新公钥的可信版本。

## 安全与事故处理

- ad-hoc 代码签名不提供 Apple 认可的开发者身份；EdDSA 验证包与客户端公钥对应。保持 HTTPS、公钥和 bundle ID，不盲目递归重签整个包。
- 首次互联网安装仍可能被 Gatekeeper 拦截；按 [Apple 官方打开说明](https://support.apple.com/en-us/102445) 处理可信来源，不自动关闭系统保护或删除 quarantine。受管理设备可能不允许批准。
- 未来 Developer ID、公证、Hardened Runtime 迁移需验证全部 helper、媒体和设备控制；保持原 EdDSA 信任，单独演练身份、权限与登录项连续性。
- 清单/说明签名尚未作为已启用能力记录；若将来启用，内容修改后须重新签名并验证轮换与失败策略。
- 包或说明链接错误时修复清单；功能或包损坏时撤下问题清单项并发布更高 build。已下载/安装用户不保证能远程撤回。
- 安装失败保留日志与人工下载入口；未验证的失败恢复不承诺自动回滚。未通过真实安装链路时，评估 Sparkle 信息型更新，不隐藏失败。

## 验证入口与剩余验收

日常入口是 `./verify.sh`；更新状态测试、[更新准备检查](../../Releases/updates/test-prepare-update.py) 与 [安装检查脚本](../../Tests/check-sparkle-install.py) 以现有文件和运行结果为准。

2026-10-08 的历史隔离测试使用回环源、真实 Release 副本与隔离 bundle ID：有效 EdDSA 的 DMG 从 build 1 替换到 2，嵌套签名通过；错误签名被拒绝，原版本保留。历史候选准备试验也验证了签名、清单字段与 DMG 字节不变。这些是本机测试，不代表正式用户网络、干净 Mac 或当前包完整验收；本次整理未重跑安装或应用测试。

剩余验收包括：真实网络下载与首次批准；标准窗口的安装和自重启；连续两次升级；偏好、权限、登录项及核心功能保持；离线/损坏清单/截断包/不兼容架构；DMG、只读路径与权限不足；取消和失败恢复；启动/全屏下不抢焦点；中英文、最小窗口、键盘与 VoiceOver。

历史来源：[Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)、[接入](https://sparkle-project.org/documentation/programmatic-setup/)、[配置](https://sparkle-project.org/documentation/customization/)、[发布与内部版本号](https://sparkle-project.org/documentation/publishing/)、[轻量提醒](https://sparkle-project.org/documentation/gentle-reminders/)、[ad-hoc 支持讨论](https://github.com/sparkle-project/Sparkle/discussions/2764)。来源沿用既有调研，本次未重新在线核查。
