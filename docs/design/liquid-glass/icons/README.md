# Combo · 图标设计汇总

AppIcon、菜单栏中央图标、音频部件与充电状态统一保存在本目录。浏览器稿使用示例数据，符号资源存在不代表真实设备识别、电量或充电信号已验证。

[打开图标设计汇总](https://fanglinwei.github.io/Combo/design/liquid-glass/#central) · [返回总设计稿](https://fanglinwei.github.io/Combo/design/liquid-glass/)

| 内容 | 浏览器预览 | 可编辑原稿与说明 |
| --- | --- | --- |
| AppIcon | [浅深背景与尺寸](https://fanglinwei.github.io/Combo/design/liquid-glass/icons/preview.html) | [SVG 主稿](combo-app-icon.svg) · [设计与导出说明](app-icon.md) |
| 中央图标 | [49 个设备与状态](https://fanglinwei.github.io/Combo/design/liquid-glass/icons/central.html) | [HTML 源稿](sources/central.html) · [设计说明](central.md) · [符号映射](central-symbols.json) |
| 音频与充电 | [39 个设备、电量与充电场景](https://fanglinwei.github.io/Combo/design/liquid-glass/icons/audio.html) | [HTML 源稿](sources/audio.html) · [定稿规则](audio.md) · [音频符号映射](audio-symbols.json) |

中央图标包含网络、电源接通／拔出、Mac 充电提示、数值、AirPods、Beats、通用音频、AirPlay、车载及底部状态。音频页包含左右耳和实心充电盒、单电池设备、电量阈值、未知态、双耳合并充电、单耳充电、空盒充电和确认充满；浏览器音频稿支持悬停或键盘聚焦显示无百分号数字。原生圆环总览与详情均为 40pt，悬停显示数字、点击切换数字显示，不获取键盘焦点；实时行为见[音频实现说明](../../../engineering/audio.md)。

充电设计规则与当前原生采集边界统一见[音频设计](audio.md)及[工程说明](../../../engineering/audio.md)。

## 来源与维护

- HTML 源稿内保留现有 SF Symbols 离屏图像；只收录最终独立源稿，不复制聊天目录中的重复合集、临时渲染文件和截图。
- 修改 HTML 后按[统一导出步骤](../README.md#设计依据与维护)生成浏览器版；AppIcon 按[图标导出说明](app-icon.md#更新方式)维护。

目录数量按用途分别统计：中央稿 49 项、音频稿 39 个场景、音频映射 25 类设备；原生设置将设备和状态展开为 51 种效果，数量不要求相同。真实设备识别、电量与充电信号仍需独立验证，不能由设计素材推断硬件支持。
