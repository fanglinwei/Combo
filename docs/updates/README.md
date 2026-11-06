# Combo 更新源目录

本目录保存 GitHub Pages 使用的静态更新资源，维护流程与签名恢复见 [更新发布维护](../release/updates.md)。

固定客户端地址为 [HTTPS appcast](https://fanglinwei.github.io/Combo/updates/appcast.xml)。本地清单已含 `1.1.0 / 101`、`1.2.0 / 102`；线上内容和 Pages 来源在发布时重新核验，不以本地文件或构建成功代替匿名 HTTPS 读取。

- `appcast.xml`：客户端订阅源，最后发布；安装包位于 GitHub Releases。
- `notes/Combo-版本-arm64.html`：版本固定说明，先于清单上线；现有绝对 URL 不随文档整理迁移。
- `public-ed-key.txt`：公开 EdDSA 公钥，被客户端配置及准备/验证工具使用；私钥、加密备份和恢复密码不放进此目录。
- 上级 `docs/.nojekyll`：保留静态发布配置。

保持更新源、公钥与既有说明路径稳定。发布包先上线，清单最后上线；已公开包不可覆盖，后续 build 必须递增。
