# 个人热点：实现、API 与验证边界

整理：2026-10-04。历史实机验证：2026-09-24，macOS 27.0 build `26A428`。当前功能只读取手机状态，点击后由用户在系统 Wi-Fi 设置中连接。

## 当前实现

[HotspotControl.swift](../Combo/Network/HotspotControl.swift) 动态加载私有 `Sharing.framework`，创建 `SFRemoteHotspotSession`，接收 `session:updatedFoundDevices:`；[Wi-Fi 面板](../Combo/Views/WiFiSections.swift) 展示发现结果。只允许已验证 build `26A428`，其他版本显示不可用并保留系统入口。

- 面板打开、处于真实状态、屏幕活动且 Wi-Fi 开启时开始；关闭面板、睡眠、关闭 Wi-Fi 或退出后停止并清空。
- 系统回调替换完整列表，按设备标识去重；同名不同设备保留，旧会话迟到回调丢弃。标识只用于内存身份。
- 首次回调等待超过 10 秒显示“暂时无法读取手机信息”，可重试；正常空列表显示“未发现可用个人热点”。
- 手机行与设置箭头打开系统 Wi-Fi 设置，不调用热点启用、连接或网络切换接口。

## 字段与显示

| 字段 | 当前接受范围 / 显示 | 2026-09-24 历史观测与限制 |
| --- | --- | --- |
| `deviceName` | 非空真实名称 | 与系统个人热点设备名一致 |
| `batteryLife` | 0–100 整数；横向电池中显示整数，填充随电量变化 | 曾返回 75；未独立校准手机屏幕的电量 |
| `signalStrength` | 0–4 整数；四阶蜂窝条 | 曾返回 4；不是 Wi-Fi RSSI，不保证所有版本量程相同 |
| `networkType` | 不展示制式文字 | 曾返回 8，未确认完整 5G/LTE 映射 |
| `cachedDevice` / `lastSeen` | 不转换为用户可见更新时间 | 曾返回 false / 0；时间语义未确认 |

类型错误、布尔冒充数字、越界或缺失的电量/信号字段隐藏，不补造正常值。整行辅助功能朗读蜂窝等级与电量百分比。

## API 依据

普通 CoreWLAN 扫描返回接入点名称、RSSI、信道和安全类型，没有手机电量、蜂窝信号或可靠的“这是手机热点”字段，因此普通扫描不能完整复刻 Instant Hotspot 分组。Wi-Fi 名称与扫描的定位权限说明见 [网络实现](network-implementation-evidence.md)。

运行时核查以本机存在的类、方法及类型为依据；旧逆向头文件只提供线索：[SFRemoteHotspotSession](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/Sharing.framework/SFRemoteHotspotSession.h)、[委托](https://github.com/nst/iOS-Runtime-Headers/blob/master/protocols/SFRemoteHotspotSessionDelegate.h)、[设备字段](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/Sharing.framework/SFRemoteHotspotDevice.h)。旧头文件中的 `cellularProtocolString` 在本机设备类不存在；[Continuity 广播枚举](https://github.com/furiousMAC/continuity/blob/master/messages/tethering_source.md)也不能直接套用为对象的 `networkType`。

公开扫描参考：[Apple CoreWLAN](https://developer.apple.com/documentation/corewlan/cwinterface/scanfornetworks(withssid:includehidden:))、[CWNetwork](https://developer.apple.com/documentation/corewlan/cwnetwork)、[Apple DTS 的 SSID 权限说明](https://developer.apple.com/forums/thread/732431?answerId=758114022)。这些来源来自历史调研，本次整理未重新在线核查。

## 历史验证与待验收

2026-09-24 的构建、签名与 `Tests/HotspotControlCheck.swift` 通过；检查覆盖字段异常、重复设备、移除、重复开始、停止、超时、能力缺失和旧回调。正式读取对象连续两次启停发现真实手机；面板辅助功能树显示名称、电量和更新后的信号，点击后打开系统 Wi-Fi 页面，未切换当前网络。

真实组件曾检查 340 pt 宽度、深浅外观、0–4 信号、0/5/25/75/100 电量及缺失字段。空/失败与设备移除主要由自动检查覆盖，没有通过关闭真实手机/Wi-Fi 制造故障。跨构建、不同手机、电量校准、签名发行版与沙盒仍未验收。

早期的 iPhone/Android 热点开关、MDM、root 和快捷指令方案已移除：它们不属于当前 macOS 只读发现功能。关联手机电量作为外圈来源是另一项研究，见 [iPhone 电量](iphone-battery-research.md)。
