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

正式接入使用 Pages 固定地址，raw 地址仅作为已验证的诊断参考，不作为第二套自动回退源。以后将 Pages 来源迁移到 `main` 时保持 URL 不变。客户端接入与实际 App 升级测试仍未完成。
