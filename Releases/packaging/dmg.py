"""Build and verify Combo's Finder layout without running the installer commands."""

import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import stat
import subprocess
import sys
import tempfile


POSITIONS = {
    "Combo.app": (220, 180),
    "Applications": (540, 180),
    "安装指南.html": (200, 350),
    "允许任意来源.command": (380, 350),
    "清除下载隔离.command": (560, 350),
}
HELPERS = list(POSITIONS)[2:]
MACH_MAGIC = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
)}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def app_files(app):
    return {str(file.relative_to(app)): digest(file) for file in app.rglob("*") if file.is_file()}


def attribute(file, name):
    return bytes.fromhex(subprocess.check_output(["/usr/bin/xattr", "-px", name, str(file)], text=True))


def icon_metadata(file):
    flags = int.from_bytes(attribute(file, "com.apple.FinderInfo")[8:10], "big")
    require(flags & 0x0400 and flags & 0x0010, f"图标或隐藏扩展名属性缺失：{file}")
    resource = attribute(file, "com.apple.ResourceFork")
    require(resource, f"图标资源为空：{file}")
    return {"data": digest(file), "icon": hashlib.sha256(resource).hexdigest()}


def ensure_unmounted(output):
    info = plistlib.loads(subprocess.check_output(["hdiutil", "info", "-plist"]))
    require(not any(Path(image.get("image-path", "")).resolve() == output.resolve()
                    for image in info["images"]), f"输出 DMG 正在挂载，请先在 Finder 中弹出再重试：{output}")


def owned_devices(work):
    # Recover even when attach succeeded but parsing its output failed.
    sources = {(work / name).resolve() for name in ("writable.dmg", "final.dmg")}
    info = plistlib.loads(subprocess.check_output(["hdiutil", "info", "-plist"]))
    for image in info["images"]:
        if Path(image.get("image-path", "")).resolve() in sources:
            entities = image["system-entities"]
            require(entities and entities[0].get("dev-entry"), "无法确定临时镜像设备")
            print(entities[0]["dev-entry"])


def publish(image, guide, output):
    targets = (output, output.parent / "安装指南.html")
    locked_flags = stat.UF_IMMUTABLE | stat.SF_IMMUTABLE | stat.UF_APPEND | stat.SF_APPEND
    for target in targets:
        require(not target.is_symlink(), f"发布目标不能是符号链接：{target}")
        if target.exists():
            require(target.is_file(), f"发布目标不是文件：{target}")
            require(not target.stat().st_flags & locked_flags, f"发布目标已锁定，请先解锁：{target}")
    # Stage on the destination filesystem so each replacement is an atomic rename.
    transaction = Path(tempfile.mkdtemp(prefix=".combo-publish-", dir=output.parent))
    replaced = []
    recovery_needed = False

    def interrupted(signum, frame):
        raise RuntimeError(f"发布被信号 {signum} 中断")

    handlers = {number: signal.signal(number, interrupted)
                for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
    try:
        for index, (source, target) in enumerate(zip((image, guide), targets)):
            if target.exists():
                subprocess.run(["ditto", "--rsrc", "--extattr", str(target),
                                str(transaction / f"old-{index}")], check=True)
            subprocess.run(["ditto", "--rsrc", "--extattr", str(source),
                            str(transaction / f"new-{index}")], check=True)
        # Record intent before rename so interruption immediately after it is recoverable.
        for index, target in enumerate(targets):
            replaced.append((index, target))
            os.replace(transaction / f"new-{index}", target)
    except BaseException:
        # Let rollback finish if another ordinary termination signal arrives.
        for number in handlers:
            signal.signal(number, signal.SIG_IGN)
        for index, target in reversed(replaced):
            try:
                backup = transaction / f"old-{index}"
                if backup.exists():
                    os.replace(backup, target)
                else:
                    target.unlink(missing_ok=True)
            except OSError as error:
                recovery_needed = True
                print(f"恢复失败：{target}：{error}", file=sys.stderr)
        if recovery_needed:
            print(f"保留发布备份，请从此目录恢复：{transaction}", file=sys.stderr)
        raise
    finally:
        if not recovery_needed:
            try:
                shutil.rmtree(transaction)
            except OSError as error:
                print(f"发布临时目录未清理：{transaction}：{error}", file=sys.stderr)
        for number, handler in handlers.items():
            signal.signal(number, handler)


def executable_main(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info["CFBundleExecutable"] == "Combo", "--app 必须指向 Combo.app")
    main = app / "Contents/MacOS" / info["CFBundleExecutable"]
    require(main.is_file(), "App 缺少主程序")
    require(os.access(main, os.X_OK), f"App 主程序没有执行权限：{main}")
    return main


def prepare(stage, resources, dmg_name):
    app = stage / "Combo.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    main = executable_main(app)
    binaries = []
    for file in app.rglob("*"):
        if file.is_file() and not file.is_symlink():
            with file.open("rb") as stream:
                if stream.read(4) in MACH_MAGIC:
                    architectures = subprocess.check_output(["lipo", "-archs", str(file)], text=True).split()
                    require(architectures == ["arm64"], f"需要纯 arm64 可执行文件：{file}（{architectures}）")
                    binaries.append(file)
    require(main in binaries, "主程序不是有效的 arm64 Mach-O 文件")
    bundles = [file for file in app.rglob("*") if file.is_dir() and not file.is_symlink()
               and file.suffix in {".app", ".framework", ".xpc", ".appex"}]
    # Sign nested code before enclosing bundles; preserve existing entitlements.
    for code in sorted(binaries, key=lambda file: len(file.parts), reverse=True) + sorted(
            bundles, key=lambda file: len(file.parts), reverse=True) + [app]:
        subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                        "--preserve-metadata=entitlements,requirements,flags", str(code)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    replacements = {
        "@VERSION@": info["CFBundleShortVersionString"],
        "@BUILD@": info["CFBundleVersion"],
        "@MINIMUM_MACOS@": info["LSMinimumSystemVersion"],
        "@DMG_NAME@": dmg_name,
    }
    guide = (resources / "安装指南.template.html").read_text()
    for token, value in replacements.items():
        require(token in guide, f"指南模板缺少占位符：{token}")
        guide = guide.replace(token, html.escape(str(value)))
    (stage / "安装指南.html").write_text(guide)
    print(f"已验证并签名 {len(binaries)} 个 arm64 可执行文件；生成当前版本指南。")


def layout(volume, stage, manifest):
    from ds_store import DSStore
    from mac_alias import Alias

    with DSStore.open(str(volume / ".DS_Store"), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = {
            "ShowStatusBar": False, "ShowToolbar": False, "ShowTabView": False,
            "ShowPathbar": False, "ContainerShowSidebar": False, "ShowSidebar": False,
            "PreviewPaneVisibility": False, "SidebarWidth": 180,
            "WindowBounds": "{{300, 180}, {760, 528}}",
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1, "backgroundType": 2,
            "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
            "backgroundImageAlias": Alias.for_file(str(volume / ".background/background.tiff")).to_bytes(),
            "iconSize": 128.0, "textSize": 14.0, "gridSpacing": 100.0,
            "gridOffsetX": 0.0, "gridOffsetY": 0.0, "scrollPositionX": 0.0, "scrollPositionY": 0.0,
            "showItemInfo": False, "labelOnBottom": True, "showIconPreview": False, "arrangeBy": "none",
        }
        store["."]["icvl"] = ("type", b"icnv")
        for name, point in POSITIONS.items():
            store[name]["Iloc"] = point
    expected = {
        "app": app_files(stage / "Combo.app"),
        "helpers": {name: icon_metadata(stage / name) for name in HELPERS},
        "background": digest(stage / ".background/background.tiff"),
    }
    manifest.write_text(json.dumps(expected, ensure_ascii=False, indent=2))


def verify(volume, manifest):
    from ds_store import DSStore

    expected = json.loads(manifest.read_text())
    visible = {file.name for file in volume.iterdir() if not file.name.startswith(".")}
    require(visible == set(POSITIONS), f"DMG 文件不符合预期：{visible}")
    require((volume / "Applications").is_symlink()
            and os.readlink(volume / "Applications") == "/Applications", "Applications 链接无效")
    executable_main(volume / "Combo.app")
    require(app_files(volume / "Combo.app") == expected["app"], "镜像中的 App 内容发生变化")
    for name in HELPERS:
        require(icon_metadata(volume / name) == expected["helpers"][name], f"内容或自定义图标未保留：{name}")
        if name.endswith(".command"):
            require(os.access(volume / name, os.X_OK), f"脚本没有执行权限：{name}")
    require(digest(volume / ".background/background.tiff") == expected["background"], "背景文件发生变化")
    with DSStore.open(str(volume / ".DS_Store"), "r") as store:
        positions = {entry.filename: entry.value for entry in store if entry.code == b"Iloc"}
        require(positions == POSITIONS, f"Finder 图标顺序或位置不符合预期：{positions}")
        require(store["."]["icvp"]["iconSize"] == 128, "Finder 图标尺寸不符合预期")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(volume / "Combo.app")], check=True)
    signature = subprocess.run(["codesign", "-dv", str(volume / "Combo.app")], capture_output=True, text=True, check=True)
    require("Signature=adhoc" in signature.stderr, "App 未使用 ad-hoc 签名")
    print("校验通过：App 签名、文件内容、拖动安装链接、5 项布局、辅助图标和脚本权限。")


if __name__ == "__main__":
    try:
        command = sys.argv[1]
        if command == "ensure-unmounted":
            ensure_unmounted(Path(sys.argv[2]))
        elif command == "owned-devices":
            owned_devices(Path(sys.argv[2]))
        elif command == "publish":
            publish(*(Path(value) for value in sys.argv[2:5]))
        elif command == "prepare":
            prepare(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
        elif command == "layout":
            layout(*(Path(value) for value in sys.argv[2:5]))
        elif command == "verify":
            verify(*(Path(value) for value in sys.argv[2:4]))
        else:
            raise RuntimeError(f"未知打包步骤：{command}")
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"打包失败：{error}", file=sys.stderr)
        sys.exit(1)
