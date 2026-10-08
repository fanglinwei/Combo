# Combo 更新源

计划固定地址：`https://fanglinwei.github.io/Combo/updates/appcast.xml`。

2026-10-08 部署结果：Pages 已构建成功，但该地址因账号主页的旧 `clam1993.com` 绑定而重定向至不可解析的 HTTP 地址，当前不可作为客户端更新源。备用 `https://raw.githubusercontent.com/fanglinwei/Combo/feature/update/docs/updates/appcast.xml` 已验证返回正确 XML；最终托管方式待确认，见首次准备记录。

托管使用公开仓库 `fanglinwei/Combo` 的 GitHub Pages。当前工作分支是 `feature/update`，首次上线可在具体提交、推送授权后以此分支的 `/docs` 为来源；合入 `main` 后再将来源迁移到 `main`，公开 URL 保持不变。不要删除仍作为 Pages 来源的分支。`docs/.nojekyll` 使该目录以静态资源发布。

`appcast.xml` 已提交到远程仓库，当前只是初始骨架，没有版本条目。首个更新版本使用 Sparkle 官方 `generate_appcast` 生成经过验证的条目；不能以 GitHub Release 标签自动代替清单。

安装包位于 GitHub Releases，版本固定更新说明放在本目录的 `notes/`。发布时先上线安装包与说明，最后上线清单。

公钥可以公开；私钥、加密私钥备份及恢复密码绝不能放进此目录。`public-ed-key.txt` 已保存公钥；客户端接入时将其配置为 `SUPublicEDKey`。

签名工具必须指定钥匙串账户 `combo-updates`，不要使用默认的 `ed25519` 账户。准备记录与备份恢复说明见 [首次准备记录](../sparkle-setup-record.md)。

本次提交、推送与 Pages 启用已获得用户授权并执行；以后发布仍按项目 Git 规则获得对应操作授权。Pages 构建成功不等于公开更新地址可用，不能跳过 HTTPS 读取检查。

维护流程见 [接入与发布清单](../sparkle-release-checklist.md)。
