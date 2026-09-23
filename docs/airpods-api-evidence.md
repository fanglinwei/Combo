# AirPods 电量读取：公开框架与私有接口证据

版本归属：后续版本技术证据，不属于 MacBook 首版实施范围。见[后续版本规划](combo-roadmap.md)。

访问日期：2026-09-22。本笔记只做第一方源码与官方文档核查，没有运行设备查询、安装软件或连接耳机实测；源码存在不等于所有 macOS、耳机代际均可用。

**结论：第三方 Mac 应用已有读取 AirPods 电量的实现，但这里核实的直接读取路线使用私有电量属性，不能称为 Apple 正式公开的 AirPods 电池 API。**

## Hammerspoon

`extensions/battery/libbattery.m` 明确声明 `IOBluetoothDevice (Private)`，含 `batteryPercentLeft/Right/Case/Single`。`privateBluetoothBatteryInfo()` 枚举已连接设备并读取这些属性。注释明确提醒系统升级可能破坏接口；盒子休眠时 Case 经常为零，左右耳字段描述为出盒时的电量。因此零值不能不加判断地显示成真实耗尽。[固定源码版本](https://github.com/Hammerspoon/hammerspoon/blob/c317acb9c46ae9f91c0e39cf06e39eade9333614/extensions/battery/libbattery.m#L158-L213)

## PairPods 0.7.0

本次官网与 latest 发布链接指向 0.7.0；官网声明 macOS 13.5 起，并限定为设备有上报时显示电量，不能将其理解成所有耳机都支持。[官网](https://pairpods.app/)、[发布页](https://github.com/wozniakpawel/PairPods/releases/tag/v0.7.0)

该版本从 Core Audio UID 提取蓝牙地址，匹配已配对且已连接的 `IOBluetoothDevice`，通过 `responds(to:)` 和 KVC 读取上述私有属性；双耳取较低值，盒子不参与主显示。其实现把非正数当作未上报；地址匹配失败、未连接、属性不存在或没有有效耳机电量时返回空。因此它提供可参考的容错机制，但不能证明 0% 与未知已被完整区分，也没有证明数据实时性。[查询源码](https://github.com/wozniakpawel/PairPods/blob/ba8aece8f1378b42768cfead705404ba2ae04761/PairPods/AudioDevice.swift#L368-L408)、[显示值逻辑](https://github.com/wozniakpawel/PairPods/blob/ba8aece8f1378b42768cfead705404ba2ae04761/PairPods/AudioDevice.swift#L304-L316)

## API 与分发边界

Apple 公开文档列出 `pairedDevices()`、`isConnected()` 和 `addressString`；未列出以上电量属性。公开框架内调用未公开 selector，仍不能据此宣称整个方案使用公开 API。[Apple IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice)

Apple App Review Guidelines 2.5.1 要求仅使用公开 API；所以“第三方可实现”与“可按此路线提交 Mac App Store”是不同结论。本笔记不保证审核结果。[Apple 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

对 Combo 的建议：保留 AirPods 电量外圈设计，进入原型验证时分别检查左右耳、开盒/合盒、切换连接及过期数据；不可用时显示未知，不把盒子休眠误画成 0%。
