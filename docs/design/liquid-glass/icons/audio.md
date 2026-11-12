# Combo 音频设备显示设计稿

定稿日期：2026-11-11；归档日期：2026-11-12。用于设计评审与后续实现交接；预览全部使用示例数据。

## 显示范围

展示蓝牙音频设备及其有电池的充电盒：AirPods、AirPods Pro、AirPods Max、Beats、通用蓝牙耳机、便携蓝牙音箱和可上报音频设备电量的助听设备。键盘、鼠标、触控板、HomePod、Apple TV 不在范围内。

总览展示当前音频设备的电量。进入声音详情后，继续使用相同设备、数据和状态；入盒充电后，即使音频输出断开，也应保留可确认的新鲜电量信息。设备关联和信号采集属于后续实现范围。

## 最终布局

- 总览：保留现有音量控制，在下方居中排列设备圆环。左右独立电量按「左耳、右耳、充电盒」顺序；没有电池的部件不占位。
- 声音详情：设备图标与名称位于上方；下方显示放大的同一组圆环。不重复添加百分比行、状态卡片或进度条。
- 已确认双耳都在盒内且同时充电时，合并为「双耳、充电盒」两环。单耳充电时左右分开，仅对应耳显示闪电。空盒充电且没有可展示的耳机数据时，只显示盒环；若仍有盒外耳机的新鲜电量数据，保留其左右环，不因盒子为空而隐藏。
- 单一电池设备显示一个居中圆环；没有左右独立数据时，不虚构左右电量。
- 长设备名尾部省略，提供完整名称提示与辅助功能名称；所有状态切换保持圆环中心、尺寸与排列稳定。

## 电量、图标与悬停

| 内容 | 定稿规则 |
|---|---|
| 默认 | 圆环表示电量；内部显示对应设备、左耳、右耳或实心充电盒图标 |
| 0–20 | 红色，包含 20 |
| 21–40 | 黄色，包含 40 |
| 41–100 | 绿色 |
| 悬停 | 仅将环内图标替换为纯数字，如 `23`、`100`，不带 `%`；圆环和闪电保持原位 |
| 键盘与触控 | 键盘聚焦显示数字；点击或空格可切换数字与图标；辅助功能始终读出部件、百分比和状态 |
| 0 | 不画有色进度弧；悬停显示 `0`，不能当成未知 |
| 已知部件、值未知 | 灰色底环，中心常显 `—`，不显示虚构的 0 或有色进度 |
| 无电池或不适用部件 | 不显示该环；例如 Beats Solo Buds 的盒无内置电池 |
| 已过期数据 | 不以旧值冒充当前值；保留槽位时使用未知态，详情说明暂不可用 |

合并双耳的圆环与悬停数字取左右有效电量的较低值，避免平均值掩盖低电量。这是本次补齐的设计取值规则。任一耳电量未知、入盒状态不明、或一耳充满另一耳仍充电时，保留分耳显示。没有明确入盒信号时，不仅凭两耳电量相同或都显示充电就推断合并。

## 充电状态

闪电使用已确认参考稿中的 `bolt.fill` 资源与贴合轮廓的深色描边，嵌在圆环正上方，切开圆环；不使用圆形底座，不移到右下角。描边在浅色和深色下均保留。

| 场景 | 圆环与闪电 |
|---|---|
| 正常使用 | 左、右、盒分别显示，无闪电 |
| 双耳在盒内充电 | 双耳合并一环，顶部白色闪电；盒独立一环 |
| 双耳与盒同时充电 | 双耳环和盒环各自显示白色闪电 |
| 仅左耳或右耳充电 | 保留左右耳；仅充电的一耳显示白色闪电 |
| 空盒接电充电 | 盒环顶部白色闪电；耳机有新鲜数据时仍可展示 |
| 一耳充满、一耳充电 | 左右分开；已满耳绿色闪电，充电耳白色闪电 |
| 明确确认充满 | 对应部件的闪电变绿，保留深色描边 |
| 100，未充电或状态未知 | 不显示闪电；100 本身不能证明充满状态 |
| 其他蓝牙音频设备充电 | 整机环顶部白色闪电；确认充满后绿色 |

耳机、左右耳和充电盒的充电标志分别判断。环色始终只表示电量档位，闪电只表示充电状态；不得根据电量上涨、达到 100 或充电盒接电，推断其他部件在充电。

## 视觉参数

沿用 Combo 原有视觉语言和已确认预览参数，原生实现复用 Theme 中对应定义。

| 参数 | 设计值 |
|---|---|
| 总览环直径 | 44 pt |
| 详情环直径 | 64 pt |
| 进度起点和方向 | 12 点钟起，顺时针 |
| 线宽与端点 | 基于 82 坐标的 5.7 线宽，约直径的 6.95%；圆角端点 |
| 红 / 绿 | `#FF3B41` / `#28CD50`，沿用前稿核对的 Combo 配色 |
| 黄 | 浅色 `#906600`，深色 `#FFD60A` |
| 底环 | 浅色 `#A7AAB3`，深色 `#565961` |
| 设备图标 | 单色，维持官方原始比例；用光学尺寸平衡宽盒与细长单耳 |
| 数字 | 系统圆体、等宽数字；100 使用较小字号，不能挤出环内 |
| 闪电位置和大小 | 水平居中；顶部约为环直径的 −10.9%；宽约 24%，高约 34% |
| 交互切换 | 图标与数字约 100 ms 淡变；减少动态效果下直接切换，无循环动画 |

上述是浏览器稿的尺寸基准，最终 SwiftUI/AppKit 需要以原生点尺寸进行光学校准。颜色档位属于本项目已确认设计，并非声称 Apple HIG 强制规定这些阈值。

## 图标匹配原则

已知品牌、型号和代数时使用配套的整机、左右耳及盒型。AirPods 普通款与 Pro 单耳不得混用；不同代数按官方资源区分。盒子使用官方 `.fill` 变体，匹配系统蓝牙电量行的小图形，不拿设备行的大幅产品图片替代。

未知型号使用语义正确的通用耳机图标；不靠改设备名或猜名称匹配成 AirPods。系统缺少专用符号时，使用语义正确的可用通用资源，保持左／右的文字与辅助功能标识，不镜像、拉伸或手绘苹果硬件图标。符号资源存在不代表设备有电池、可识别或可读取。

## 验收与实现边界

设计预览覆盖总览、详情、各类图标、单耳和双耳充电、空盒充电、确认充满、单电池设备充电、阈值及未知态。以下项目是原生实现的验收要求：

- 电量边界 0、20、21、40、41、100 与未知值；数字无百分号。
- 总览和详情的同一设备状态一致；每个部件的闪电相互独立。
- 双耳合并的取值与拆分条件；盒外仍有新鲜电量时不丢失展示。
- 浅色、深色、减少动态效果、减少透明度、增强对比度、长名称、鼠标及键盘辅助功能。
- 各代设备识别、真实充电信号、开合盖与休眠后的更新及时性、数据过期判定。

本次只整理设计稿与预览；未修改 Combo 源码。前稿引用的系统数据与开源采集实现不能替代 Combo 本机验证，也不能保证所有设备都会上报充电信号。

## 原设计阶段预览验证

以下为原聊天的历史检查记录；本次归档不据此声明原生界面或设备采集已验收。

已在浏览器深色外观查看总览、详情、双耳合并充电和数字切换；检查 39 个场景均生成圆环，164 个圆环均有图标资源引用，包含 18 个充电中标记、8 个充满标记和 2 个未知电量槽位。电量阈值自检与机械设计检查通过。

未逐场景目视核对；浅色外观、窄宽度、系统辅助功能及原生 SwiftUI/AppKit 尚未验证。

## 来源

- [统一图标设计入口](../index.html#audio)
- [音频与充电预览](audio.html)
- [可编辑源稿](sources/audio.html)
- [25 类音频设备符号映射](audio-symbols.json)
- [汇总音频设备显示设计稿](codex://threads/01a1ca08-c30b-7bd1-bfcf-8130d29f94b7)

- [音频图标汇总](codex://threads/01a1c9fb-2a79-7670-9d29-ee059b1f712e)：最终型号映射、实心盒型、官方资源与版本表。
- [电量状态](codex://threads/01a1c9c3-01c4-7ee1-b832-c45e84de8dae)：最终阈值、圆环、悬停数字、充电闪电、合并与拆分状态。
- [Apple HIG — SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Apple HIG — Icons](https://developer.apple.com/design/human-interface-guidelines/icons)
- [SF Symbols 官方资源](https://developer.apple.com/sf-symbols/)

以下资源表继承图标汇总稿的本机系统目录核对结果。最低系统版本仅指资源可用性，不表示设备采集能力；较新符号仍需在目标部署系统验证并提供通用资源降级。

| 设备 | 设备符号 | 左耳 | 右耳 | 盒子 | 最低 macOS（同序） |
|---|---|---|---|---|---|
| AirPods 1/2 | `airpods` | `airpod.left` | `airpod.right` | `airpods.chargingcase.fill` | 11.0 / 11.0 / 11.0 / 12.0 |
| AirPods 3 | `airpods.gen3` | `airpod.gen3.left` | `airpod.gen3.right` | `airpods.gen3.chargingcase.wireless.fill` | 12.1 / 12.1 / 12.1 / 12.1 |
| AirPods 4 | `airpods.gen4` | `airpods.gen4.left` | `airpods.gen4.right` | `airpods.gen4.chargingcase.wireless.fill` | 15.2 / 15.2 / 15.2 / 15.2 |
| AirPods Pro 1 | `airpods.pro.gen1` | `airpods.pro.gen1.left` | `airpods.pro.gen1.right` | `airpods.pro.gen1.chargingcase.wireless.fill` | 27.0 / 27.0 / 27.0 / 27.0 |
| AirPods Pro 2 | `airpods.pro` | `airpods.pro.left` | `airpods.pro.right` | `airpods.pro.chargingcase.wireless.fill` | 15.0 / 15.0 / 15.0 / 15.0 |
| AirPods Pro 3 | `airpods.pro.gen3` | `airpods.pro.gen3.left` | `airpods.pro.gen3.right` | `airpods.pro.gen3.chargingcase.wireless.fill` | 27.0 / 27.0 / 27.0 / 27.0 |
| AirPods Max | `airpods.max` | — | — | — | 15.0 / — / — / — |
| Powerbeats Pro | `beats.powerbeats.pro` | `beats.powerbeats.pro.left` | `beats.powerbeats.pro.right` | `beats.powerbeats.pro.chargingcase.fill` | 15.0 / 15.0 / 15.0 / 15.0 |
| Powerbeats Pro 2 | `beats.powerbeats.pro.2` | `beats.powerbeats.pro.2.left` | `beats.powerbeats.pro.2.right` | `beats.powerbeats.pro.2.chargingcase.fill` | 15.5 / 15.5 / 15.5 / 15.5 |
| Beats Fit Pro | `beats.fitpro` | `beats.fitpro.left` | `beats.fitpro.right` | `beats.fitpro.chargingcase.fill` | 14.0 / 14.0 / 14.0 / 14.0 |
| Beats Studio Buds | `beats.studiobuds` | `beats.studiobuds.left` | `beats.studiobuds.right` | `beats.studiobuds.chargingcase.fill` | 12.0 / 15.0 / 15.0 / 12.0 |
| Beats Studio Buds + | `beats.studiobuds.plus` | `beats.studiobuds.plus.left` | `beats.studiobuds.plus.right` | `beats.studiobuds.plus.chargingcase.fill` | 15.0 / 15.0 / 15.0 / 15.0 |
| Beats Solo Buds | `beats.solobuds` | `beats.solobuds.left` | `beats.solobuds.right` | `beats.solobuds.chargingcase.fill` | 14.6 / 14.6 / 14.6 / 14.6 |
| Beats 头戴式 | `beats.headphones` | — | — | — | 12.0 / — / — / — |
| Beats 颈挂式 | `beats.earphones` | — | — | — | 12.0 / — / — / — |
| Powerbeats | `beats.powerbeats` | `beats.powerbeats.left` | `beats.powerbeats.right` | — | 12.0 / 13.3 / 13.3 / — |
| Powerbeats 3 | `beats.powerbeats3` | `beats.powerbeats3.left` | `beats.powerbeats3.right` | — | 12.0 / 13.3 / 13.3 / — |
| Beats Pill | `beats.pill.fill` | — | — | — | 14.6 / — / — / — |
| 通用头戴式 | `headphones` | — | — | — | 10.15 / — / — / — |
| 通用真无线 | `earbuds` | `earbud.left` | `earbud.right` | `earbuds.case.fill` | 12.0 / 26.0 / 26.0 / 12.0 |
| 通用入耳式 | `earbuds.in.ear` | `earbuds.in.ear.left` | `earbuds.in.ear.right` | `earbuds.case.fill` | 26.0 / 26.0 / 26.0 / 12.0 |
| 通用无柄式 | `earbuds.stemless` | `earbuds.stemless.left` | `earbuds.stemless.right` | `earbuds.case.fill` | 26.0 / 26.0 / 26.0 / 12.0 |
| 通用骨传导 | `earbuds.bone.conduction` | `earbuds.bone.conduction.left` | `earbuds.bone.conduction.right` | — | 26.0 / 26.0 / 26.0 / — |
| 助听设备 | `hearingdevice.ear` | — | — | — | 12.0 / — / — / — |
| 通用蓝牙音箱 | `hifispeaker.fill` | — | — | — | 10.15 / — / — / — |
