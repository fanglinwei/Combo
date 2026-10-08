#!/usr/bin/env python3
"""Prepare local Sparkle upload artifacts from an already finalized Combo DMG."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FEED = "https://fanglinwei.github.io/Combo/updates/appcast.xml"
RELEASES = "https://github.com/fanglinwei/Combo/releases"
NOTES = "https://fanglinwei.github.io/Combo/updates/notes/"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
ACCOUNT = "combo-updates"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(value):
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value), f"无效的数字版本：{value}")
    parts = [int(part) for part in value.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def validate_history(feed, display, build):
    require(re.fullmatch(r"[1-9][0-9]*", build), "新构建号必须是独立的正整数")
    for item in feed.findall("./channel/item"):
        enclosure = item.find("enclosure")
        old_build = item.findtext(SPARKLE + "version")
        old_display = item.findtext(SPARKLE + "shortVersionString")
        if enclosure is not None:
            old_build = old_build or enclosure.get(SPARKLE + "version")
            old_display = old_display or enclosure.get(SPARKLE + "shortVersionString")
        require(old_build, "旧清单项缺少构建号，不能判断递增关系")
        require(version(build) > version(old_build), f"构建号必须大于已公开值 {old_build}")
        require(not old_display or version(display) > version(old_display),
                f"发行版本必须大于已公开值 {old_display}")


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Combo-release-preparation"})
    with urllib.request.urlopen(request, timeout=30) as response:
        require(response.url.startswith("https://"), "远端地址必须保持 HTTPS")
        return response.read()


def prepare(args):
    dmg = args.dmg.resolve()
    tools = args.sparkle_tools.resolve() / "bin"
    output = args.output.resolve()
    require(not output.exists(), f"候选目录已存在，不覆盖：{output}")
    require(dmg.is_file(), f"找不到最终 DMG：{dmg}")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version), "发行版本必须是 X.Y.Z")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.tag), "标签不能包含路径或特殊字符")
    require(dmg.name == f"Combo-{args.version}-arm64.dmg", "DMG 文件名与发行版本不一致")
    require(args.notes.is_file() and args.notes.read_text().strip(), "需要非空 HTML 更新说明")
    require(args.notes.suffix.lower() == ".html", "更新说明使用完整 HTML 页面")
    require(re.search(r"<body\b", args.notes.read_text(), re.I), "更新说明需要 body 标签")
    for name in ("generate_keys", "generate_appcast", "sign_update"):
        require((tools / name).is_file(), f"缺少 Sparkle 工具：{name}")
    feed_bytes = download(FEED)
    history = ET.fromstring(feed_bytes)
    require(history.tag == "rss" and history.find("channel") is not None, "线上清单不是有效 RSS")
    validate_history(history, args.version, args.build)
    # Use the existing gh login to avoid anonymous API rate limits and detect drafts.
    release = subprocess.run(["gh", "api", f"repos/fanglinwei/Combo/releases/tags/{args.tag}"],
                             capture_output=True, text=True)
    require(release.returncode != 0, "该标签已有 Release，不能重新准备覆盖包")
    require("HTTP 404" in release.stderr, f"无法核对远端 Release：{release.stderr.strip()}")
    public_key = run(tools / "generate_keys", "--account", ACCOUNT, "-p")
    require(public_key == (ROOT / "docs/updates/public-ed-key.txt").read_text().strip(),
            "钥匙串公钥与仓库公钥不一致")
    run("hdiutil", "verify", dmg)
    with tempfile.TemporaryDirectory(prefix="combo-update-", dir=ROOT / "build") as temp:
        work = Path(temp)
        # Keep mounts outside auto-cleaned work: never recurse into a still-mounted volume.
        mount_root = Path(tempfile.mkdtemp(prefix="combo-update-mount-", dir=ROOT / "build"))
        mount = mount_root / "volume"
        attached = plistlib.loads(subprocess.check_output([
            "hdiutil", "attach", str(dmg), "-readonly", "-nobrowse", "-noautoopen",
            "-mountpoint", str(mount), "-plist"]))
        device = next(entity["dev-entry"] for entity in attached["system-entities"]
                      if entity.get("mount-point"))
        try:
            app = mount / "Combo.app"
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            require(info["CFBundleShortVersionString"] == args.version
                    and info["CFBundleVersion"] == args.build, "包内版本/构建号与参数不一致")
            require(info["CFBundleIdentifier"] == "local.combo.app", "包内不是正式 Combo Bundle ID")
            require(info.get("SUFeedURL") == FEED and info.get("SUPublicEDKey") == public_key,
                    "包内更新源或公钥不一致")
            require(version(info["LSMinimumSystemVersion"]) >= version("26"), "最低系统配置不一致")
            require(run("lipo", "-archs", app / "Contents/MacOS/Combo") == "arm64", "Combo 必须是 arm64")
            run("codesign", "--verify", "--deep", "--strict", app)
        finally:
            try:
                run("hdiutil", "detach", device)
            except subprocess.CalledProcessError as error:
                raise ValueError(f"无法卸载测试镜像，保留挂载目录：{mount_root}") from error
            if mount.exists():
                mount.rmdir()
            mount_root.rmdir()
        # Work on copies. The signed final archive and production feed stay unchanged.
        candidate = work / "candidate"
        candidate.mkdir()
        archive = candidate / dmg.name
        shutil.copy2(dmg, archive)
        release_note = candidate / (dmg.stem + ".html")
        shutil.copy2(args.notes, release_note)
        (candidate / "appcast.xml").write_bytes(feed_bytes)
        download_prefix = f"{RELEASES}/download/{urllib.parse.quote(args.tag)}/"
        run(tools / "generate_appcast", "--account", ACCOUNT, "--maximum-deltas", "0",
            "--maximum-versions", "0", "--versions", args.build,
            "--download-url-prefix", download_prefix,
            "--release-notes-url-prefix", NOTES, "--link", RELEASES, candidate)
        generated = ET.parse(candidate / "appcast.xml").getroot()
        require(len(generated.findall("./channel/item")) == len(history.findall("./channel/item")) + 1,
                "生成清单丢失旧条目或新增了意外条目")
        item = next(item for item in generated.findall("./channel/item")
                    if item.findtext(SPARKLE + "version") == args.build)
        enclosure = item.find("enclosure")
        require(enclosure is not None, "生成项缺少 enclosure")
        require(item.findtext(SPARKLE + "shortVersionString") == args.version, "生成项发行版本错误")
        require(enclosure.get("url") == download_prefix + dmg.name, "生成项下载地址错误")
        require(int(enclosure.get("length", "0")) == archive.stat().st_size, "生成项文件大小错误")
        require(item.findtext(SPARKLE + "minimumSystemVersion") == info["LSMinimumSystemVersion"],
                "生成项最低系统错误")
        require(item.findtext(SPARKLE + "hardwareRequirements") == "arm64", "生成项硬件要求错误")
        require(item.findtext(SPARKLE + "releaseNotesLink") == NOTES + release_note.name,
                "生成项说明地址错误")
        run(tools / "sign_update", "--account", ACCOUNT, "--verify", archive,
            enclosure.get(SPARKLE + "edSignature", ""))
        original_hash = hashlib.sha256(dmg.read_bytes()).hexdigest()
        require(hashlib.sha256(archive.read_bytes()).hexdigest() == original_hash, "最终 DMG 字节发生变化")
        note_dir = candidate / "notes"
        note_dir.mkdir()
        release_note.rename(note_dir / release_note.name)
        report = dict(version=args.version, build=args.build, tag=args.tag, archive=dmg.name,
                      bytes=archive.stat().st_size, sha256=original_hash,
                      source_feed_sha256=hashlib.sha256(feed_bytes).hexdigest(),
                      download_url=enclosure.get("url"),
                      notes_url=item.findtext(SPARKLE + "releaseNotesLink"),
                      status="local-prepared", notarized=False,
                      pending=["standard-ui-upgrade", "clean-mac-acceptance", "publication"])
        (candidate / "release-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        # Recheck the destination before moving; never replace a previous candidate.
        output.parent.mkdir(parents=True, exist_ok=True)
        require(not output.exists(), f"候选目录已存在：{output}")
        shutil.move(str(candidate), str(output))
    print(f"已准备本地候选：{output}\nSHA-256：{original_hash}\n未提交、上传或发布更新源。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dmg", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--tag", required=True, help="实际发布标签，显式指定以避免 v 前缀差异")
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sparkle-tools", type=Path,
                        default=Path.home() / "Library/Caches/Combo/Sparkle/2.10.0/spm")
    args = parser.parse_args()
    (ROOT / "build").mkdir(exist_ok=True)
    try:
        prepare(args)
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        parser.exit(1, f"准备失败：{error}\n")


if __name__ == "__main__":
    main()
