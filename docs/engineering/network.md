# 网络与 Wi-Fi：实现、权限及验证边界

整理：2026-10-09。路径 API 的历史核查为 2026-09-22；Wi-Fi 面板历史接入记录为 2026-09-24。当前包含扫描、SSID 和普通网络连接。

## 默认路径与菜单栏图形

[NetworkStatus.swift](../../Combo/Network/NetworkStatus.swift) 使用 `NWPathMonitor` 判断默认路径可用性，使用 `SCDynamicStore` 监听 IPv4/IPv6 全局主接口及接口配置，按 `SCNetworkInterface` 的类型映射 Wi-Fi/以太网。CoreWLAN 电源与链路事件触发刷新。

| 读取结果 | 表现 |
| --- | --- |
| 无可用路径，Wi-Fi 关闭 | Wi-Fi 划线图形 |
| 无可用路径，Wi-Fi 未明确关闭 | 无可用路径 / 异常图形 |
| 路径等待连接 | 等待连接 / 短横线 |
| 主接口可确认是 Wi-Fi / 以太网 | 对应介质；有线不显示网口图标 |
| 双栈介质冲突、隧道、无法映射或没有证据 | 连接类型不确定 / 短横线 |

不硬编码 `en0 = Wi-Fi`，不以可用接口数组中出现 Ethernet 就断言全部流量走有线。IPv4/IPv6 一致才合并，单侧有效用该侧，冲突保留不确定。VPN/代理/分流可能令全局主接口与特定请求路径不同；这不是全机流量观测。

`NWPath.status == .satisfied` 只表示路径可用于连接。Combo 没有外部互联网探测，不能据此宣称 DNS、登录门户或远端服务正常。菜单栏无线图形表示介质，面板列表才展示 RSSI 信号。

## Wi-Fi 面板

[WiFiControl.swift](../../Combo/Network/WiFiControl.swift) 使用 CoreWLAN 读取电源、当前 SSID/BSSID/RSSI、已知网络和安全类型，并扫描及关联普通网络。

- 名称与扫描按需使用定位授权；权限不可用时保留电池、声音及一般路径状态。
- 打开面板或手动刷新时扫描；面板活跃期间每 10 秒刷新连接状态，不把每次状态刷新都变成扫描。
- 同名不同安全类型分开；同组优先保留当前 BSSID，否则保留较强信号。名称排序，不把扫描可见当成连接成功。
- RSSI 为 0 或非负值视为未知，不画满格；有效负值按 `-60`、`-75` dBm 分档。
- 企业认证与未知安全类型交给系统 Wi-Fi 设置；基础安全提示只按协议类型判断，不承诺与系统所有规则一致。
- 连接过程仅表示 Combo 发起的连接；普通扫描不触发连接动画。失败、取消和状态变化不得显示成功。

个人热点用独立私有发现会话，见 [个人热点](network.md#hotspot)；普通 Wi-Fi 扫描不提供手机电量与蜂窝等级。

## 密码与权限

| 能力 | 当前权限和行为 |
| --- | --- |
| 默认路径监听与本机配置 | 不为此请求定位或本地网络 |
| SSID/BSSID 与扫描 | 定位授权；缺失名称不能当作断网 |
| 系统保存的 Wi-Fi 密码 | 用户点击已知普通加密网络时，按所选 SSID 调用 `CWKeychainFindWiFiPassword`；开关默认开启，不等于系统已授权 |
| 手动输入并记住密码 | 仅连接成功后存入本机 Combo 钥匙串，可取消记住或删除；系统密码不复制到此处 |
| 附近 AirPlay Bonjour | 本地网络授权，见 [AirPlay](audio.md#airplay) |

系统密码先查用户域，仅项目不存在才查系统域；拒绝/取消或其他访问失败不继续域回退。拒绝后停止本次连接和本次运行的重复请求，用户可在设置中重新允许下次请求。关闭偏好会使尚未完成的读取结果失效，不撤销 macOS 已授予的钥匙串访问权。旧版只按名称保存的 Combo 密码不自动复用，新条目按名称与安全类型隔离。

不保存地理坐标，不上传网络名称或密码。详见 [设置规格](../product/behavior.md#settings)。

## API 证据

以下为历史核查来源，本次整理未重新在线核查：

- [NWPath](https://developer.apple.com/documentation/network/nwpath)：`usesInterfaceType` 与 `availableInterfaces` 不能证明全机流量路径。
- [PrimaryInterface](https://developer.apple.com/documentation/systemconfiguration/kscdynamicstorepropnetprimaryinterface-swift.var)、[全局网络键](https://developer.apple.com/documentation/systemconfiguration/scdynamicstorekeycreatenetworkglobalentity(_:_:_:))：系统主接口解析依据。
- [CWInterface](https://developer.apple.com/documentation/corewlan/cwinterface)、[RSSI](https://developer.apple.com/documentation/corewlan/cwinterface/rssivalue())、[SSID 定位权限变化](https://developer.apple.com/forums/thread/732431)：RSSI 与网络名的权限、未知值语义不同。历史 macOS 26/27 SDK 头文件核查不能替代签名 App 实测。
- [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)：Bonjour/局域网发现与普通路径监听权限不同；macOS 15 起引入本地网络隐私。

若将来改变沙盒或发行签名，需重新核对 location/network entitlement 与真实授权行为，不沿用开发进程的成功作为保证。

## 历史验证与待验收

2026-09-24 的 `Tests/WiFiControlCheck.swift` 覆盖同名安全类型隔离、当前 BSSID、RSSI 未知、安全分类及密码请求取消等规则；演示数据检查列表展开、密码表单与企业认证提示。历史验证未切换真实网络、未写入真实 Wi-Fi 密码。

日常检查入口为 `./verify.sh`。仍需在当前签名应用中验收首次允许/拒绝/撤销定位与钥匙串权限、实际连接和失败恢复、Wi-Fi/以太网双连接、IPv6/双栈冲突、VPN/隧道、睡眠唤醒及扩展坞拔插。实时状态与演示状态应分别检查，未知信号不能阻断其他功能。

<a id="hotspot"></a>

## 个人热点

历史实机验证：2026-09-24，macOS 27.0 build `26A428`；当前只读取手机状态，连接交给系统设置。

### 当前实现

[HotspotControl.swift](../../Combo/Network/HotspotControl.swift) 动态加载私有 `Sharing.framework`，创建 `SFRemoteHotspotSession`，接收 `session:updatedFoundDevices:`；[Wi-Fi 面板](../../Combo/Views/WiFiSections.swift) 展示发现结果。只允许已验证 build `26A428`，其他版本显示不可用并保留系统入口。

- 面板可见、屏幕活动且 Wi-Fi 开启时开始；关闭面板、睡眠、关闭 Wi-Fi 或退出后停止并清空。
- 系统回调替换完整列表，按设备标识去重；同名不同设备保留，旧会话迟到回调丢弃。标识只用于内存身份。
- 首次回调等待超过 10 秒显示“暂时无法读取手机信息”，可重试；正常空列表显示“未发现可用个人热点”。
- 手机行与设置箭头打开系统 Wi-Fi 设置，不调用热点启用、连接或网络切换接口。

### 字段与显示

| 字段 | 当前接受范围 / 显示 | 2026-09-24 历史观测与限制 |
| --- | --- | --- |
| `deviceName` | 非空真实名称 | 与系统个人热点设备名一致 |
| `batteryLife` | 0–100 整数；横向电池中显示整数，填充随电量变化 | 曾返回 75；未独立校准手机屏幕的电量 |
| `signalStrength` | 0–4 整数；四阶蜂窝条 | 曾返回 4；不是 Wi-Fi RSSI，不保证所有版本量程相同 |
| `networkType` | 不展示制式文字 | 曾返回 8，未确认完整 5G/LTE 映射 |
| `cachedDevice` / `lastSeen` | 不转换为用户可见更新时间 | 曾返回 false / 0；时间语义未确认 |

类型错误、布尔冒充数字、越界或缺失的电量/信号字段隐藏，不补造正常值。整行辅助功能朗读蜂窝等级与电量百分比。

### API 依据

普通 CoreWLAN 扫描返回接入点名称、RSSI、信道和安全类型，没有手机电量、蜂窝信号或可靠的“这是手机热点”字段，因此普通扫描不能完整复刻 Instant Hotspot 分组。Wi-Fi 名称与扫描的定位权限说明见 [网络实现](network.md)。

运行时核查以本机存在的类、方法及类型为依据；旧逆向头文件只提供线索：[SFRemoteHotspotSession](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/Sharing.framework/SFRemoteHotspotSession.h)、[委托](https://github.com/nst/iOS-Runtime-Headers/blob/master/protocols/SFRemoteHotspotSessionDelegate.h)、[设备字段](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/Sharing.framework/SFRemoteHotspotDevice.h)。旧头文件中的 `cellularProtocolString` 在本机设备类不存在；[Continuity 广播枚举](https://github.com/furiousMAC/continuity/blob/master/messages/tethering_source.md)也不能直接套用为对象的 `networkType`。

公开扫描参考：[Apple CoreWLAN](https://developer.apple.com/documentation/corewlan/cwinterface/scanfornetworks(withssid:includehidden:))、[CWNetwork](https://developer.apple.com/documentation/corewlan/cwnetwork)、[Apple DTS 的 SSID 权限说明](https://developer.apple.com/forums/thread/732431?answerId=758114022)。这些来源来自历史调研，本次整理未重新在线核查。

### 历史验证与待验收

2026-09-24 的构建、签名与 `Tests/HotspotControlCheck.swift` 通过；检查覆盖字段异常、重复设备、移除、重复开始、停止、超时、能力缺失和旧回调。正式读取对象连续两次启停发现真实手机；面板辅助功能树显示名称、电量和更新后的信号，点击后打开系统 Wi-Fi 页面，未切换当前网络。

真实组件曾检查 340 pt 宽度、深浅外观、0–4 信号、0/5/25/75/100 电量及缺失字段。空/失败与设备移除主要由自动检查覆盖，没有通过关闭真实手机/Wi-Fi 制造故障。跨构建、不同手机、电量校准、签名发行版与沙盒仍未验收。
