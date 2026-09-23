# Combo 首版：网络状态与权限技术证据

核查日期：2026-09-22。适用目标：macOS 26 及以上、MacBook、独立安装包。本文为实施依据，不代表已完成实机兼容性验证；未扫描用户网络、未修改系统设置。

## 1. 最小技术方案

使用 `Network.NWPathMonitor` 监听本应用的默认路径变化；使用 `SystemConfiguration.SCDynamicStore` 辅助解析系统默认接口；使用 `CoreWLAN.CWWiFiClient` 取得 Wi-Fi 接口与 RSSI。三者只负责各自可证明的信息，不能用一个“已联网”布尔值代替路径、介质和信号。用户已确认首版只展示连接与路由，不做外部探测、不读取 SSID/BSSID、不申请定位。

建议状态模型：`pathAvailability`（available/unavailable/pending）、`transport`（wifi/ethernet/other/ambiguous/unknown）、可空 `rssi`。字段均保留采样时间；连接切换后立即清除旧接口的信号值。

## 2. 主要连接不能用接口列表猜

Apple 将 `usesInterfaceType` 定义为路径中的连接“可能通过某种接口发送流量”；`availableInterfaces` 是按偏好排序的可用接口列表。因此，列表包含 Ethernet 不等于 Ethernet 当前承载全部流量，取第一个元素也不是所有 VPN、双栈和多路径情形下的严格证明。[NWPath](https://developer.apple.com/documentation/network/nwpath)

建议规则：

1. `NWPathMonitor` 无可用路径时，显示无连接；`requiresConnection` 表达等待连接，不直接断言互联网故障。
2. 通过 `SCDynamicStoreKeyCreateNetworkGlobalEntity` 创建 State 域 IPv4、IPv6 全局键，读取 `kSCDynamicStorePropNetPrimaryInterface`；使用 `SCDynamicStoreSetNotificationKeys` 与回调监听变化。
3. 将返回的接口名与实际枚举的接口/服务类型映射。不得硬编码 `en0 = Wi-Fi`；不存在或无法映射时返回 unknown。
4. IPv4、IPv6 都有值且指向同一物理介质时，显示该介质；只有一种协议有效时用其结果；二者冲突则标为多路径/不确定，不武断优先 IPv4 或有线。
5. VPN、隧道、代理、多路径可能使“全局主接口”和特定请求实际路径不同。隧道接口不能直接映射为以太网，也不能看到某个 `utun` 就断定所有流量走 VPN。证据不足时中央统一显示短横线 `—`，面板说明“连接类型暂不可确定”，仍保留电量与音量显示。

这是对“主要连接”的保守工程定义，不是全机所有进程流量的观测。若产品要求精确到某个目标，只能以连接该目标时的实际路径为依据；该结果也不代表所有互联网目的地。

参考：[PrimaryInterface 常量](https://developer.apple.com/documentation/systemconfiguration/kscdynamicstorepropnetprimaryinterface-swift.var)、[全局网络键](https://developer.apple.com/documentation/systemconfiguration/scdynamicstorekeycreatenetworkglobalentity(_:_:_:))。Apple 也明确要求不要硬编码 BSD 接口名。[TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## 3. Wi-Fi RSSI 与网络名的权限不同

| 数据/操作 | API | 权限和回退 |
|---|---|---|
| 路径是否可用、接口类型 | NWPathMonitor | 不主动发起本地设备访问；不为此请求定位、蓝牙或本地网络 |
| RSSI | CWInterface.rssiValue() | 官方文档未声明定位前提；值 0 表示错误或未参与网络，不是满格。首版不请求定位，按 API 能力尝试；失败则显示信号未知 |
| SSID/BSSID（后续参考，首版不读取） | CWInterface.ssid()/bssid() | Sonoma 起 SSID 明确要求定位服务开启并授权；不能把 nil 当作断网 |
| Wi-Fi 扫描、连接和修改设置 | 不属于首版必要能力 | 不调用，用户通过系统设置管理网络 |

CoreWLAN 应从 `CWWiFiClient` 获得接口，不自行实例化底层接口对象。[CWInterface](https://developer.apple.com/documentation/corewlan/cwinterface)、[RSSI 语义](https://developer.apple.com/documentation/corewlan/cwinterface/rssivalue())、[Apple DTS 对 Sonoma SSID 权限变化的说明](https://developer.apple.com/forums/thread/732431)

默认 `xcrun` 指向 macOS **27.0** SDK，但本机同时存在 `MacOSX26.sdk`。已显式读取 `/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk/System/Library/Frameworks/CoreWLAN.framework/Headers/CWInterface.h`，并与默认 SDK 核对：SSID/BSSID 条目声明定位要求，RSSI 条目没有此注记。此证据不能替代 macOS 26 签名 App 的实测，也不能据此承诺未来系统行为。RSSI 无效时保留固定 Wi-Fi 轮廓并显示“信号强度暂不可用”，不能为了补齐层数默认满格。

以下仅为后续版本参考，不是首版设置或权限流程；首版不包含任何网络名开关或位置授权说明键。若后续加入网络名：用户打开“显示 Wi-Fi 名称”时说明用途，再在前台申请 Core Location 授权。仅请求授权、读取 SSID，不启动持续位置更新，不保存坐标。配置 macOS 的 `NSLocationUsageDescription`；若采用 `requestWhenInUseAuthorization`，同时提供其文档要求的 `NSLocationWhenInUseUsageDescription`。文案建议：“用于显示当前 Wi-Fi 网络名称；Combo 不记录或上传你的地理位置。”若启用 App Sandbox，另配置 `com.apple.security.personal-information.location`。独立分发本身不等于已经选择了是否沙盒化。

Apple 的位置 API 文档存在跨平台说明差异：macOS 上 When In Use 与 Always 功能等价，但无需为了本功能索要持续位置更新。以目标 macOS 26、正式签名 `.app` 的首次授权、拒绝、撤销测试为准。[位置授权](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)、[requestWhenInUseAuthorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())

## 4. 可用路径不是互联网检测

`NWPath.status == .satisfied` 只表示路径可用于连接，不能证明 DNS、登录门户、远端服务器或整个互联网正常。用户已确认首版不发送任何外部探测请求，UI 使用“网络已连接”，不要使用“互联网正常”。`!` 至少覆盖明确无可用路径；“Wi-Fi 已连接但互联网不通”只有完成探测后才能给出有限判断。

首版不实现以下方案，仅保留后续参考。若另行加入主动检测：使用 `URLSession` 请求产品自有、固定的 HTTPS 小响应端点；声明请求用途；限制频率和超时；网络切换后去抖，休眠停止；失败显示“网络检测未通过”而不是断言全网不可用。不要擅自复用 Apple 登录门户检查地址，不发送 SSID/BSSID、设备名或稳定设备标识。

## 5. 互联网、沙盒与本地网络权限

| 能力 | 需要什么 |
|---|---|
| 独立分发、非沙盒应用访问普通公网 HTTPS | 一般没有“互联网访问”TCC 弹窗；仍受系统网络策略影响 |
| 沙盒应用发起公网连接 | `com.apple.security.network.client` 签名 entitlement；这不是用户权限弹窗 |
| 访问局域网设备、Bonjour 发现、`.local` 解析 | macOS 15 起适用本地网络隐私；macOS 26 同样需设计授权流程 |
| 默认路径监听、读取本地网络配置 | 不是主动访问本地设备，无须为首版主动触发本地网络授权 |

主动请求网关、扫描同网段、发现手机均可能触发本地网络权限，因此不纳入首版网络状态采集。将来关联手机功能启用时才配置 `NSLocalNetworkUsageDescription`，并按具体 Bonjour 服务配置 `NSBonjourServices`。普通非 `.local` DNS 的系统解析，以及系统配置的局域网 DNS/代理，有 Apple 文档列明的豁免；不能泛化为“所有走 Wi-Fi 的流量都需要本地网络授权”。[TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)

## 6. 开发验证门槛

- 在正式签名 GUI App 中测试；终端子进程的隐私行为可能不同，不用命令行成功替代 App 验收。
- 在未授予定位的正式签名 App 中记录 RSSI 可用性；确认首版不调用 SSID/BSSID、不触发位置请求。RSSI 不可用不能阻断电量、音量或一般连接状态。
- Wi-Fi 单连接、Ethernet 单连接、双连接改变优先级、仅 IPv6、双栈不同路由、全隧道及分流 VPN。
- 睡眠/唤醒、拔插扩展坞、Wi-Fi 关闭与重连时不显示旧接口数据。
- 首次启动不应弹出本地网络权限；主动公网检测若未来启用，不能意外访问 `.local` 或局域网地址。
- 先验证事件订阅；如 RSSI 事件不足，再仅在 Wi-Fi 相关状态下低频刷新，不用高频定时器反复解析系统命令输出。
