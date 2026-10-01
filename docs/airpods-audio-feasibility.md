# 声音面板与 AirPods 实现及验证

调研与实机读取验证日期：2026-09-24。

## 已确定范围

用户选择推荐方向：macOS 原生、自用原型；先验证音量、输出切换、AirPods 电量、聆听模式、对话感知。空间音频与 AirPlay 完整控制单独研究。

后续按用户“按计划执行，高级功能能实现尽量实现”的指示，已将电量、通透/自适应/降噪、对话感知接入 Combo 声音面板。初始只读探针已清理，真实切换验证脚本仍保留；所有测试操作均已恢复原耳机设置。没有执行 Git 写操作。

实现入口：`Combo/Audio/AirPodsHelper.m`、`Combo/Audio/AirPodsContext.c`、`Combo/Audio/AirPodsControl.swift`、`Combo/Views/SoundSections.swift` 中的 `AirPodsSection`。`Combo/Audio/AudioVolume.swift` 提供主通道/左右声道回退，供 AudioStore 读写与事件监听共用。

## 结论

本机核心读写路径已验证。基础声音控制复用 Combo；AirPods 控制使用独立的短生命周期 helper 和进程内私有接口适配。写操作包含设备身份复查、1.5 秒回读确认；失败或超时不显示成功。不将本机验证外推至其它 macOS 版本或耳机型号。

| 功能 | 证据 | 结论 |
| --- | --- | --- |
| 设备枚举、默认输出切换 | Combo/Stores/AudioStore.swift 中的 refreshOutputs / setOutput，CoreAudio 公开接口 | 复用现有实现；本轮没有切换输出 |
| 音量、静音 | 本机 CoreAudio 属性查询 | 已实现左右声道回退、读写与监听；主通道音量不可读时仍可使用滑块 |
| 电量 | IOBluetoothDevice 私有 getter 实际返回左右耳电量 | 可读；盒子休眠/零值/不支持统一保留未知，不能伪装成实时 0% |
| 聆听模式 | AVOutputDevice 实际写入与独立进程回读 | 降噪→通透→降噪、降噪→自适应→降噪均成功；面板提供这三种模式 |
| 对话感知 | 私有 AVOutputDevice 实际写入与独立进程回读 | 关闭→开启→关闭成功；面板开关已接入 |
| 空间音频 | 按用户要求不监控 | 已移除查询、数据字段和展示 |
| AirPlay / 电视 | 开源项目 Bonjour 发现 + 系统菜单自动化 | 发现与建立音频路由分开验证；当前原型不覆盖 |

## 本机观测

- macOS 27.0，Build 26A428。
- 当前连接耳机的产品 ID 为 0x2027；按 airpods-control 的兼容表对应 AirPods Pro 3。型号映射来自社区资料，不把名称作为能力判断依据。
- 探针采样：左耳 43%、右耳 34%，充电盒未知。数值仅代表采样时刻。
- 默认输出静音为 0；左右声道音量分别为 0.3125、0.31249994。主通道读取返回 OSStatus 2003332927。
- HAL `lstm = 2`，`lsms = 7`；只保留原始观测，不猜测完整枚举或位掩码定义。
- **无进程内适配时**：共享系统音频上下文不可用，模式与对话感知返回 null。
- **有进程内适配时**：上下文和当前输出可用；模式为 `AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation`，可用列表包含 Normal / ActiveNoiseCancellation / AudioTransparency / Automatic；对话感知支持为 true、开启状态为 false。
- 本机只连接一副蓝牙耳机。生产 helper 用 IOBluetoothDevice.outputAudioDeviceID 精确匹配默认输出；通过 associatedAudioDeviceID + CoreAudio UID translation 将 AV 上下文映射到同一个输出。UI 写请求还携带设备 ID 和 UID 的 SHA-256 摘要，不按名称匹配。多耳机实机验证仍待补充。

## 高级功能实测边界

- “关闭聆听模式”：虽然系统能力列表包含 Normal，但本机写入未被独立回读确认；原状态恢复成功。截图本身也没有该项，因此面板暂不提供关闭选项。helper 保留 allowlist/回读支持，不把 API 返回成功当成设置成功。
- 空间音频：本机 `supportsHeadTrackedSpatialAudio=true`，模式为 Automatic。`setAllowsHeadTrackedSpatialAudio:NO` 以及模式 Never / Always / MultichannelOnly 均未产生可确认的持久变化；Automatic 同值写入不能算切换验证。初版移除这些写入口，仅保留读取；后续按用户要求进一步移除所有空间音频读取与展示。所有试验后确认仍为原 Automatic、允许状态 true。
- AirPlay：AVOutputDeviceDiscoverySession 的 Audio feature 发现会话可创建，但本机 5 秒发现返回 0 个设备；未确认授权/PIN 流程与连接 completion ABI。未把未知 setter 拼装进产品，仍从“声音设置 / AirPods”进入系统设置。

## 实现行为与验证

- 只在面板可见、屏幕活动且为本机状态时，每 3 秒读取一次；关闭面板/睡眠/换设备会取消请求并清除旧快照。
- 写入时禁用重复操作；写前核对当前 CoreAudio ID、UID 摘要、AV 端点，写后持续核对路由及返回状态。设备变化、helper 失败、超时、未确认设置都会显示失败/重试状态。
- 充电盒读不到时不显示伪造的 0%；多个电量字段独立显示。不监控或展示空间音频状态。
- `./build.sh` 已通过现有全部检查、新增 AirPods/声道测试、应用编译与签名校验。验证产物：`build/airpods-panel/Combo.app`。
- 独立窗口实际点击通透模式后，选中状态与耳机一致且无错误提示，随后恢复降噪；音量滑块显示实际声道音量。GUI 期间发现并修复 JSON 布尔被编码为数字的问题，实机脚本现检查布尔类型。
- `Tests/AirPodsCheck.swift` 覆盖音量声道选择、异常电量/状态、重复操作、未确认写入、旧设备、损坏 JSON、进程失败、超时与取消。
- `Tests/airpods-live-check.py --write` 验证过期 token 在写前被拒绝，以及通透/自适应/对话感知真实变化和逐项恢复；最终保留功能全部通过。空间音频与 Off 的失败试验单独记录于上文，没有纳入通过结论。

```sh
# 默认只读；--write 才会短暂更改耳机设置并逐项恢复。
python3 Tests/airpods-live-check.py build/airpods-panel/Combo.app
python3 Tests/airpods-live-check.py build/airpods-panel/Combo.app --write
```

## 早期探针记录

独立只读探针已从仓库清理；当前验证入口是上文的 `./build.sh` 和 `Tests/airpods-live-check.py`。原探针输出 JSON，不输出蓝牙地址、序列号、设备名称；null 表示未知/不可读，不能转成关闭、0% 或不支持。自检曾覆盖电量类型、范围、未知值，以及不存在的 getter，并完成普通/适配两种实机读取。

正式实现中的 [AirPodsContext.c](../Combo/Audio/AirPodsContext.c) 仅为新启动的 helper 进程适配私有 entitlement 查询，其余查询转给原函数。不注入系统进程，不修改 SIP，也不安装到 /Applications。应用内 helper 的本地 ad-hoc 打包与运行已验证；尚未验证 Developer ID、公证或沙盒分发。

## GitHub 来源与可复用内容

1. [AudioSwitch](https://github.com/iamzifei/audioswitch)（MIT）：基础设备面板；[VolumeController.swift](https://github.com/iamzifei/audioswitch/blob/main/Sources/AudioSwitchCore/VolumeController.swift) 展示主通道/声道回退与可写检查。Combo 已有相关逻辑，不需要引入整个应用。
2. [switchaudio-osx](https://github.com/deweller/switchaudio-osx)（MIT）：CoreAudio 设备切换参考；本轮无需安装。
3. [airpods-control](https://github.com/raulgg/airpods-control)（MIT）：[PrivateAudio.swift](https://github.com/raulgg/airpods-control/blob/main/Sources/AirPodsControl/PrivateAudio.swift) 提供私有类、selector、模式字符串与写后回读参考。[兼容矩阵](https://github.com/raulgg/airpods-control/blob/main/docs/compatibility.md) 将 Pro 3 和 Pro 2 Lightning 的模式/对话感知读写列为已验证；这属于上游结果，不是本轮写入测试。
4. [airpods-control 安全模型](https://github.com/raulgg/airpods-control/blob/main/SECURITY.md)：解释本进程 interpose `SecTaskCopyValueForEntitlement` 与 `com.apple.avfoundation.allow-system-wide-context`。本轮用独立的小型探针验证该机制。
5. [Hammerspoon 电量源码](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/battery/libbattery.m)：私有 `batteryPercentLeft/Right/Case/Single` 读取；注释说明充电盒休眠等局限。未采用含义不确定的 Combined 值作为截图中的单一百分比。
6. [AirBattery](https://github.com/lihaoyun6/AirBattery)：电量产品参考，BLE 等采集路径与私有 getter 并不相同；本轮没有移植该项目。
7. [airplay-cli](https://github.com/bpetrynski/airplay-cli)：Bonjour 发现，AppleScript 操作声音菜单完成切换；不是通用公开路由控制 API。
8. [atmos-control](https://github.com/yukij3/atmos-control)：捕获音频并使用 AUSpatialMixer 渲染；要求关闭系统空间音频以免重复处理，不能作为截图系统开关可直接控制的证据。

来源为调研当日 GitHub 页面与源码，未固定上游 commit。终端直接下载 GitHub 超时，未安装或执行上游项目。探针代码独立编写，以本机编译输出为实测依据。

## 后续边界

1. 私有接口可能随系统更新失效；升级系统后重跑只读及自愿写入验证。
2. 多设备、断连重连的真实硬件覆盖仍待补充，已有设备身份防护及旧请求取消测试。
3. 暂不实现空间音频自建渲染、AirPlay 菜单自动化或全版本兼容层。

## 声音区域样式调整（2026-09-24）

使用真实 CoreAudio 输出列表与耳机状态；不按参考截图硬编码设备名称或电量。

| 区域 | 原界面 → 当前界面 |
| --- | --- |
| 输出设备 | 下拉菜单 → 32 pt 最小行高的设备列表，26 pt 圆形图标，选中设备为蓝色 |
| 耳机电量 | 独立文本 → 设备名称下的左右耳图标与电量，保留可读到的充电盒电量 |
| 聆听模式 | 圆形选择标记 → 独立勾选列、系统聆听图标和文字，25 pt 最小行高 |
| 对话感知 | Switch → 关闭/打开两行，选中项显示勾选 |
| 展开区 | 无折叠 → 默认展开，右侧箭头可收起；其他输出设备不显示耳机高级选项 |
| 空间音频 | 只读监控 → 删除 helper 查询、Swift 数据字段与界面 |

尺寸按参考截图约 2× 像素密度估算，保持 Combo 现有 340 pt 面板宽度。选项区局部浅灰底色，字体沿用系统字体；三种聆听图标取自系统私有符号资源，缺失时回退到公共人物图标。电量仍在收起状态刷新，面板关闭时停止轮询。

本轮验证：`build.sh` 构建及现有检查全部通过；`Tests/airpods-live-check.py build/audio-style/Combo.app --write` 通过通透、自适应、对话感知切换、过期目标拒绝及逐项恢复，并检查 JSON 不含空间音频字段。原降噪/对话感知关闭状态已恢复。原生窗口验证了默认展开、点击收起与重新展开、收起保留电量和选中状态的辅助功能描述。Tab 焦点在当前本机设置下未进入按钮，未宣称完成键盘遍历验收；按钮继续使用 SwiftUI 原生 Button。

输出顺序保持原来的名称排序，因此与截图中的设备先后顺序不同；玻璃背景随宿主窗口变化。修改前后截图：`build/audio-style/before.png`、`after.png`，并排对照：`comparison.png`。

本轮只修改 `Combo/Views.swift`（原生 SwiftUI 列表/按钮）、`Combo/Store.swift`（设备图标分类）、`Combo/AirPodsControl.swift` 和 `Combo/AirPodsHelper.m`（移除空间音频）；同步更新两份现有 AirPods 检查及 README/本文。保留仓库原有其他改动，未进行 Git 写操作。本轮独立差异保存于 `build/audio-style/task.diff`。

## 胶囊切换与边界修正

按后续确认，聆听模式改为三段、对话感知改为两段：图标在胶囊内，名称在下方；选中项使用蓝底白图标。输出设备行增加整行浅灰圆角悬浮背景，未选中分段增加局部悬浮高亮。底轨根据列数和 62 pt 按钮宽度收进，仅比首尾按钮各多 2 pt 边框留白，按钮与文字位置不变。所有布局改动位于 `Combo/Views.swift`，继续复用真实读取/写入流程。

构建及现有检查通过；原生界面实测自适应模式和对话感知打开后选中状态正确回读，已恢复降噪/对话感知关闭。边界调整后的应用再次编译通过，并核对截图 `build/audio-segments/controls.png`，边界前后对照为 `bounds-comparison.png`。悬浮使用 SwiftUI `onHover`，当前自动化未取得稳定的纯悬浮截图，不计入视觉验证通过项。未进行 Git 写操作。

## 定时刷新闪烁修复

原因：面板每 3 秒读取一次耳机状态，读取和用户写操作共用 `busy`，而控件用它决定是否禁用，导致正常轮询也会使整个区域短暂变灰。`AirPodsControl` 现将后台读取与用户写操作区分：只有写操作设置可观察的 `busy`；相同的状态回读不再发布更新；用户点击可取消正在执行的只读查询并优先写入，旧进程回调仍按身份丢弃。后台失败仍保留原来的不可用提示。

在 `Tests/AirPodsCheck.swift` 增加了后台查询不禁用、连续相同回读零界面通知、查询期间写入优先级和重复写保护检查。修复前断言失败，修复后通过。

## 选中胶囊滑动动画

聆听模式和对话感知使用同一条轨道中的单个蓝色选中胶囊，以 220 ms ease-in-out 平移；图标与文字位置固定，减少动态效果开启时不动画。`AirPodsControl` 维护独立的待确认选中值，点击立即移动，真实设备快照仍保留上次确认值；拒绝、失败和超时清除待确认值并回退，设备变化/面板关闭时取消待确认状态。重复点击被拒绝，后台轮询仍保持静默。

现有 AirPods 检查覆盖立即显示目标但不篡改真实快照、确认成功清理待确认值、重复写保护、失败回退、超时回退、取消，以及此前的静默轮询检查，均通过。完整构建通过，最终辅助功能文字调整后再次编译通过。原生面板已验证聆听模式在等待回读期间先移动到自适应位置并标记“正在切换”，确认后保持；随后请求恢复降噪。验证期间当前输出变为内置扬声器，未重新选择耳机或继续对话感知实机切换。对话感知待确认与回退由自动化检查覆盖；没有对 220 ms 动画进行逐帧录制。构建：`build/audio-animation/Combo.app`。

## 鼠标拖动切换

蓝色选中胶囊支持水平拖动。拖动仅预览位置，不发送请求；松开后按最近的选项中心吸附并调用原控制接口，落回原项不写入，拖出轨道限制在两端。保留点击、原生辅助功能按钮、220 ms 吸附动画、减少动态效果设置、确认期间禁用及失败回退。

`AirPodsSegmentTrack` 复用两组轨道，使用 SwiftUI DragGesture 与自动复位的 GestureState；拖动须从当前蓝色胶囊开始。纯几何检查覆盖三段/两段、边界限位、最近项判断、非胶囊起点及无效输入。独立原生测试窗口使用相同 AirPodsSection 与控制器、测试 helper，鼠标操作验证：降噪拖到自适应、小幅拖动不发送请求、右侧越界限位、对话感知向右和向左切换。逐项日志确认每次改变选项的拖动仅一次请求；另单独验证一次普通鼠标点击也只有一次请求。真实耳机未被修改。完整构建及检查通过，产物 `build/audio-drag/Combo.app`。
