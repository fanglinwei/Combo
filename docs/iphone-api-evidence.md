# iPhone 电量读取：USB 与网络查询证据

版本归属：后续版本技术证据，不属于 MacBook 首版实施范围。见[后续版本规划](combo-roadmap.md)。

访问日期：2026-09-22。仅审阅上游源码及 Apple 官方文档，未安装软件、查询设备、配对或修改设置；没有实测锁屏、重启和具体 iOS 版本。

**结论：libimobiledevice 提供可用于查询 iPhone 电池信息的工具路径，支持 USB 和网络连接，但不能由此承诺同一 Apple 账户即可自动、持续读取。**

上游 `ideviceinfo.c` 将 `com.apple.mobile.battery` 列为已知查询域。`-u` 指定设备 UDID，`-n` 选择网络设备，`-q` 指定域，`-k` 指定字段；实现通过 `lockdownd_get_value` 读取，默认先建立带握手的会话。可供后续验证的命令形态如下，本次没有执行：[固定源码](https://github.com/libimobiledevice/libimobiledevice/blob/bcced6c4f6a79e09ed3961632b2faf81fe873137/tools/ideviceinfo.c)

```sh
# USB：查询整个电池域
ideviceinfo -u '<设备UDID>' -q com.apple.mobile.battery
# 网络：查询同一个域
ideviceinfo -n -u '<设备UDID>' -q com.apple.mobile.battery
```

上述证据证明查询能力和命令语法，不保证每代系统返回哪些字段。原型应检查真实返回值、类型、范围和缺失情况，不能把命令成功退出或空输出等同于取得有效电量。

**信任与网络前提：**Apple 说明首次信任电脑需要连接设备、解锁，并在 Mac 与 iPhone 上确认；信任持续到用户撤销或抹掉设备。信任的权限范围大于“只读取电量”，应在设置引导中如实说明。[Apple 信任电脑说明](https://support.apple.com/en-us/109054)

Apple 的 Finder 无线连接流程是先用 USB 连接，在“通用”勾选“连接 Wi-Fi 时显示此设备”并应用；此后同一 Wi-Fi 网络下设备可出现在 Finder。文档将“接通电源”描述为自动同步触发条件，不能误写成所有网络查询必须充电。Finder 可发现也不等于第三方查询必定成功；台式 Mac 使用以太网时的实际发现条件仍需验证。[Apple Finder Wi-Fi 说明](https://support.apple.com/en-us/102471)

**未证实边界：**本次来源没有保证已信任设备在持续锁屏、重启后首次解锁前、睡眠、跨网段或系统升级后始终可查询。不能承诺后台永久在线，也不能把 libimobiledevice 的协议实现称为 Apple 承诺稳定的公开电量 SDK。Combo 若采用此路径，应把手机电量设计为可选来源，显示更新时间，并允许“不可用／需重新连接”。
