# Combo · 界面与图标设计

面板、设置和引导保留 1.3.0 浏览器设计快照；图标资料包含后续中央图标、音频电量与充电设计。全部使用示例数据，设计编号不代表发布版本，浏览器表现不代替原生验收。当前行为见[产品规格](../../product/behavior.md)，设备能力见[工程文档](../../README.md)。

## 预览与原稿

[打开总设计稿](https://fanglinwei.github.io/Combo/design/liquid-glass/)可切换以下页面。Pages 预览随发布分支更新；本地源稿与线上内容应在发布时分别核验。

| 内容 | 浏览器预览 | 可编辑原稿 |
| --- | --- | --- |
| 总览与三页详情 | [面板](https://fanglinwei.github.io/Combo/design/liquid-glass/combo-panel-liquid-glass.html) | [源稿](sources/combo-panel-liquid-glass.html) |
| 独立设置窗口 | [设置](https://fanglinwei.github.io/Combo/design/liquid-glass/combo-settings-liquid-glass.html) | [源稿](sources/combo-settings-liquid-glass.html) |
| 使用引导 | [引导](https://fanglinwei.github.io/Combo/design/liquid-glass/combo-onboarding-liquid-glass.html) | [源稿](sources/combo-onboarding-liquid-glass.html) |
| AppIcon | [浅深背景与尺寸](https://fanglinwei.github.io/Combo/design/liquid-glass/icons/preview.html) | [SVG 与导出说明](icons/app-icon.md) |
| 中央图标 | [设备与状态](https://fanglinwei.github.io/Combo/design/liquid-glass/icons/central.html) | [源稿](icons/sources/central.html) · [符号说明](icons/central.md) |
| 音频与充电 | [设备、电量与充电场景](https://fanglinwei.github.io/Combo/design/liquid-glass/icons/audio.html) | [源稿](icons/sources/audio.html) · [设计规则](icons/audio.md) |

面板默认展示融合方案，可切换控制中心方案；设置默认展示外观。历史设置稿为 33 种图标效果，当前原生效果目录见[设置规格](../../product/behavior.md#settings)。音频稿的充电信号、双耳合并和键盘交互是设计参考，当前原生差异见[音频实现](../../engineering/audio.md)。

## 配图

中英文 README 共用 [1.3.0 配图](../../assets/ui-1.3.0/README.md)，其中记录截图状态、视口与裁切区域；保留原稿中文，不作为实机截图。

| 总览 · 深色 | 设置 · 浅色 |
| :---: | :---: |
| <img src="../../assets/ui-1.3.0/panel.jpg" width="352" alt="总览面板设计"> | <img src="../../assets/ui-1.3.0/settings.jpg" width="420" alt="浅色设置设计"> |

| 电池详情 | Wi-Fi 详情 | 声音详情 |
| :---: | :---: | :---: |
| <img src="../../assets/ui-1.3.0/battery.jpg" width="260" alt="电池详情设计"> | <img src="../../assets/ui-1.3.0/wifi.jpg" width="260" alt="Wi-Fi 详情设计"> | <img src="../../assets/ui-1.3.0/sound.jpg" width="260" alt="声音详情设计"> |

![使用引导设计](../../assets/ui-1.3.0/onboarding.jpg)

## 设计依据与维护

设计规则见[项目 AGENTS.md](../../../AGENTS.md)，主题与几何复用 `Combo/Views/Theme.swift`。此处只维护设计资料，不重复产品行为和原生实现细节。

- `sources/` 是可编辑 HTML 片段，外层同名 HTML 是 GitHub Pages 使用的完整导出版。设置只维护一份，面板通过 include 标记引用；不要直接修改导出版。
- `icons/` 保存 [AppIcon、中央与音频图标](icons/README.md)。原生所需 AppIcon 尺寸直接生成到资源目录；文档侧只留主稿、共享 PNG 与尺寸预览。
- 图标和壁纸内嵌在稿件中；预览外壳从 unpkg 加载运行库，完全离线使用尚未验证。
- 修改 HTML 后统一导出五页，再检查源稿同步与引导交互；参数是已安装 visualize 的渲染脚本路径：

```sh
python3 docs/design/liquid-glass/render.py <visualize-skill>/scripts/render.py
python3 Tests/Views/DesignAssetsCheck.py
node Tests/Views/OnboardingPrototypeCheck.cjs
```

资源检查不覆盖原生材质、焦点、系统辅助功能或硬件信号；应用构建和视觉验收按项目规则另行执行。
