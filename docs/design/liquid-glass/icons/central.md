# Combo 中央图标设计提案

更新：2026-11-11。已归入[统一图标设计稿](https://fanglinwei.github.io/Combo/design/liquid-glass/#central)，与 AppIcon、音频电量和充电状态一起查看。这是待实现的设计，不替代项目当前行为规格。

## 覆盖范围

总表含 49 个条目：网络 5 个，电源与数值 9 个，AirPods 7 个，Beats 11 个，通用音频设备 7 个，AirPlay 与车载 5 个，底部状态 2 个，输出列表参考 3 个。静音与播放用于检查底部符号；内置扬声器、显示器与其他音频输出仅作为输出列表参考，当前没有新增为主圆环中央状态。

## 视觉规则

中央设备与状态符号使用官方 SF Symbols 原图、Medium 字重、单色、等比缩放及统一视觉中心。不镜像、拉伸或重绘 Apple 硬件。充电闪电使用 `bolt.fill`，底部静音使用 `speaker.slash.fill`，电源连接与断开使用官方插头加勾号／叉号符号组合。填充或描边根据资源语义和小尺寸识别选择，Apple HIG 并未要求所有符号都使用填充版。

主圆环保留原有 240° 开口、底部音量圆点与播放音柱结构；不将音频部件的完整圆环和颜色阈值套到 Mac 主圆环。电源提示保留接通与拔出的区别。网络数据不可用使用横杠，不使用问号暗示另一种状态。连接中的图形仅展示静态检查帧，未设计或验证新的连接动画。

电量与音量数字使用系统圆体、无百分号；三位数缩小。总表提供 22pt 原尺寸及放大检查、浅色与深色切换。单个条目可查看符号名称和本机官方目录记录的最低 macOS 版本。

音频页采用后续定稿，统一左右耳、实心盒型、红黄绿阈值、未知值、悬停数字及充电状态，见[音频与充电设计说明](audio.md)。

## 来源与验证边界

来源：[优化耳机电量图标与低电量提示 (3)](codex://threads/01a1ca07-6564-7d40-bce3-3f3afabb99ef)。2026-11-12 仅归档既有稿件，以下为原设计阶段记录，不代表当前原生验收。

- [中央图标状态与符号映射](central-symbols.json)
- [音频与充电设计说明](audio.md)
- [Apple HIG：SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Apple HIG：Icons](https://developer.apple.com/design/human-interface-guidelines/icons)
- [SF Symbols](https://developer.apple.com/sf-symbols/)

49 个条目的符号均通过本机 NSImage 解析并离屏绘制。浏览器检查了条目数量、分组、选中状态更新、图像加载和浅深色切换，无捕获到的控制台错误。合并后已在浏览器确认两个页签可切换，原音频页的 19 个场景入口、左右耳和充电盒圆环正常显示，无捕获到的控制台错误。

未改 Combo 项目源码。未在原生菜单栏验证光学尺寸、实时状态与动效；新型号资源受 macOS 版本限制，资源存在不代表设备识别或电量采集已支持。
