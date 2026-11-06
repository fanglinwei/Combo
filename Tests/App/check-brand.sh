#!/bin/zsh
set -eu
APP="${1:?pass the built Combo.app path}"
[[ -s "$APP/Contents/Resources/AppIcon.icns" ]] || { print -u2 'Missing application icon'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Contents/Info.plist")" == 'AppIcon' ]] || { print -u2 'Icon not declared in Info.plist'; exit 1; }
[[ -s "$APP/Contents/Resources/Assets.car" ]] || { print -u2 'Missing compiled asset catalog'; exit 1; }
[[ -s docs/assets/brand/combo-iris-logo.svg ]] || { print -u2 'Missing editable logo'; exit 1; }
print 'PASS: brand assets packaged and declared'
