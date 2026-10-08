# Combo · Sparkle 2 接入与发布清单

整理：2026-10-08。适用条件：macOS 26+ / arm64，当前没有 Developer ID 证书；GitHub Releases 分发 DMG、GitHub Pages 提供更新清单。本文是操作指南，框架与发布脚本尚未接入，示例地址与命令不代表已经配置。

完整设计见 [远程更新方案](app-update-design.md)。本机密钥、工具、更新源与备份的实际准备结果见 [首次准备记录](sparkle-setup-record.md)。

## 1. 你首次需要准备什么

| 准备项 | 你需要做的事 | 完成标志 |
| --- | --- | --- |
| GitHub 发布权限 | 确认可以管理 `fanglinwei/Combo` 的 Releases；安排更新源的 Pages 仓库 | 可以发布公开安装包和静态文件 |
| 固定更新源地址 | 选定 Pages 站点及稳定的 `appcast.xml` 路径；第一版无需购买域名 | HTTPS 地址能匿名读取真实 XML，不能是 GitHub 文件展示页 |
| 发布 Mac | 指定一台安装完整 Xcode 的 Mac，保存 Sparkle 工具和发布历史 | 同一环境能重复生成分发包 |
| 更新签名密钥 | 使用 Sparkle 官方工具生成一次 EdDSA 密钥；私钥留在发布机钥匙串 | 公钥可嵌入 App，发布工具能用私钥签名 |
| 私钥恢复备份 | 导出私钥到受保护的加密备份，验证可恢复；不要上传仓库、聊天或公开服务器 | 换机器或系统重装后能恢复同一发布密钥 |
| 测试环境 | 准备另一台或干净的测试 Mac，走真实网络下载与升级 | 可以验证首次打开、替换、重启与权限状态 |

建议优先复用现有仓库的 Releases。Pages 可使用现有仓库或独立更新仓库；若现有 Pages 已用于官网，另建更新仓库避免冲突。仓库命名只是建议，由你管理的实际地址决定。

示例结构，未部署：

```text
https://fanglinwei.github.io/combo-updates/appcast.xml
https://fanglinwei.github.io/combo-updates/notes/1.1.0.html
https://github.com/fanglinwei/Combo/releases/download/v1.1.0/Combo-1.1.0-arm64.dmg
```

Pages 在仓库 Settings → Pages 配置，可选择分支来源或 GitHub Actions。初期使用简单的静态发布即可，确认站点发布完成后再访问 XML。不要把 `github.com/.../blob/.../appcast.xml` 配进 App；它是展示页。[GitHub Pages 配置说明](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)

## 2. 首次工程接入要完成什么

这些属于开发与打包工作，用户不需要每次手动在 Xcode 中重复配置：

- 通过 Swift Package Manager 接入锁定的 Sparkle 2 稳定版本，正确嵌入框架与辅助程序。
- 将固定更新源填入 `SUFeedURL`，将生成的公钥填入 `SUPublicEDKey`。
- 创建唯一、长期存在的更新器，接入关于页、自动检查开关和面板提醒。
- 配置默认自动检查、24 小时间隔，禁止静默自动下载安装与系统分析。
- 将 `CFBundleVersion` 改为独立递增的内部构建号，继续用 `CFBundleShortVersionString` 展示用户版本。
- 区分测试更新源与正式更新源；Debug 不消费正式安装更新。
- 调整现有 DMG 打包流程，验证 Sparkle 的符号链接、执行权限、辅助组件与 ad-hoc 签名没有被破坏。
- 准备发布脚本，生成最终包、更新说明与 appcast，并检查签名、大小、URL 和版本一致性；第一版禁用 delta 生成。

Sparkle 工具目录中首次运行：

```sh
./generate_keys --account combo-updates
```

这是官方工具命令，不是项目当前已有脚本。它将私钥保存到登录钥匙串，输出公钥供 `SUPublicEDKey` 使用。Combo 后续所有签名工具也必须指定 `--account combo-updates`。本机已完成生成，不需要再次创建；密钥不应每个版本重新生成。[Sparkle 接入与密钥说明](https://sparkle-project.org/documentation/)

私钥导出备份使用锁定工具版本的 `generate_keys -h` 核验参数，备份到加密且受保护的位置。不要用会把私钥打印到终端或日志的方式备份。换发布机应导入同一私钥，不直接生成替代密钥。

## 3. 首个支持更新的版本怎么发布

1. 将固定更新源、公钥与更新入口编译进首个支持更新的版本。
2. 创建有效初始 appcast，可列出当前首个版本；客户端应正确显示无新版本。
3. 准备两个构建号递增的测试包，用测试源完成 ad-hoc → ad-hoc 的下载、校验、安装与重启演练。
4. 在另一台或干净的测试 Mac 上验证网络下载后的首次打开与授权；复核登录项、偏好、Helper 和核心功能。
5. 发布首个支持更新的 DMG、安装说明和正式更新源。
6. 通知现有用户手动安装一次这个版本。旧版没有 Sparkle，单独发布 appcast 不会使它具备自更新能力。

当前没有 Apple 证书，因此不执行 Developer ID 签名与公证。Sparkle 的更新包签名也不代替公证。首次安装可能需要用户按 Apple 官方流程批准打开；不要承诺之后绝不再出现系统提示。[Apple 安装说明](https://support.apple.com/en-us/102445)

## 4. 以后每次发布，你需要做什么

| 顺序 | 操作 | 必须确认 |
| --- | --- | --- |
| 1 | 确定版本号和构建号 | build 大于所有已公开构建，不能只改 GitHub tag |
| 2 | 写更新说明 | 用户可理解的新增、改进、修复；涉及权限或最低系统改变时明确说明 |
| 3 | 构建并运行发布检查 | Release arm64，包内版本正确，核心功能和辅助程序可用 |
| 4 | 生成最终 DMG | ad-hoc 签名结构与镜像验证通过；确定最终字节后再签更新包 |
| 5 | 生成 EdDSA 签名与 appcast | 使用原私钥；包 URL、长度、版本、最低系统要求正确 |
| 6 | 发布 GitHub Release 的安装包 | 稳定版、版本固定文件名与下载地址；可以匿名下载 |
| 7 | 上传版本固定更新说明 | 页面可访问；清单引用地址一致 |
| 8 | 用旧版和测试源试升级 | 候选安装包与将公开的包完全一致；替换、重启、偏好、权限检查通过 |
| 9 | 最后发布正式 appcast | 所有引用资源已可访问，Pages 部署完成且读取到新版清单 |
| 10 | 从已发布旧版再检查 | 能发现新版本，包能下载且更新成功；记录发布结果 |

主顺序：**改版本 → 写说明 → 构建验证 → 最终打包 → 更新包签名 → 安装包与说明上线 → 测试 → appcast 上线 → 旧版复核。**

不要把“安装包已上传 Releases”当成“自动更新已发布”。客户端读取的是固定 appcast；只有清单更新后才会发现新版本。上传同一个 appcast 到 Releases 也不会自动改变 GitHub Pages 上的文件。

发布更新源前，候选安装包已经可以被手动下载。发现候选包有问题时停止更新源发布，并安排修复构建；不悄悄覆盖已经公开的包。

## 5. 版本号示例

| 发布 | 展示版本 | 内部构建号 | 示例 tag |
| --- | --- | --- | --- |
| 首个支持更新版本 | 1.1.0 | 101 | v1.1.0 |
| 修复版 | 1.1.1 | 102 | v1.1.1 |
| 下一功能版 | 1.2.0 | 103 | v1.2.0 |

表格仅展示规则，不替项目指定下一个版本。Sparkle 使用包内内部构建号判断更新；tag 和文件名不能代替它。公开的新构建始终递增，不复用旧构建号。[Sparkle 版本规则](https://sparkle-project.org/documentation/publishing/#internal-build-numbers)

## 6. 发布工具应该替你完成什么

建议将一次发布的大部分机械步骤封装为一个本地准备脚本，输入版本、构建号和更新说明，输出待上传目录：

```text
release-output/
  Combo-1.1.1-arm64.dmg
  appcast.xml
  notes/1.1.1.html
  release-validation.txt
```

目录仅为目标结构，目前没有新增该脚本。脚本应校验最终 App 的公钥与发布密钥匹配、build 递增、签名和版本一致，并把 appcast 包地址指向版本固定的 GitHub Release 地址。测试源覆盖在测试构建/配置中进行，不能测试时重新修改已经签名的最终包。

`generate_appcast` 是生成清单与包签名的推荐工具；如果启用更新源/说明签名，改清单或说明后还需要重新签名。具体下载地址参数和禁止生成 delta 的参数以锁定工具的帮助为准，由接入脚本固定，不要求你每次手工拼 XML。[发布文档](https://sparkle-project.org/documentation/publishing/)

当前已有 `Releases/package-dmg.sh` 只完成现有 DMG 打包，尚未承担 Sparkle 发布工作。尤其是同版本重复打包会替换本地同名文件；公开包不能这样覆盖。未来脚本要区分“本地可重做”和“已公开不可覆盖”，并防止签名后重新打包导致签名失效。

GitHub Release、tag、Pages 上传涉及实际发布和 Git 写操作；运行本地准备脚本不应默认替用户提交、打 tag 或推送。按项目规则，对具体 Git 操作与发布动作获得授权后再执行。

## 7. 每次不用做的事

- 不重新接入 Sparkle，不重新创建公私钥。
- 不更改 `SUFeedURL` 或 bundle ID。
- 不要求用户重新安装框架或手动覆盖 App（安装更新链路通过验证后）。
- 不必为每次发版创建新服务器、注册账户系统或购买域名。
- 目前没有 Developer ID，不安排无法完成的 Apple 公证步骤。

## 8. 发布后有问题怎么办

- 包/说明地址错误：修复清单链接，若启用 feed 签名则重新签名，再发布清单。
- 已公开包损坏或功能有问题：停止向未下载用户提供该清单项，发布更高 build 的修复包；不覆盖旧包、不自动降级。
- EdDSA 私钥丢失：优先恢复备份；无 Developer ID 时不能假定有备用身份可自动轮换，必要时让用户手动安装带新公钥的可信版本。
- 升级失败：保留日志与人工下载入口；没有验证过的安装链路不向用户承诺自动恢复。

## 9. 现在的完成状态

- 已完成：产品方案、无 Apple 证书条件下的发布设计、本操作清单。
- 待接入：Sparkle 依赖、更新入口、构建号规则、发布脚本。
- 已准备：固定 Pages 目标地址、EdDSA 密钥、公钥文件与经过解密比对的本机加密备份；具体位置见首次准备记录。
- 待完成：更新源文件提交/推送与 Pages 启用、独立外部备份、真实测试环境。
- 待验证：真实网络下载后的 ad-hoc → ad-hoc 更新演练。

已在后续首次准备步骤创建密钥和本机加密备份。尚未部署 Pages、发布 Release、修改客户端代码或执行 Git 写操作。
