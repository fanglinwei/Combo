#!/bin/zsh
set -euo pipefail

dmg_releases="${0:A:h}"
dmg_root="${dmg_releases:h}"
dmg_app=""
case "${1:-}" in
  "") ;;
  --app)
    [[ $# == 2 ]] || { print -ru2 -- '用法：./Releases/package-dmg.sh [--app /path/to/Combo.app]'; exit 1; }
    dmg_app="${2:A}"
    ;;
  --help|-h)
    print -r -- '用法：./Releases/package-dmg.sh [--app /path/to/Combo.app]'
    print -r -- '默认增量构建 Release（arm64），再生成 Releases/Combo-版本号-arm64.dmg。'
    print -r -- '--app 跳过构建，复制并以 ad-hoc 签名打包指定的纯 arm64 Combo.app。'
    exit 0
    ;;
  *) print -ru2 -- "不支持的参数：$1"; exit 1 ;;
esac
[[ $# == 0 || "${1:-}" == --app ]] || exit 1
cd "$dmg_root"
export DEVELOPER_DIR="${COMBO_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

[[ "$(uname -s)" == Darwin ]] || { print -ru2 -- '此脚本需要 macOS。'; exit 1; }
command -v python3 >/dev/null || { print -ru2 -- '请安装 Python 3.10 或更高版本。'; exit 1; }
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else "需要 Python 3.10 或更高版本")'
xcrun --find swiftc >/dev/null
if [[ -z "$dmg_app" && "$(uname -m)" != arm64 ]]; then
  print -ru2 -- '默认构建需要 Apple Silicon Mac；也可用 --app 指定纯 arm64 App。'
  exit 1
fi

mkdir -p build "$dmg_releases"
dmg_lock="$dmg_root/build/dmg-package.lock"
mkdir "$dmg_lock" 2>/dev/null || { print -ru2 -- "已有打包任务运行，或上次被强制中止留下锁：$dmg_lock"; exit 1; }
dmg_work=""
dmg_device=""
dmg_resources="$dmg_releases/packaging"
cleanup() {
  local dmg_result=$1 dmg_devices dmg_owned dmg_safe=1
  set +e
  if [[ -n "$dmg_work" ]]; then
    if dmg_devices="$(python3 "$dmg_resources/dmg.py" owned-devices "$dmg_work")"; then
      for dmg_owned in "${(@f)dmg_devices}"; do
        [[ -n "$dmg_owned" ]] || continue
        diskutil eject "$dmg_owned" >/dev/null || dmg_safe=0
      done
    else
      dmg_safe=0
    fi
    if (( dmg_safe )); then
      rm -rf "$dmg_work" || dmg_result=1
    else
      print -ru2 -- "无法确认临时镜像已卸载，保留工作目录：$dmg_work"
      dmg_result=1
    fi
  fi
  rmdir "$dmg_lock" || dmg_result=1
  return "$dmg_result"
}
trap 'cleanup $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
dmg_work="$(mktemp -d "$dmg_root/build/dmg-package.XXXXXX")"
dmg_python="$dmg_root/build/dmg-venv/bin/python"
if [[ ! -x "$dmg_python" ]]; then
  print -r -- '首次运行：创建隔离的 Python 环境…'
  python3 -m venv "$dmg_root/build/dmg-venv"
fi
if ! "$dmg_python" -c 'from importlib.metadata import version; assert version("ds_store") == "1.3.3" and version("mac_alias") == "2.2.3"' >/dev/null 2>&1; then
  print -r -- '首次运行：安装固定版本的 Finder 布局依赖…'
  "$dmg_python" -m pip install --disable-pip-version-check -r "$dmg_resources/requirements.txt"
fi

if [[ -z "$dmg_app" ]]; then
  print -r -- '构建 Release（arm64），构建日志：build/dmg-release-build.log'
  if ! COMBO_CONFIGURATION=Release ./build.sh -derivedDataPath "$dmg_root/build/dmg-release" \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- \
      > "$dmg_root/build/dmg-release-build.log" 2>&1; then
    tail -n 60 "$dmg_root/build/dmg-release-build.log" >&2
    exit 1
  fi
  dmg_app="$dmg_root/build/dmg-release/Build/Products/Release/Combo.app"
fi
[[ -d "$dmg_app" && -f "$dmg_app/Contents/Info.plist" ]] || { print -ru2 -- "找不到有效的 App：$dmg_app"; exit 1; }
dmg_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$dmg_app/Contents/Info.plist")"
[[ -n "$dmg_version" && "$dmg_version" != *[^a-zA-Z0-9._-]* ]] || { print -ru2 -- 'App 版本号不能用于文件名。'; exit 1; }
dmg_name="Combo-${dmg_version}-arm64.dmg"
dmg_output="$dmg_releases/$dmg_name"
"$dmg_python" "$dmg_resources/dmg.py" ensure-unmounted "$dmg_output"

print -r -- "准备 $dmg_name…"
dmg_stage="$dmg_work/stage"
mkdir -p "$dmg_stage/.background"
ditto --rsrc --extattr "$dmg_app" "$dmg_stage/Combo.app"
# Only clean the copied app; leave the source app and the helper icons intact.
/usr/bin/xattr -cr "$dmg_stage/Combo.app"
ln -s /Applications "$dmg_stage/Applications"
cp "$dmg_resources/assets/background.tiff" "$dmg_stage/.background/background.tiff"
for dmg_script in 允许任意来源.command 清除下载隔离.command; do
  cp "$dmg_resources/$dmg_script" "$dmg_stage/$dmg_script"
  chmod 755 "$dmg_stage/$dmg_script"
  /bin/zsh -n "$dmg_stage/$dmg_script"
done
"$dmg_python" "$dmg_resources/dmg.py" prepare "$dmg_stage" "$dmg_resources" "$dmg_name"
xcrun swiftc "$dmg_resources/set-icons.swift" -o "$dmg_work/set-icons"
"$dmg_work/set-icons" "$dmg_resources/assets" "$dmg_stage"

attach_image() {
  hdiutil attach "$1" "$2" -nobrowse -noautoopen -mountpoint "$dmg_work/volume" -plist > "$dmg_work/attach.plist" || return $?
  dmg_device="$("$dmg_python" -c 'import plistlib,sys; data=plistlib.load(open(sys.argv[1],"rb")); print(next(e["dev-entry"] for e in data["system-entities"] if e.get("mount-point")))' "$dmg_work/attach.plist")" || return $?
  [[ -n "$dmg_device" ]]
}
eject_image() {
  diskutil eject "$dmg_device" >/dev/null || return $?
  dmg_device=""
}
hdiutil create -srcfolder "$dmg_stage" -volname 'Combo 安装' -fs HFS+ -format UDRW -o "$dmg_work/writable.dmg" >/dev/null
# Explicit exits avoid zsh ERR_EXIT bypassing EXIT traps on function failures.
attach_image "$dmg_work/writable.dmg" -readwrite || exit $?
"$dmg_python" "$dmg_resources/dmg.py" layout "$dmg_work/volume" "$dmg_stage" "$dmg_work/manifest.json"
"$dmg_python" "$dmg_resources/dmg.py" verify "$dmg_work/volume" "$dmg_work/manifest.json"
eject_image || exit $?

print -r -- '压缩并校验最终 DMG…'
hdiutil convert "$dmg_work/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_work/final.dmg" >/dev/null
hdiutil verify "$dmg_work/final.dmg" > "$dmg_work/verify.log"
attach_image "$dmg_work/final.dmg" -readonly || exit $?
"$dmg_python" "$dmg_resources/dmg.py" verify "$dmg_work/volume" "$dmg_work/manifest.json"
eject_image || exit $?

# Recheck immediately before replacing an existing release.
"$dmg_python" "$dmg_resources/dmg.py" ensure-unmounted "$dmg_output"
cp "$dmg_work/verify.log" "$dmg_root/build/dmg-package-verify.log"
"$dmg_python" "$dmg_resources/dmg.py" publish "$dmg_work/final.dmg" "$dmg_stage/安装指南.html" "$dmg_output"
print -r -- "完成：$dmg_output"
shasum -a 256 "$dmg_output"
