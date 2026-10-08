# Combo · Sparkle 首次准备记录

日期：2026-10-08。本记录不含私钥或恢复密码。

## 已完成

- 首次 GitHub API 检查确认 `fanglinwei/Combo` 为公开仓库，当前账户有 admin/push 权限，默认分支为 `main`；当时尚未启用 Pages。
- 固定更新源为 `https://fanglinwei.github.io/Combo/updates/appcast.xml`；Pages 已部署，旧域名继承问题已在用户额外授权后解除，默认 HTTPS 地址验证通过，见部署记录。
- 准备静态更新源文件；XML 语法检查通过，当前没有发布条目。
- 下载官方 Sparkle 2.10.0，SHA-256 与 GitHub Release asset digest 一致：`c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`。
- 使用官方工具创建专用账户 `combo-updates` 的 EdDSA 密钥；私钥存钥匙串，公钥存 `updates/public-ed-key.txt`。
- 完成加密备份及解密逐字节比对，临时明文导出文件已删除。
- 官方 `sign_update` 对临时文件签名并验证通过；未签名或发布实际 App 更新。

来源：[Sparkle 2.10.0 官方 Release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)。

## 本机位置

| 内容 | 位置/标识 |
| --- | --- |
| 官方工具 | `/Users/fun/Library/Caches/Combo/Sparkle/2.10.0/bin` |
| 私钥 service / account | `https://sparkle-project.org` / `combo-updates` |
| 加密备份 | `/Users/fun/Library/Application Support/Combo/ReleaseBackups/combo-updates-private-ed-key-2026-10-08.enc` |
| 恢复密码 service / account | `Combo Sparkle Backup Recovery` / `combo-updates` |
| 公钥 | `docs/updates/public-ed-key.txt` |

工具目前位于缓存目录，清理后可重新下载同一官方版本并验证；密钥与备份不在缓存目录中，不需重新生成。

## 独立备份仍需由维护者完成

加密备份和恢复密码目前都在这台 Mac，属于已验证的本地备份，尚不能应对整机丢失。请将 `.enc` 复制到外部介质或受保护的备份服务；在“钥匙串访问”中查找 `Combo Sparkle Backup Recovery`，经本人解锁后将恢复密码保存到独立密码管理器。两者不要一起放在普通文件夹中，不发送到聊天。

加密参数为 OpenSSL AES-256-CBC、PBKDF2-HMAC-SHA256、600000 次迭代；恢复密码随机生成且只存钥匙串，不是 Mac 登录密码。备份文件仅当前用户可读写。

## 日常签名账户

所有工具都指定 `--account combo-updates`，包括 `generate_keys`、`sign_update` 和 `generate_appcast`，避免使用默认账户的错误密钥：

```sh
"/Users/fun/Library/Caches/Combo/Sparkle/2.10.0/bin/generate_keys" --account combo-updates -p
"/Users/fun/Library/Caches/Combo/Sparkle/2.10.0/bin/sign_update" --account combo-updates "/path/to/Combo-version-arm64.dmg"
```

发布脚本接入时，`generate_appcast` 使用 `--maximum-deltas 0`，按各版本固定包地址配置 URL，不手工复制不匹配的签名。

## 恢复方法

新 Mac 下载并验证 Sparkle 官方工具，从独立备份取回 `.enc` 与密码。选择受保护的临时目录，密码在 OpenSSL 交互提示中输入，不写进命令、脚本或 shell 历史：

```sh
umask 077
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 \
  -in "/path/to/combo-updates-private-ed-key-2026-10-08.enc" \
  -out "/protected/temp/private-ed-key.txt"
"/path/to/Sparkle/bin/generate_keys" --account combo-updates \
  -f "/protected/temp/private-ed-key.txt"
"/path/to/Sparkle/bin/generate_keys" --account combo-updates -p
```

公钥与仓库 `public-ed-key.txt` 完全一致后删除临时明文。不要向已有不同密钥的账户直接导入；先核对账户与恢复目标。当前验证了加密/解密一致性，尚未在另一台 Mac 上执行导入演练。

## 已授权部署与验证结果

用户已授权仅提交七个文档/更新源文件、推送 `feature/update` 并启用 Pages。准备提交为 `21dedbb`（`docs: prepare Sparkle update feed and release guide`），已经推送。原有 `Combo.xcodeproj/project.pbxproj` 修改未纳入提交；私钥、加密备份和恢复密码不在仓库中。

GitHub Pages 已启用，来源为 `feature/update` 的 `/docs`，构建 API 返回 `built` 且无错误。合入 `main` 后可迁移来源，合并仍需另行授权。

首次外部读取检查发现：账号主页 `fanglinwei/fanglinwei.github.io` 绑定 `clam1993.com`（存在 `CNAME` 文件），Combo 项目继承该域名。原计划 HTTPS URL 当时返回 301，跳转到不可解析的 HTTP 地址。

备用地址已经匿名 HTTPS 验证通过，返回有效 RSS XML，与本地文件字节完全一致：

```text
https://raw.githubusercontent.com/fanglinwei/Combo/feature/update/docs/updates/appcast.xml
```

XML SHA-256：`bc471fcdd222263f7344a9f6a55833a938f7d4cc8c86f882c06737120b1b2bbe`。此项只验证元数据读取，不证明 App 安装更新已实现或通过测试。

用户随后明确授权解除账号主页的旧域名及必要 CNAME 配置。已通过 Pages API 将主页 `cname` 清空；GitHub 同时删除主页仓库的 `CNAME`，自动产生提交 `cda70f96b32b45fa98f572820ace42f37a4fefe4`（`Delete CNAME`）。该操作恢复账号下继承站点的默认 GitHub Pages 地址，没有改动网站内容或执行历史重写。

最终检查：Combo Pages `html_url` 为 `https://fanglinwei.github.io/Combo/`，`https_enforced = true`，来源保持 `feature/update` 的 `/docs`。直接读取原计划更新源时限制请求及跳转只能使用 HTTPS；返回有效 XML，内容与本地字节及上述 SHA-256 一致。

正式接入使用 Pages 固定地址，raw 地址仅作为已验证的诊断参考，不作为第二套自动回退源。以后将 Pages 来源迁移到 `main` 时保持 URL 不变。客户端本地接入与隔离安装测试进展见下文。


## 客户端本地接入与隔离测试（2026-10-08）

- 项目通过远端 Swift Package Manager 仓库 `https://github.com/sparkle-project/Sparkle.git` 接入 Sparkle。版本要求从 2.10.0 起，`Package.resolved` 当前锁定 2.10.0（revision `eef1a539a373c1f1a320624b1130fc5de7b2e100`）；正式地址、公钥、24 小时间隔、关闭自动下载安装和系统分析已写入 Info.plist。
- 一个应用生命周期内的更新器管理调度；关于页提供检查按钮与自动检查偏好，面板设置入口提供轻量提醒。Debug 更新器不启动。成功检查时间保存在本机，失败检查不会覆盖它。用户已确认在软件更新栏最后一行显示“上次检查时间”：手动/自动成功检查后刷新，失败保留旧值，从未成功检查时显示“尚未检查”。
- 已匿名读取线上 HTTPS appcast，Sparkle 能完成成功检查，空清单表示当前无可用更新。
- 官方 SPM 归档 SHA-256 为 `17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959`。远端仓库首次拉取曾停滞，临时使用本地声明验证；用户随后确认保留远端仓库依赖。现在常规工程已成功解析远端依赖并自动嵌入框架，临时本地声明已移除。
- 当前远端依赖的 Debug 与 Release arm64 构建通过，解析日志为 `build/sparkle-remote-resolve.log`，Release 日志为 `build/sparkle-release-build.log`。设置页中英文、深浅色、最小尺寸与大字号预览位于 `build/update-settings-previews/`。
- 当前远端依赖的完整 `verify.sh CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` 通过（退出码 0），包含更新状态持久化、面板交互、设置与引导、本地化、音频网络、签名和品牌资源。日志为 `build/sparkle-verify.log`。首轮面板关闭检查出现未定位的 nil 值失败；添加行号诊断后单独复测及完整复测均通过，未修改面板实现或放宽断言。
- `Tests/check-sparkle-install.py` 使用本机回环源、隔离 Bundle ID 和真实 Release Combo 副本。当前远端依赖构建的正向测试把 ad-hoc 构建 1 的副本替换为构建 2，随后验证嵌套签名；负向测试提供不匹配的 EdDSA 签名，验证 Sparkle 拒绝更新且构建 1 保留。工具使用既有 `combo-updates` 钥匙串账户，没有导出私钥。
- 上述安装测试验证下载、DMG 解压、签名校验和替换，不代表完成干净 Mac 上的首次 Gatekeeper 批准或 Combo 标准窗口中的自重启体验验收。正式 appcast 仍无更新条目，未发布测试包或 App Release。
- 用户既有 Xcode 签名与新编译配置保持原样。无证书的本地验证与 DMG 构建命令显式使用 Manual/ad-hoc；打包器允许官方 Sparkle 的通用二进制，继续要求 Combo 自身是 arm64，并从内向外签名和验证。

## 本地更新产物准备工具（2026-10-08）

维护者已明确确认首个支持更新的版本为 1.1.0，独立构建号为 101。当前源码仍为 1.0.0；正式版本修改与 GitFlow 分支准备尚未执行。

新增 `Releases/updates/prepare-update.py`，复用现有 DMG 打包器产物和官方 Sparkle 2.10.0 工具。只读核对当前线上清单与同标签 GitHub Release，检查包内版本、架构、公钥、更新源和嵌套签名，生成本地 appcast/说明/摘要。使用 `gh` 已有登录避免匿名 API 限流，任何非 404 错误均停止。脚本不创建密钥、不导出私钥、不修改生产清单、不执行 Git 或 GitHub 写操作。

版本与失败防护的 6 组标准库单元检查通过。用既有 Release 副本创建隔离的 1.1.0 / 101 DMG（未启动该副本），实际调用 generate_appcast 与 sign_update 验签通过；下载 URL、大小、版本、系统及 arm64 要求、说明 URL 均复核。DMG 字节不变。错误构建号 102 被拒绝且未产生候选。挂载目录独立于自动清理工作目录；卸载失败时保留挂载目录，避免递归清理仍挂载的卷。

测试目录 `build/update-preparation-fixture/` 全部属于本地验证，使用 `local-preparation-fixture-1.1.0` 标签地址和明确标记的测试说明，不是正式发布候选，禁止上传。正式 appcast 仍为空，未创建标签或 Release。脚本使用说明见发布清单第 6 节。
