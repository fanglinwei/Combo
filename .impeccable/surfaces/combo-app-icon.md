---
version: 1
slug: combo-app-icon
primary_target: docs/assets/brand/liquid-glass/combo-app-icon.svg
related_targets: [docs/assets/brand/liquid-glass/preview.png]
---
# Combo 应用图标

用户已确认当前稿作为新的 AppIcon，覆盖原生图标资源及当前品牌／设计预览引用。实时菜单栏图标保持原有功能。沿用现有图标结构，重做风格；底部四个圆点改为音乐动态柱体。此前 C 包围三个功能符号的方案被否定，已删除。

## Direction contract

THESIS: 用现有电量弧、Wi-Fi 和底部音乐柱体融成一个标志，保持品牌识别和三合一产品含义。

OWN-WORLD: 用户已否定石墨及多色高光；当前为清透蓝底与统一白色玻璃标志，仅保留柔和落影和细边缘光，保持简洁。

STORY: 先认出熟悉的 Combo 轮廓，再看到四个圆点变成高低错落的音乐柱体；外弧指代电量，双弧指代网络，音乐柱体指代声音。

FIRST VIEWPORT: 1024px 透明画布，824px 蓝色圆角底座；中央沿用原标志，四条音乐柱体沿用 App 播放态的圆弧排列，宽度采用 C 的 5.4、圆角 2.7，柱长经视觉调整为 16、23、19.5、15.5，使与两侧外弧的衔接更平缓。预览含浅深背景和 16、32、64、128、256px 尺寸。

FORM: 对已确定视觉体系做图标延伸，使用项目原生 SVG 图形。seed: none (user-pinned direction).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

2026-11-06 用户补充：柱体须像 App 内一样呈圆弧；以 IconRenderer.swift 四柱位置为准，柱体竖直，左右上提、中间下沉，不添加旋转。

2026-11-06 最新反馈：否定多色玻璃和繁复高光，要求简洁。移除多色、柱体反光条及装饰线；统一蓝白配色。

2026-11-06：用户要求只调整柱体长度，过渡更平缓；保留 App 的弧形位置与宽度，缩短两侧、适当加长中间柱。

用户选定 D。当前修订保留其高低节奏，并参考 IconRenderer 的固定底沿、圆头及向上伸缩方式，延长侧柱并缓和高差。底沿仍为 80.4、85.4、85.4、80.4；长度 16、23、19.5、15.5。

外弧修整：圆心 `(50,48)`、半径 34、146°至394°，弧宽 6.8 与柱宽统一；端点略向内下方延伸，保留圆头。

最新外弧：保留上部圆形，左右下段改为与主圆相切的短 Bézier 曲线，末端转为竖直切向，坐标 `(22.2,67.5)` 与 `(77.8,67.5)`。尾部与柱体方向更一致；宽度、圆头、Wi-Fi 和音乐柱保持不变。此前 146°/394° 的纯圆端点为历史版本。

最新要求：采用 D 的高低节奏与平缓过渡，柱宽参考 C。四柱宽 5.4、圆角 2.7，原中心、长度和底沿保持不变；外弧保留已有相切 Bézier 收尾，不重置为候选文件中的旧圆弧。

最新用户要求优先：不保留平缓外弧收尾。恢复原始圆弧 `M20.6 65 A34 34 0 1 1 79.4 65`，弧宽 6，去掉额外 Bézier 尾部；保留 D 的柱长与 C 的细度。前述外弧尾部记录为历史版本。
