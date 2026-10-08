# Combo 更新源

已上线固定地址：`https://fanglinwei.github.io/Combo/updates/appcast.xml`。

2026-10-08 部署结果：Pages 已构建成功。首次检查发现账号主页旧域名继承导致 HTTP 重定向；用户额外授权解除旧绑定后，固定 Pages HTTPS 地址已验证返回与本地完全一致的 XML。接入使用此固定地址，raw 仓库地址仅作诊断参考，见首次准备记录。

托管使用公开仓库 `fanglinwei/Combo` 的 GitHub Pages，当前来源为 `feature/update` 分支的 `/docs`；合入 `main` 后再将来源迁移到 `main`，公开 URL 保持不变。不要删除仍作为 Pages 来源的分支。`docs/.nojekyll` 使该目录以静态资源发布。

`appcast.xml` 已提交到远程仓库，当前只是初始骨架，没有版本条目。首个更新版本使用 Sparkle 官方 `generate_appcast` 生成经过验证的条目；不能以 GitHub Release 标签自动代替清单。

安装包位于 GitHub Releases，版本固定更新说明放在本目录的 `notes/`。发布时先上线安装包与说明，最后上线清单。

公钥可以公开；私钥、加密私钥备份及恢复密码绝不能放进此目录。`public-ed-key.txt` 已保存公钥；客户端接入时将其配置为 `SUPublicEDKey`。

签名工具必须指定钥匙串账户 `combo-updates`，不要使用默认的 `ed25519` 账户。准备记录与备份恢复说明见 [首次准备记录](../sparkle-setup-record.md)。

本次提交、推送与 Pages 启用已获得用户授权并执行；以后发布仍按项目 Git 规则获得对应操作授权。Pages 构建成功不等于公开更新地址可用，不能跳过 HTTPS 读取检查。

维护流程见 [接入与发布清单](../sparkle-release-checklist.md)。
