# 系统菜单公开 AX 能力探针

验证目标：Wi-Fi、声音／AirPods、电池。它不是 Combo 应用，也没有实现折叠、移动或归位。

## 构建与自动检查

在项目根目录执行：

```sh
xcrun swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk prototypes/menu-access/MenuProbe.swift -o prototypes/menu-access/MenuProbe
python3 prototypes/menu-access/check.py
```

本次结果：macOS 26 SDK 编译通过，参数保护和目标精确选择检查通过。没有安装额外依赖。

## 实机诊断

```sh
./prototypes/menu-access/MenuProbe --list
```

2026-09-22 本次实际返回退出码 2：当前执行环境没有辅助功能权限。未弹授权、未读取到菜单项、未点击或修改布局。因此无法据此判定三个项目是否暴露可用 AXPress。

在用户已主动授予对应运行宿主辅助功能权限的测试环境中，重新列举。只输出菜单栏项的 identifier、role、actions，不递归读取下拉菜单中的网络名等内容。若目标无标识、无 AXPress 或无法定位，记为能力不足，不用坐标猜测。

需要点击验证时，人工确认输出中属于目标的精确标识，再运行 `MenuProbe --press '实际标识'`。该操作会尝试打开系统菜单；程序不会替你关闭菜单或修改选项。没有内置猜测标识；输出成功只代表 AX 接受 action，不证明正确菜单已展开。

终端已有权限不代表正式应用有权限。后续必须使用稳定签名 GUI 原型复验，并另行实现折叠恢复链路。日期／时钟不属于这个探针的支持承诺。
