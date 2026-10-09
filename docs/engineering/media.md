# 媒体播放：当前实现、数据来源与验证边界

整理：2026-10-09。当前实现使用隔离 helper 读取系统注册媒体客户端；未采用方案只用于解释选型。

## 数据链路

[MediaPlayback.swift](../../Combo/Audio/MediaPlayback.swift) 启动系统 `/usr/bin/perl`，经 DynaLoader 加载打包的 `ComboMediaPlayback.dylib`；[MediaPlaybackHelper.m](../../Combo/Audio/MediaPlaybackHelper.m) 动态加载私有 MediaRemote 并流式输出 JSON。加载机制参考 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)，不是 Apple 公开 API 或跨版本兼容承诺。

| 数据 / 操作 | 当前行为 | 边界 |
| --- | --- | --- |
| 播放状态 | 枚举系统注册客户端并聚合；任一有效客户端播放时触发音柱 | 未注册客户端不可识别；每个客户端的默认播放器不等于全部子会话 |
| 当前曲目 | 标题、艺人、来源 App、可用封面 | 来源提供什么就展示什么，不补造数据 |
| 播放操作 | 上一首、播放/暂停、下一首，经 helper 发往本机播放源 | 不是 HomePod/Apple TV 接收端独立控制 |
| 故障 | `available` 与 `playing` 分开；读取失败、helper 缺失、超时保留不可用状态 | 不把不可用写成“已知暂停” |

helper 约每秒查询，单次客户端状态查询超时 2 秒；宿主每 5 秒检查回复，退出或失效后断开并按启用状态重新启动。JSON 按行解析，缓冲有大小上限；旧进程回调按实例隔离。锁屏/休眠停止检测，唤醒恢复。

相同来源的短时缺失元数据可保留约 5 秒；切歌按曲目身份避免沿用旧封面。暂停时可保留媒体卡，系统会话结束后清理。看门狗与元数据保留不是“最后一次 playing 永久有效”的承诺。

## 显示与隐私

底部显示顺序：系统静音/零音量 → 最近调整音量的约 2 秒提示 → 已确认播放且动效开启 → 普通音量点。固定四柱约 1.2 秒循环，系统减少动态效果时静态显示；具体规则见 [产品行为](../product/behavior.md#media-display) 与 [设置规格](../product/behavior.md#settings)。

不采集音频波形、不录音、不读取网页正文，动画帧不驱动媒体查询。当前方案不需要旧 Apple Events/浏览器扩展实施文档中的网站授权、native host 注册或 App Group 快照配置；这些流程不应作为当前用户操作要求。

已按 bundle ID 排除 FaceTime、微信、QQ、企业微信、腾讯会议、Teams、Zoom、Skype、Discord、Slack 等已知通讯来源及 Combo 自身。浏览器内通话和未知通讯应用仍需验证；名单排除不能保证理解所有媒体内容。普通通知音不等于注册媒体会话。

## 历史 API 比较与未采用方案

2026-09-22 的资料核查保留以下结论；它们用于解释选型，不作为待实现清单。本次未重新在线核查来源。

| 路径 | 已核查事实 | 当前取舍 |
| --- | --- | --- |
| `MPNowPlayingInfoCenter` | 发布调用应用自己的状态，不是任意应用的全局枚举 | 不用于检测其他来源。[Apple 文档](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter) |
| Music/Spotify Apple Events | 部分桌面播放器有 `player state`；授权按目标应用分别处理 | 没有作为当前通用检测路径；不能推及所有播放器。[Hammerspoon Spotify](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spotify/spotify.lua) |
| CoreAudio 输出活动 | `kAudioProcessPropertyIsRunningOutput` 描述 I/O 与输出流 | 通知、会议、游戏等也可活跃，不能替代严格播放状态。[Apple 声明](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunningoutput) |
| 播放器辅助功能 UI | 菜单“播放/暂停”可能只表达操作，缓冲与后台窗口需另验收 | 未作为当前正式检测路径；不要增加无用途的授权流程 |
| Safari/Chrome 扩展 | 可观察获准网页的媒体元素，经原生消息桥接 | 当前没有交付这套扩展；不保留旧注册、通信和发布步骤作为首版要求。[Safari 原生消息](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)、[Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) |

## 验证入口与待验收

`./verify.sh` 中的 `Tests/Audio/MediaPlaybackHelperCheck.m` 覆盖多客户端聚合、暂停/停止/中断、通讯来源排除及 JSON 布尔；`Tests/Audio/MediaPlaybackTests.swift` 覆盖解码、helper 缺失与元数据/显示规则。自动检查不等于播放器硬件或系统版本验收，本次文档整理未重跑应用测试。

实机验收仍需覆盖目标播放器版本、浏览器媒体与通话、多个客户端和子会话、暂停/缓冲/结束、来源退出、helper 失效重连、睡眠唤醒、当前签名与 macOS 26。没有实测 CPU/能耗数字，不声明私有加载机制在 Developer ID、公证或沙盒下必定可用。
