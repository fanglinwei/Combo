# 第三方读取 AirPods 电量：Combo 可行性调研

版本归属：**后续版本研究，不纳入 MacBook 首版。**功能范围与推进条件见[后续版本规划](combo-roadmap.md)。

调研日期：2026-09-22。方法：核对项目源码、开发者发布记录、Apple 文档及本机 SDK／命令手册。没有安装第三方应用、扫描附近设备或连接 AirPods 实测。

## 结论

**第三方 macOS 应用可以读取 AirPods 电量，已有可检查的开源实现。** 可获取的数据包括左右耳、充电盒及部分充电状态，但字段是否存在、精度、更新时机和支持型号取决于读取路径、设备与系统版本。不能据此承诺全部型号、持续实时更新或所有分发环境可用。

证据不是只来自系统界面：Hammerspoon 源码直接读取电量属性；AirBattery 源码解析 AirPods 广播并回退查询系统蓝牙报告；MacSweep 源码解析该报告中的左右耳与充电盒字段。[Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/battery/libbattery.m)、[AirBattery 固定版本源码](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift)、[MacSweep](https://github.com/VincentShipsIt/macsweep.dev/blob/master/MacSweep/Sources/Core/Monitoring/ConnectedDevice.swift)。

## 路径一：系统蓝牙报告

可验证的最小入口为：

```sh
/usr/sbin/system_profiler SPBluetoothDataType -json -timeout 10
```

本次未执行设备查询。Apple 随系统提供的 `man system_profiler` 确认 JSON 输出与超时选项；该手册没有承诺各蓝牙电量字段始终存在或报告固定时延。

MacSweep 的 `ConnectedDeviceScanner` 实际执行系统报告，并读取 `device_batteryLevelMain`、`device_batteryLevelLeft`、`device_batteryLevelRight`、`device_batteryLevelCase`。AirBattery 的 `getLevel` 同样从已缓存的 `SPBluetoothDataType` 结果读取对应字段。[MacSweep 源码](https://github.com/VincentShipsIt/macsweep.dev/blob/master/MacSweep/Sources/Core/Monitoring/ConnectedDevice.swift)、[AirBattery getLevel](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift#L268-L284)。

判断：适合先做一个最小实机探针，验证目标 AirPods 与 macOS 的字段覆盖。它是系统报告解析，不是专门的 AirPods 电量 SDK；字段结构与沙盒内可用性需要验证。不要每个动画帧或每秒启动一次报告，也不能把重新读取同一缓存视为设备刚上报了新值。

## 路径二：CoreBluetooth 扫描和厂商广播解析

AirBattery 导入公开 CoreBluetooth，通过 `CBAdvertisementDataManufacturerDataKey` 取得厂商广播，按长度与消息类型区分开盖、合盖路径，再提取左右耳和盒子的电量、充电标记；遇到 `255` 缺失值，回退到系统报告。[AirBattery 解析实现](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift#L304-L360)、[Apple 广播数据键](https://developer.apple.com/documentation/corebluetooth/cbadvertisementdatamanufacturerdatakey)。

这条路径说明**不必把直接调用私有电量 selector 作为唯一方案**，但公开扫描 API 不等于 Apple 公开承诺了这些字节的 AirPods 协议含义。报文格式和型号映射仍属于项目解析约定，需要验证和维护。该源码既记录粗略电量位，也使用更细的电量字段，不能笼统称所有蓝牙广播都是 10% 精度，或反过来保证所有读数都有 1% 精度。

项目按时间窗口扫描，而非无限高频扫描；README 说明需要蓝牙权限，长时间未更新会提示可能离线。字段精度、设备识别、开合盖条件及后台行为应分别验收。[AirBattery 源码](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift)、[项目说明](https://github.com/lihaoyun6/AirBattery)。

## 路径三：IOBluetooth 私有电量属性

Hammerspoon 明确把相关方法声明为私有 API，并读取 `batteryPercentLeft`、`batteryPercentRight`、`batteryPercentCase` 等字段；其注释指出充电盒经常因休眠而返回 0。公开 IOBluetooth 框架的存在，不能证明这些具体属性是公开接口。本机 SDK 的 IOBluetooth 公开头文件检索也未找到这些 `batteryPercent*` 名称。[Hammerspoon 源码](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/battery/libbattery.m)、[Apple IOBluetooth 文档](https://developer.apple.com/documentation/iobluetooth)。

PairPods 的 0.7.0 发布记录（2026-03-22）称，将失效的 IOKit／IORegistry 电量方案替换为 IOBluetooth，并改用设备地址匹配；这是现有路径发生兼容性变化的具体案例。[PairPods 发布记录](https://pairpods.app/)。详细 API 核查见 [补充证据](airpods-api-evidence.md)。

判断：此路径有工程先例，但不适合作为 Combo 首版唯一承诺；尤其不能仅因框架本身公开，就把其私有电量方法当作稳定公共 API。

## 对 Combo 的设计和实施建议

以下为基于上述证据的设计建议，不代表已接入真实设备：

1. 可以继续设计“台式 Mac 外圈显示指定 AirPods 电量”，保留外圈始终代表电量的含义。
2. 首先用系统报告做目标系统／耳机的最小实测；覆盖不足时，再评估按需 BLE 扫描。不要一开始整合全部路径。
3. 左右耳和充电盒独立保存。外圈若采用较低有效耳机电量，不应包含盒子；只有一耳有效时不能用另一耳的未知值参与最小值运算。
4. 至少区分有效、未知、过期、断开。私有路径中盒子返回的 0 可能有歧义，不能统一显示为“没电”，也不能把所有真实 0% 都忽略；必须结合来源和状态判断。
5. 外圈读不到数据时保留淡色轮廓；精确读数、来源设备与最近读取时间在面板显示。若只能证明采集时间，不能冒充设备上报时间。
6. 固定绑定用户选定的设备，不用设备名作为唯一身份，不展示附近其他人的耳机。
7. 动画刷新与电量获取独立运行。媒体音柱不驱动蓝牙扫描或系统报告。

## 最小实机验证清单

- 确定目标 macOS 与 AirPods 型号／固件，记录数据来源。
- 双耳播放、单耳使用、暂停，分别检查左右耳读数和更新条件。
- 开盒、合盒、耳机放回，确认盒子是否可读及何时失效。
- 断开、重连、蓝牙关闭、Mac 睡眠唤醒，检查是否把旧值误作实时值。
- 两副耳机同时出现、耳机改名，确认仍绑定正确设备。
- 核对低电量与 0%／缺失标记处理；检查精度，不补造小数或个位数。
- 在最终选择的签名、权限与沙盒环境中复验。开源应用的运行方式不能自动代表 Combo 的目标发布环境。

## 对此前 iPhone 判断的补充

此次在 AirBattery 项目说明中还发现 iPhone 电量读取先例：其 Wi-Fi／USB 路径要求手机信任 Mac 并配对，使用 libimobiledevice；另有蓝牙模式。因此应把此前“尚未找到通用公开接口”的表述理解为没有确认通用官方 SDK，**不等于第三方完全无法读取 iPhone 电量**。手机路径不属于本次 AirPods 主结论，需要另做验证。[AirBattery README](https://github.com/lihaoyun6/AirBattery)。
