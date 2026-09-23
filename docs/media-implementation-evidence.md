# Combo 首版：媒体播放检测与权限证据

核查日期：2026-09-22。产品目标已确定为独立安装包、macOS 26 及以上、MacBook。本文件记录技术事实与建议，媒体支持应用清单仍需产品确认；没有执行用户媒体查询或触发授权。

## 结论

固定循环音柱不需要采集音频，但仍需要可信的播放状态来源。本次未找到可承诺覆盖所有应用的公开全局 Now Playing 读取 API。不能把 `MPNowPlayingInfoCenter.default().playbackState` 当成其他应用状态，也不能把 Core Audio 输出流运行当成媒体正在播放。

后续需求确认：首版需要浏览器视频及更多播放器，用户不接受仅 Music/Spotify，也不接受以音频活动替代严格播放状态；已同意分别适配。用户进一步指定原生播放器为网易云音乐、QQ 音乐，因此下文 Music/Spotify Apple Events 仅保留为已调研的对照，不是首版应用清单；它们的公开脚本能力不能推及网易云/QQ。两者当前存在实现阻断，详见末节。

对明确支持的播放器（例如 Music、Spotify 桌面端）查询 Apple Events `player state` 是可维护的局部实现；首次启用时请求对应应用的“自动化”权限。没有授权、目标未安装或不支持时，保留音量圆点。

## 技术事实矩阵

| 路径 | 能取得什么 | macOS 26 与版本证据 | 权限及限制 | 首版判断 |
|---|---|---|---|---|
| `MPNowPlayingInfoCenter` | 调用应用自己发布的媒体信息与播放状态 | 26 SDK 注释明确 current application；macOS API 起点为 10.12.2 | 不会因取得媒体库权限而变成全局读取 API | 不用于检测其他应用 |
| Music Apple Events | Music 的 `player state` | 本机 Music 脚本字典存在只读 `pPlS`，支持 playing/paused/stopped 等枚举；需 macOS 26 实机签名包验证 | Automation 用户授权；Hardened Runtime Apple Events entitlement；隐私说明 | 可作为明确支持源 |
| Spotify Apple Events | Spotify 桌面客户端播放状态 | Hammerspoon 上游实现直接读取该属性；实际版本需再验证，不能推及网页播放器 | 同上，授权按目标应用分别处理 | 可作为明确支持源 |
| 私有 `MediaRemote` | 系统 Now Playing 信息，具体可见范围取决于系统实现 | mediaremote-adapter 上游报告 macOS 15.4 起普通应用直接加载不可用；其替代方案借系统 Perl 身份加载私有 framework | 没有可依赖的普通公开授权流程；独立分发不会解决私有 API 的稳定性问题 | 不作为首版默认技术基础，不依赖绕过系统限制 |
| Core Audio `kAudioProcessPropertyIsRunningOutput` | 进程正在运行音频 I/O 且存在活动输出流 | 已检查 macOS 26 SDK 头文件 | 不采样音频；不能由属性语义推导通知声/通话/游戏/媒体类别，也不能推导暂停状态 | 不等价替代媒体播放检测 |

Apple 的 [MPNowPlayingInfoCenter 文档](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter) 与本机 macOS 26 SDK 的 `MediaPlayer.framework/Headers/MPNowPlayingInfoCenter.h` 一致。当前 `xcrun --show-sdk-path` 默认 SDK 是 27.0；本次特意另查 `/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk`，未把默认 SDK 当成 26 验证。

Core Audio 的 [IsRunningOutput 声明](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunningoutput) 对应 26 SDK 的 `CoreAudio.framework/Headers/AudioHardware.h` 第 1971–1974 行注释。它描述运行 I/O 与输出流，不描述媒体语义。这里的误判风险是基于接口定义的工程推论，不是已经完成的兼容性测试。

只读 `AudioObjectGetPropertyData` 查询进程及其输出运行属性，不创建音频 tap、不获取 PCM 数据；预期不需要音频采集授权。但已查官方页面/头文件没有给出逐一 macOS 26.x 与分发配置的 TCC 保证，本次也没有运行签名测试包。因此，文档应写“预期无录音权限，签名包实测为准”，不能写已验证免授权。

不要误用 [kAudioHardwarePropertyProcessIsAudible](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessisaudible)：它属于 AudioSystemObject 属性，26 SDK 注释描述本进程音频是否将被听见，不是每个 `AudioProcess` 的实时电平或全局媒体播放枚举。不能用名字中的 Audible 推导它能区分音乐、通知与会议。

若选择音频活动方案，应在产品中明确其能力：通知、通话、游戏也可能触发；暂停后仍维持活动音频流的应用可能继续显示；无声或静音视频不保证触发。按 bundle ID 排除应用可以减少误判，但无法识别同一浏览器中的网页视频与会议，不能包装成全局严格媒体检测。

Music 证据为 Apple 随系统交付的 `/System/Applications/Music.app/Contents/Resources/com.apple.Music.sdef` 第 250 行 `player state`；Spotify 证据为 [Hammerspoon 自身实现](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spotify/spotify.lua)。动态分发通知可以作为以后减少查询的优化，但不能把未经目标版本验证的通知名当成稳定公开协议。

MediaRemote 变化来自 [mediaremote-adapter 作者说明](https://github.com/ungive/mediaremote-adapter)。这是项目作者对其实现与兼容性的声明，不是 Apple 对 macOS 26 的保证；本次未运行其 helper，也未验证其声称的全版本覆盖。

## 自动化权限实施要求

- `Info.plist` 写入 `NSAppleEventsUsageDescription`，建议内容：“用于读取你选择的音乐应用的播放状态，在菜单栏显示播放动效。Combo 不录制音频。”系统弹窗可能仍以“控制”目标应用描述授权，产品应解释实际只读用途，不能自称系统提供只读权限。
- 独立签名包启用 Hardened Runtime 时，为跨团队播放器配置 `com.apple.security.automation.apple-events`。它允许请求用户授权，不是自动获得访问权。[Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)、[隐私说明键](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
- 分别呈现每个目标应用的未授权、已授权、被拒绝、未安装状态；用户主动点击启用该应用后才触发首次请求。被拒绝后停止查询该目标，不循环请求。
- 先确认目标应用正在运行再查询，避免只为展示动效而启动播放器。读取应有超时、取消及退避，不在主线程阻塞。可先用 1 秒查询作为试验参数，最终以功耗和响应验收确定。
- 仅获取播放枚举，不读歌名、播放历史或媒体库；不请求麦克风、屏幕录制、系统音频录制、辅助功能或 Apple Music 媒体库访问权限来完成该功能。
- 若未来启用 App Sandbox，Automation entitlement 与用户授权仍不等于沙箱放行；还需要目标的 `scripting-targets` 或相应例外配置，不能直接沿用非沙箱判断。[Apple 沙箱脚本权限](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)

## 最小状态约定与无权限回退

数据层必须区分 `playing`、`notPlaying`、`unavailable(reason)`。未授权、超时、不支持均是 unavailable，不能伪装成已知暂停。UI 可以统一回退音量圆点，但设置面板应说明覆盖范围或不可用原因。

若支持多个播放器：任意已授权、受支持且有效的来源报告 playing 时显示固定音柱；不存在有效 playing 时显示圆点。目标退出立即清除其缓存 playing；睡眠、会话失活时停查询和动画，唤醒后重新读。快进/倒带等枚举如何映射需在具体适配器中明确，不能默认字符串非空就是 playing。

视觉优先级保持首版设计：系统静音 → 音量调整后的约 2 秒提示 → 已确认播放动效 → 音量圆点；减少动态效果时静态高低音柱。动画只由 UI 时钟驱动，不能每一帧查询播放器。

## 开发前必须通过的验证

1. 使用独立签名、Hardened Runtime 的实际应用验证首次允许/拒绝/撤销授权，避免把脚本编辑器或终端已有权限误当成产品权限。
2. 对支持播放器测试播放、暂停、退出、多个播放器同时运行、进程无响应及睡眠唤醒。禁止为查询自动启动播放器。
3. 明确浏览器网页视频、第三方本地播放器、会议通话是否不支持；未经验证不得在 UI 宣称“所有媒体”。
4. 验证纯固定动效路径没有麦克风、录屏、系统音频录制请求；记录静态和播放时的 CPU/能耗，不持续保存媒体元数据。

## 严格状态方案补充：Safari 与 Chrome 扩展

### 已核实的通信事实

Safari Web Extension 包含网页脚本、原生 app extension、containing app 三部分。content script 先向扩展后台发消息；只有后台或扩展页面能用 `browser.runtime.sendNativeMessage`，不能从 content script 直接调用。`nativeMessaging` 必须在 manifest 声明。Safari 将消息送至所属原生扩展，忽略传入的 application ID；在 `SafariWebExtensionHandler.beginRequest(with:)` 处理，不能误认为它直接送达正在运行的 Combo app。原生扩展与 containing app 可通过共同 App Group 共享数据。[Apple 原生消息文档](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)

Apple 允许以 Developer ID 签名、公证后在 Mac App Store 外分发 Safari 扩展的 containing app；发布包不要求用户开启允许未签名扩展。[Apple 分发文档](https://developer.apple.com/documentation/safariservices/distributing-your-safari-web-extension)

Chrome MV3 content script 先发给 service worker，再经 `runtime.connectNative` 连接独立 native host。manifest 需要 `nativeMessaging`。主机注册 JSON 的 `allowed_origins` 必须是指定扩展 ID，不能用通配符；macOS `path` 要用 helper 绝对路径。用户级默认注册位置为 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/<host-name>.json`。协议为原生字节序 32 位长度加 UTF-8 JSON；长连接适合持续事件，`sendNativeMessage` 每条消息可能启动新进程。content script 无法直接调用 native API。[Chrome 当前扩展原生消息文档](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)

content scripts 运行在隔离环境但可以读取 DOM；自动注入受 `matches` 与网站访问授权约束。`all_frames` 表示对匹配的所有 frame 注入，不是越过跨域 frame 权限。相关 `about:blank`、`blob:` 等 frame 需要额外匹配选项并分别验证 Safari/Chrome 支持；只访问顶层 document 不能保证发现嵌入播放器。[Chrome content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)

### 最小实现建议，不是已完成实测

沿用同一套 DOM 检测脚本，原生桥接分别实现；不使用音频采集、MediaRemote 或浏览器远程调试端口。

```text
网页 audio/video
  → content script（观察媒体状态）
  → 扩展后台（按 tab/frame/document 聚合并验证来源）
    → Safari：sendNativeMessage → 原生 Web Extension Handler
    → Chrome：connectNative → 签名的 Combo native host helper
  → App Group 中分来源的原子状态快照
  → Combo 读取状态 → 现有显示状态归约与固定动画
```

为避免新增后台服务，原生扩展和同团队签名 helper 各自更新 App Group 中自己的小型快照，Combo 在启用浏览器适配期间最多约每秒读取一次。这个轮询值是性能验证起点；只有延迟/功耗不达标时再换事件通知或 XPC。所有相关 target 必须正确配置并验证 App Group entitlement/容器 URL；不能硬编码其他应用沙箱路径。Safari 用 App Group 共享数据有官方依据；将同组 helper 用于 Chrome 快照是本项目实现建议，须签名包集成验证。[Apple 共享数据示例](https://developer.apple.com/videos/play/wwdc2020/10665/)

快照只含协议版本、受控来源 ID、会话 ID、递增序号、播放枚举与更新时间；不保存 URL、标题、歌名或网页正文。多 profile/session 分开写入并在读取端聚合，避免两个浏览器互相覆盖。应用重启/扩展断开/快照过期应置 unavailable，不能把上次 playing 永久留住。过期阈值结合浏览器后台节流实测，失联不等于已知暂停。

后台须依据浏览器提供的 sender 身份确认 tab/frame/document，不能信任消息内自报身份；只接受约定字段、枚举和小消息长度，拒绝路径、脚本、URL 打开命令。native host 再检查调用 origin 和协议，stdout 只输出规范协议消息。App Group 文件采用原子写入，不将网页数据用作文件名。Chrome 只在用户主动启用集成时注册当前用户 native host；应用移动后修复绝对路径，卸载集成时删除本应用的注册文件，不写系统级目录。

### HTMLMediaElement 状态模型

| 观察项 | 技术含义 | 建议映射 |
|---|---|---|
| `play` | paused 从 true 变 false，可能仍在等数据 | starting，不立即认定正在播放 |
| `playing` | 开始或恢复播放 | playing |
| `pause` | 已进入暂停状态 | paused |
| `ended` | 播放到末尾或无后续数据而结束 | ended |
| `waiting` | 因暂时缺少数据停止播放 | buffering，暂停播放动画 |
| `emptied` / `error` | 媒体清空或加载错误 | notPlaying / unavailable，分别保留原因 |

这些事件多数不冒泡；直接绑定已发现的媒体元素，并观察后续插入/移除与 SPA 替换。首次注入时读取 `paused`、`ended`、`readyState`、`seeking` 等当前状态，避免遗漏扩展开启前已播放的内容；初始快照无法确认时等待后续状态事件，不以非零音量推导播放。`suspend` 只表示停止加载，`stalled` 只表示取数据受阻，不应直接等于暂停；`timeupdate` 也可能来自跳转，不独自判定 playing。[MDN 媒体接口与事件](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement)、[playing](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/playing_event)、[waiting](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/waiting_event)

静音视频仍可处于 playing，应触发媒体状态；只有系统输出静音才走产品既定的静音视觉优先级。多元素、多标签页按“任意已确认 playing”聚合；单个标签暂停不能覆盖另一个标签仍在播放。导航、frame 卸载、元素移除、标签关闭、浏览器退出都清除对应活动状态。

### 网站权限与支持边界

- 用户需要安装并启用浏览器扩展，另行授予网站访问权限；这不是 macOS 麦克风/录屏权限。UI 应解释系统可能显示“读取和更改网页数据”，实际只观察媒体元素状态。
- 第一版可以让用户选择指定网站授权；若承诺任意普通网页，则需相应广泛 HTTP/HTTPS 网站访问范围。`activeTab` 是临时用户操作授权，不能替代后台长期观察所有标签页。
- 必须验证后台标签、跨域 frame、动态插入元素、Picture in Picture、全屏、倍速、循环播放、播放中启用扩展、服务工作线程重启和桥接重连。后台线程重启需要重建当前快照，不仅重放旧事件。
- 未授权 iframe、浏览器内部/受限页面、未允许的无痕窗口不在覆盖范围。无权页面是 unavailable，不宣称已暂停。
- 纯 Web Audio 音频图、没有可观察媒体元素的自绘播放器、closed shadow DOM 等不保证覆盖；开放 shadow root 可单独遍历，不能把普通 querySelector 当成完整全页扫描。Web Audio 可直接由音频节点产生声音，因此 DOM 媒体事件不是它的通用状态接口。[MDN Web Audio](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
- `navigator.mediaSession.playbackState` 是页面应用可设置的状态，默认可为 none；不是读取所有标签页或整个 macOS 的 API，也不保证网站维护它。只可在专门验证的网站适配中作为补充，不是全局探针。[MDN MediaSession playbackState](https://developer.mozilla.org/en-US/docs/Web/API/MediaSession/playbackState)
- HTML video/audio 也可能承载 WebRTC 通话或广告。若产品要求排除通话或广告，还需站点/媒体类型专门规则；“读取媒体元素的严格播放状态”不等于“自动理解内容是音乐或电影”。

### 发布阻断项

必须在 macOS 26 的 Developer ID 公证安装包中验证 Safari 扩展发现/启用、App Group 读写、Chrome 正式扩展 ID 与主机注册、首次网页授权和撤销、应用移动及升级。源代码可加载或开发者模式可运行不能替代发布验收。浏览器扩展断开时恢复音量圆点并在设置提示连接状态，不改用音频活动或私有 API 偷偷兜底。

## 网易云音乐与 QQ 音乐：当前可行性阻断

此节对应用户明确选择的原生播放器，不能用 Apple Music、Spotify 或网页版擅自替代。

### 本机只读检查

2026-09-22 检查应用包文件，未启动应用、未发 Apple Events、未读取实时播放状态、未请求权限：

| 应用 | 本机证据 | 能得出的结论 |
|---|---|---|
| 网易云音乐 | `/Applications/NeteaseMusic.app`，版本 3.1.12，bundle ID `com.netease.163music`；Info.plist 未声明 `NSAppleScriptEnabled` 或 `OSAScriptingDefinition`；包内未找到 `.sdef`、`.scriptSuite`、`.scriptTerminology` | 本安装版本没有可据以实现公开 `player state` 查询的脚本字典；不能照搬 Music/Spotify 方案。不能仅凭缺少字典绝对断言所有未公开 Apple Events 都不存在 |
| QQ 音乐 | `/Applications` 与 `~/Applications` 顶层未发现 QQMusic/QQ音乐 app；`QQ.app` 是另一产品，不能当成 QQ 音乐 | 无本机版本、脚本字典或 AX UI 实测证据 |

### 上游实现证据

- [feishutune 作者说明](https://github.com/Durden-T/feishutune) 明确其 QQ 音乐适配不走 AppleScript，而用 `media-control` 读取系统 Now Playing。这说明它的成功案例不能证明存在普通公开播放器接口。
- [lyrimuse 的播放数据源文档](https://github.com/Yudaotor/lyrimuse/blob/main/docs/features/02-playback-source.md) 将 QQ 音乐、网易云音乐都列为 `media-control` / MediaRemote 来源，并说明其包包含 Perl adapter。该路线仍受本文排除的私有框架/身份适配限制；独立安装包不使其成为公开 API。
- [CloudMusicFocus 作者说明](https://github.com/eruimisshy/CloudMusicFocus) 给出网易云 3.x 的 AX 菜单路线：读取“控制”菜单中的“暂停/播放”项；作者称其在 macOS 26 验证。它还说明需要 `AXManualAccessibility`、`AXEnhancedUserInterface` 属性才读到未展开菜单。这些不是本次已确认的标准公开 AX 属性，不能把项目成功宣称为仅公开稳定接口的保证。项目另有音频 tap 功能，Combo 不应引入该部分。
- [MyLyrics 作者说明](https://github.com/ZiweiZhou99/MyLyrics) 使用辅助功能读取网易云界面进度，并要求主窗口保持打开；也使用本地数据库与估算回退。因此它不是可直接保证隐藏窗口、暂停、缓冲下严格播放状态的方案。

本次未找到两家厂商正式文档公开保证“读取本机 macOS 客户端实时 playing/paused”的 SDK/API。曲库、歌词、历史记录或账号 Web API 不等于本机即时播放状态。未找到是本次调研边界，不是证明绝对不存在。

### 可验证的候选与不能承诺的部分

Apple 提供公开的 [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue) 和 [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)。前者读目标公开的辅助功能属性，后者检查或引导辅助功能授权；属性缺失、UI 不支持、进程不可响应均有错误返回。

最新决定：用户已接受辅助功能权限，并同意先验证网易云/QQ 播放暂停可读性，再决定正式支持。目前两者仍不能列为已确认可交付。适配使用 Swift 直接调用 `AXUIElement` 公开 API；仅在用户主动点击启用/授权时用 `AXIsProcessTrustedWithOptions` 的 prompt 选项引导授权，普通状态刷新只检查权限。无需通过 System Events AppleScript，因此不应同时请求 Automation 权限，也不应为当前首版原生播放器保留无用途的 Apple Events entitlement/说明键。

逐版本验证播放器后台、最小化、关闭主窗口、迷你播放器、播放/暂停/缓冲、语言切换与更新。菜单写着“暂停”也可能是“用户已发起播放但仍缓冲”，因此按钮反义推断不能单独保证严格播放状态。

只读 AX 方案不应点击菜单、激活应用或改变播放来探测，不应申请录音权限；也不能静默启用未文档属性。只读意图不意味着系统提供仅限读取的辅助功能权限，授权说明必须真实。

如果 AX 公开属性无法提供可靠状态，现有条件下该原生播放器适配应标为未解决，而不是默认加私有 MediaRemote、缓存猜测、音频活动替代。网页版通过 Safari/Chrome 扩展读取媒体元素可另行验证，但属于改变用户使用场景，需明确选择，不能宣称已完成原生客户端适配。
