# Mac 调用获取 iPhone 电量的可行性

版本归属：**后续版本研究，不纳入 MacBook 首版。**功能范围与推进条件见[后续版本规划](combo-roadmap.md)。

调研日期：2026-09-22。范围：为 Combo 的关联设备电量外圈评估数据来源。仅核查第一方项目源码和 Apple 官方文档，未安装依赖、配对手机、修改无线连接设置或进行设备实测。

## 结论

**可行，已有第三方实现；优先验证“首次 USB 信任／配对，之后在局域网查询”的方案。** 不需要把“安装 iPhone 配套 App”作为唯一前提，也不能把“同一 Apple 账户”当成足以读取电量的条件。

最直接的证据是 AirBattery 的 `IDeviceBattery.swift`：枚举 USB 和网络设备，调用 libimobiledevice 的 `ideviceinfo` 查询 `com.apple.mobile.battery`，读取 `BatteryCurrentCapacity` 和 `BatteryIsCharging`。[固定源码](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/IDeviceBattery.swift)。

## 方案比较

| 路径 | 手机端 App | 条件与证据 | 对 Combo 的判断 |
| --- | --- | --- | --- |
| USB + libimobiledevice | 不要求 | 设备连线，完成信任和配对；源码有实际电量查询 | 最小实测起点 |
| 网络 + libimobiledevice | 不要求 | 信任／配对、无线连接启用、设备能被发现且可达；AirBattery 要求初次连线配对及同局域网 | 优先评估的日常体验 |
| 蓝牙发现 + GATT 读取 | 不要求 | AirBattery 有特定 iPhone／蜂窝 iPad 路径；需蓝牙权限和适配验证 | 补充路径，不作为普遍保证 |
| iPhone App 读取后同步 | 需要 | 手机使用公开 UIDevice 电量 API；同步与后台更新需自行设计 | 官方手机端 API 清晰，但后台时效不可保证 |

前两条是第三方库访问设备协议，不是 Apple 提供的通用跨设备电池 SDK；开源工具能运行不代表任意沙盒或商店发布形态都可直接照搬。[libimobiledevice](https://libimobiledevice.org/)、[ideviceinfo 上游源码](https://github.com/libimobiledevice/libimobiledevice/blob/master/tools/ideviceinfo.c)。

## USB／网络路径的调用方式

以下是供后续验证的命令示例，本次没有执行。`DEVICE_UDID` 必须替换为用户选定、已配对设备的标识。

```sh
# USB 设备的电量与充电状态
ideviceinfo -u DEVICE_UDID -q com.apple.mobile.battery

# 已配对且可以通过网络发现的设备
ideviceinfo -n -u DEVICE_UDID -q com.apple.mobile.battery
```

上游 `ideviceinfo.c` 明确支持 `-n` 网络模式、`-u` 指定设备、`-q` 指定查询域，并通过 lockdownd 会话取得值。AirBattery 使用该查询读取当前电量和充电布尔值；这不是电池健康度或最大容量百分比。[上游源码](https://github.com/libimobiledevice/libimobiledevice/blob/master/tools/ideviceinfo.c)、[AirBattery 调用](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/IDeviceBattery.swift#L47-L86)。

AirBattery 在 USB 路径另外执行自带的 `wificonnection` 工具启用无线连接。因此不能把该项目的“插过一次线后可无线查询”误解成所有用户只点一次信任后便自动具备无线查询条件。Combo 若采用此路径，应明确引导并验证无线连接启用状态，不能悄悄修改设置。[同一调用文件](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/IDeviceBattery.swift#L70-L85)。

## 蓝牙路径：不能仅描述为被动读取广播中的电量

AirBattery 的 BLE 实现以特定 Apple 广播类型发现设备，随后调用 `centralManager.connect`、发现服务并读取 `180F` 服务下的 `2A19` 特征。也就是说，观察到广播只是发现步骤，后续还有连接与读取，不宜承诺“扫描一下就能拿到所有 iPhone 的准确电量”。项目 README 限定该功能用于 iPhone／蜂窝版 iPad，并要求开启蓝牙。[BLE 源码](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift#L147-L237)、[项目 README](https://github.com/lihaoyun6/AirBattery)。

该分支的充电状态推断代码被注释，不能据此声称蓝牙路径与 USB／网络路径具有同等充电状态能力。设备识别、允许连接的条件、锁屏与后台广播行为均需实测；不能从项目存在推出无需任何前提即可读取附近所有手机。

## 配套 iPhone App 路径

手机 App 可开启 `UIDevice.current.isBatteryMonitoringEnabled` 后读取 `batteryLevel`。官方规定其范围为 0 到 1；未开启监测时可能返回 -1，不能显示成真实电量。该 API 读取运行 App 的本机电量，不是让 Mac 直接读取远端 iPhone 的 API。[batteryLevel](https://developer.apple.com/documentation/uikit/uidevice/batterylevel)、[isBatteryMonitoringEnabled](https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled)。

手机再把数据同步给 Mac 是可设计的方案，但普通后台刷新由系统决定启动时机，不支持据此承诺每分钟固定更新或锁屏后持续实时上报。此方案增加手机端应用与同步维护，不是 Combo 首次验证的最短路径。[Apple 后台执行策略](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)。

## 对产品的建议

1. 将 iPhone 列为“需要设置的关联电量来源”，而不是登录同一账户后自动可用的承诺。
2. 设置流程：选择手机 → USB 信任／配对 → 首次电量查询成功 → 引导确认无线连接 → 拔线验证 → 才允许作为无线电量来源。
3. 网络不通、锁屏后会话失败、手机重启或信任失效时，显示“未连接／数据不可用”，保留淡色外圈。手机重启后的首次解锁等场景必须单独验收，当前未证明可连续查询。
4. 正常时显示电量、充电状态和明确的设备名称；过期时展示上次成功读取的时间，不把缓存当成实时状态。
5. Mac 可以通过以太网连接局域网，iPhone 使用 Wi-Fi；产品需要的是可发现且互通的网络路径，不应只检查 Mac 是否开了 Wi-Fi。具体混合网络环境仍需验证，尤其访客网络和客户端隔离。
6. 先做一个 USB + 网络查询探针验证目标设备，不同时搭建云同步、iPhone App 和多条蓝牙回退路径。

## 实测与边界

必须覆盖：USB 已信任／未信任；无线启用／未启用；同网可达／网络隔离；锁屏、长时间闲置、低电量模式、手机重启后首次解锁前后；Mac 睡眠唤醒；充电、未充电、满电；两台手机和设备改名；最终签名与沙盒环境。

本次确认的是**第三方调用有现实实现和明确命令**，不是对当前手机及系统版本的实测保证。官方连接条件与上游调用细节见 [补充证据](iphone-api-evidence.md)。
