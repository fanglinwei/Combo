# 声音与 AirPods：实现、技术证据及验证边界

整理：2026-10-04。历史实机读写验证：2026-09-24，macOS 27.0 build `26A428`，本地 ad-hoc 原型。电量来源的早期研究为 2026-09-22；现在已接入声音面板，外圈仍表示 Mac 本机电量。

## 当前能力

| 功能 | 当前实现 | 验证边界 |
| --- | --- | --- |
| 输出设备、音量、静音 | CoreAudio；主通道不可读时回退左右声道；默认输出列表与事件监听 | 设备切换及不同硬件仍需实机回归 |
| AirPods 电量 | IOBluetooth 私有左右耳/充电盒 getter | 字段独立；盒子休眠、歧义零值、不支持保留未知 |
| 聆听模式 | 通透、自适应、降噪；私有 AVOutputDevice 写后回读 | 本机往返切换曾通过；Normal/关闭模式未独立确认，面板不提供 |
| 对话感知 | 两段关闭/打开，写后回读 | 本机关闭→开启→关闭曾通过 |
| 空间音频 | 不监控、不展示、不提供写操作 | 早期写入未确认；最终已移除全部字段与查询 |
| AirPlay | 默认路由识别与附近发现另见 [AirPlay 文档](airplay-homepod-icon-research.md) | 未路由设备的面板直连未实现 |

实现入口：[AudioStore.swift](../Combo/Stores/AudioStore.swift)、[AudioVolume.swift](../Combo/Audio/AudioVolume.swift)、[AirPodsControl.swift](../Combo/Audio/AirPodsControl.swift)、[AirPodsHelper.m](../Combo/Audio/AirPodsHelper.m)、[AirPodsContext.c](../Combo/Audio/AirPodsContext.c)、[SoundSections.swift](../Combo/Views/SoundSections.swift)。

## 身份、生命周期与失败处理

只在真实面板可见、屏幕活动且当前输出适用时读取；AirPods 每 3 秒一次。关闭面板、睡眠或设备变化会取消请求并清除旧快照。蓝牙类别复用同一 status 请求，见 [蓝牙分类](bluetooth-audio-device-icon-research.md)。

helper 用 `IOBluetoothDevice.outputAudioDeviceID` 匹配默认输出，通过 associatedAudioDeviceID 与 CoreAudio UID translation 将 AV context 映射到同一输出；请求携带设备 ID 和 UID 的 SHA-256 摘要，不按名称匹配。写前复查 CoreAudio/UID/AV 端点，写后约 1.5 秒回读；设备变化、超时、损坏 JSON、未确认状态都不能显示成功。

后台读取与用户写入的 busy 分开；相同快照不重复发布更新，避免每 3 秒禁用/闪烁控件。点击可以取消只读查询并优先写入；重复写入拒绝。待确认选中值与真实快照分开，拒绝/失败/超时回退，关闭或换设备清除。

`AirPodsContext.c` 只在新启动 helper 中适配私有 entitlement 查询，其他查询转回原函数；不注入系统进程、不修改 SIP。本地打包运行曾验证，Developer ID、公证和沙盒未验证。

## 控件的最终行为

输出设备使用真实列表与共享类别，选中项强调色、整行悬浮背景；AirPods 可展开/收起，收起保留电量，关闭面板停止读取。

聆听模式三段、对话感知两段：图标在胶囊内，名称在下方，单个选中胶囊以 220 ms ease-in-out 滑动；减少动态效果时停止滑动。水平拖动须从当前胶囊开始，只预览位置，松开按最近项提交一次请求，原项不写入，两端限位。保留点击、原生辅助功能按钮、确认期间禁用与失败回退。

早期勾选列表、Switch 和各次边界调整已被此界面替代，不再维护临时截图/构建产物路径作为操作入口。

## 本机历史观测与验证

2026-09-24 单副耳机的产品 ID 为 `0x2027`；AirPods Pro 3 对应来自社区资料，不能以名称或该记录保证全部机型。一次采样左右耳为 43%/34%，盒子未知；主通道音量读取返回 OSStatus `2003332927`，左右声道约 0.3125。HAL `lstm = 2`、`lsms = 7` 仅是原始值，不推完整枚举。

未适配时共享音频 context 不可用；适配后可读模式与对话感知。降噪↔通透、降噪↔自适应、对话感知关闭↔开启经独立进程回读通过并恢复原状态。Normal 未确认，空间音频多种 setter 未确认持久变化，这些失败不计入通过项。

历史原生窗口检查了展开/收起、真实选中状态与音量回退；拖动验证窗口使用测试 helper，确认改变选项各一次请求、小幅拖动零请求和越界限位，未修改真实耳机。完整键盘遍历、纯悬浮视觉和 220 ms 逐帧动画未验收。

日常检查用 `./verify.sh`；`Tests/AirPodsCheck.swift` 覆盖声道选择、异常字段、身份/旧设备、重复操作、未确认写入、损坏 JSON、进程失败、超时、取消、静默轮询、待确认与拖动几何。真实设备脚本默认只读，`--write` 会改变设置并逐项恢复，需在明确开展硬件验证时使用：

```sh
python3 Tests/airpods-live-check.py '<已构建 Combo.app 的路径>'
python3 Tests/airpods-live-check.py '<已构建 Combo.app 的路径>' --write
```

多耳机、改名、断开重连、睡眠唤醒、不同型号/固件与系统版本仍需实机覆盖；历史构建通过不表示本次重新测试。

## 电量来源与扩展研究

2026-09-22 的资料研究并入本节，用于更多型号与 [关联设备外圈规划](combo-roadmap.md)，不是“AirPods 电量尚未实现”的计划。

| 路线 | 已核查证据 | 取舍与限制 |
| --- | --- | --- |
| IOBluetooth 私有 getter | Hammerspoon 声明 `batteryPercentLeft/Right/Case/Single`；PairPods 0.7.0 按地址匹配后读取 | 当前采用同类私有路线；公开框架不令私有 selector 成为公共 API |
| `system_profiler SPBluetoothDataType -json -timeout 10` | MacSweep/AirBattery 解析 Main/Left/Right/Case 字段 | 未采用轮询；报告可能缺字段或缓存，不是专门电量 SDK |
| CoreBluetooth 厂商广播 | AirBattery 解析 `CBAdvertisementDataManufacturerDataKey` 与缺失标记 | 公开扫描不等于 Apple 公开协议；型号、精度、开合盖与权限仍需维护 |

Hammerspoon 注释提醒充电盒休眠常返回零，左右耳字段可能只反映出盒时读数。PairPods 非正数当缺失的策略不能证明真实 0% 与未知已完全区分。来源设备、采集时间与设备上报时间不同；扩展时须分别保存左右耳/盒子、有效/未知/过期/断开，不用未知值参与最低电量，不把盒子纳入双耳主显示。固定绑定、身份和外圈空态仍属规划。

## 来源

以下为历史来源，本次整理未重新在线核查或安装上游项目：

- [Hammerspoon 固定电量源码](https://github.com/Hammerspoon/hammerspoon/blob/c317acb9c46ae9f91c0e39cf06e39eade9333614/extensions/battery/libbattery.m#L158-L213)、[Apple IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice)：公开连接字段与私有电量属性的边界。
- [PairPods 0.7.0](https://github.com/wozniakpawel/PairPods/releases/tag/v0.7.0)、[查询源码](https://github.com/wozniakpawel/PairPods/blob/ba8aece8f1378b42768cfead705404ba2ae04761/PairPods/AudioDevice.swift#L368-L408)：地址匹配与私有字段容错。
- [AirBattery 固定 BLE/报告源码](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift)、[MacSweep](https://github.com/VincentShipsIt/macsweep.dev/blob/master/MacSweep/Sources/Core/Monitoring/ConnectedDevice.swift)：未采用的其他电量路径。
- [airpods-control 私有接口](https://github.com/raulgg/airpods-control/blob/main/Sources/AirPodsControl/PrivateAudio.swift)、[安全模型](https://github.com/raulgg/airpods-control/blob/main/SECURITY.md)、[兼容矩阵](https://github.com/raulgg/airpods-control/blob/main/docs/compatibility.md)：模式字符串、进程内适配与上游硬件验证，不替代 Combo 验收。
- [AudioSwitch 音量回退](https://github.com/iamzifei/audioswitch/blob/main/Sources/AudioSwitchCore/VolumeController.swift)、[switchaudio-osx](https://github.com/deweller/switchaudio-osx)：CoreAudio 参考，未引入整个应用。
- [Apple App Review 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)：第三方可实现与私有路线可提交商店是不同结论，不保证审核结果。
