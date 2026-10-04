# Combo 开发历史

整理：2026-10-04。本文保留里程碑、已知失败和验证范围，原重复 README 功能清单、失效编译命令及临时构建截图路径已精简。完整旧 README 可从 [提交 b283bf7](https://github.com/fanglinwei/Combo/blob/b283bf7385cf54ece625f82b277177b0917df9bb/README.md)追溯。

使用说明见 [English README](../README.md) / [中文 README](../README.zh-CN.md)，当前行为见 [文档总览](README.md)。历史构建通过或界面采样不表示本次重新验收。

## 2026-09-22：首版范围与技术研究

确定 MacBook 电池、网络路径、音量与固定播放动效的组合入口，外圈使用本机电量。分别研究路径/RSSI 权限、播放器状态、耳机与手机电量、手动隐藏系统菜单项。

此阶段“不扫描 Wi-Fi”“未接入 AirPods 电量”“浏览器扩展/Apple Events 首版适配”已被后续实现取代。有效 API 事实保留于各主题文档；手机及关联设备外圈仍为 [后续规划](combo-roadmap.md)。

## 2026-09-23：授权与自动折叠实验

0.2 预览曾通过电池/音量/网络只读采样和事件注册；没有据此确认所有硬件与 macOS 26。辅助功能引导提供系统设置、重新检查和稍后再说，授权不自动开始扫描。

系统权限开关开启而 `AXIsProcessTrusted` 仍为 false 时，重新启动未解决。ad-hoc designated requirement 与 cdhash 变化是可能原因，未读取 TCC 证明唯一根因；固定当前运行路径重新授权是排查方向，不重置全局权限。签名依据：[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

授权后旧 AX 根入口返回 NoValue，后续 MenuBarAgent 找到系统项；私有单项折叠最终也隐藏 Combo，自身恢复入口不可靠，实验暂停。方案、失败证据与验收条件统一见 [菜单栏研究](menu-bar-hiding-research.md)。

## 2026-09-24：电池、Wi-Fi、热点与声音面板

- [电池](battery-controls.md)：补齐供电与有效上限；适配器能耗模式 0→1→0 写入回读，未改电池模式。临时解除手动上限开始充电，优化充电不变，试验后恢复 80% 上限；固定恢复时刻不作产品承诺。
- [高耗能应用](battery-controls.md#高耗能应用)：查明 ControlCenter 同源私有数据源并接入；空状态有相邻对照，非空顺序与后台/扩展筛选仍未完整验收。
- [Wi-Fi](network-implementation-evidence.md)：接入普通网络列表、定位、扫描/连接与钥匙串偏好；示例与规则检查通过，真实网络切换和系统密码授权未完成完整验收。
- [个人热点](mobile-hotspot-api-feasibility.md)：Sharing 私有发现读到手机名称、电量与蜂窝等级，点击打开系统 Wi-Fi 设置，未连接热点；仅支持已验证 build `26A428`。
- [AirPods](airpods-audio-feasibility.md)：左右耳电量、通透/自适应/降噪与对话感知往返读写通过，恢复原设置；关闭模式和空间音频写入未确认，最终空间音频不监控。

## 后续声音与图标迭代

声音高级选项从列表/Switch 收敛为胶囊分段；后台轮询与写入 busy 分开，消除定时变灰；待确认选中值与真实快照分开，失败回退；加入点击/水平拖动，模拟 helper 验证每次提交一次请求。真实硬件、键盘与动画逐帧边界见声音文档。

2026-09-29 绘制 [19 个状态 GIF](combo-current-states.md)：16 场景及连接成功/失败、取消静音；资源使用应用共享绘图和演示数据，不改变系统。旧设计几何与原生对照图仍是历史素材，当前时序以设置规格为准。

## 2026-10-03：蓝牙、AirPlay 与设置

[蓝牙分类](bluetooth-audio-device-icon-research.md)统一 CoreAudio transport、品牌/CoD/通用名称顺序，复用已授权 helper 身份；配对表不能作为当前输出，精确型号仍有限。

[AirPlay](airplay-homepod-icon-research.md)建立当前路由名称/机型读取和 opt-in Bonjour 发现；历史 Apple TV 路由得到“客厅”/`AppleTV14,1`，无 HomePod。异步 token/取消/超时、生命周期和模拟授权保护的自动检查通过；真实弹窗与多设备/旧系统待验收。发现结果点击仍转交系统声音设置。

[设置](combo-settings.md)六页、主题/外观、窗口预览与菜单栏演示、低电量默认 20% 及旧值迁移、完整系统图标基线与确认恢复已实现。历史 144 个标准离屏渲染加补充样本、原生窗口六页/滚动/演示/无效输入/确认取消检查通过；VoiceOver、全键盘与真实权限恢复仍未完整验收。

品牌当前为天空蓝，依据 [品牌资源](assets/brand/README.md)；早期绿色品牌与旧设置页名称不再作为现行规格。

## 2026-10-04：文档整理

按主题合并证据与实现，更新网络、媒体、AirPods 和菜单栏过期范围；删除 9 份被替代的独立笔记，合并映射见 [总览](README.md#本次合并与删除记录)。日常验证入口为 `./verify.sh`，旧拼接源码的 live-state 编译命令已失效，不再作为操作步骤保留。
