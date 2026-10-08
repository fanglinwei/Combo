# Combo · Sparkle 首次准备记录

日期：2026-10-08。本记录不含私钥或恢复密码。

## 已完成

- GitHub API 确认 `fanglinwei/Combo` 为公开仓库，当前账户有 admin/push 权限，默认分支为 `main`，尚未启用 Pages。
- 固定更新源准备为 `https://fanglinwei.github.io/Combo/updates/appcast.xml`，尚未部署。
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

## 待授权上线

当前分支 `feature/update`。本次未暂存、提交、推送、创建分支或配置 Pages。原有 `Combo.xcodeproj/project.pbxproj` 修改不属于本次发布文件。

首次上线可将本次文档和更新源精确路径提交、推送至当前分支，再启用 Pages 来源 `feature/update` 的 `/docs`；合入 `main` 后迁移来源，合并另需授权。启用 Pages 会公开 `/docs` 静态内容，仓库本身当前已公开。

上线后检查 HTTPS 返回真实 XML；地址可用不代表客户端已接入 Sparkle，也不会让旧版自动升级。
