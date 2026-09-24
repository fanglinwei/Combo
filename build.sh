#!/bin/zsh
set -eu
cd "${0:A:h}"
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
TARGET="$(uname -m)-apple-macosx26.0"
APP="${COMBO_APP_OUTPUT:-$PWD/build/Combo.app}"
SIGNING_IDENTITY="${COMBO_SIGNING_IDENTITY:--}"
if [[ "$APP" != /* || "$APP" != *.app ]]; then
    print -u2 'COMBO_APP_OUTPUT must be an absolute .app path.'
    exit 1
fi
if ps -axo command= | grep -Fxq "$APP/Contents/MacOS/Combo"; then
    print -u2 'Combo is running from the output path. Quit it before rebuilding, or use COMBO_APP_OUTPUT for a separate validation build.'
    exit 1
fi
if [[ "$SIGNING_IDENTITY" == - ]]; then
    print -u2 'WARNING: ad-hoc builds have version-specific signing identity; a rebuild may invalidate privacy grants. Use a consistent COMBO_SIGNING_IDENTITY for permission testing.'
fi
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
xcrun swiftc -sdk "$SDK" -target "$TARGET" Combo/State.swift Tests/main.swift -o build/state-check
./build/state-check
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library Combo/State.swift Combo/Icon.swift Tests/IconTransitionCheck.swift -o build/icon-transition-check
./build/icon-transition-check
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library Combo/WiFiControl.swift Tests/WiFiControlCheck.swift -o build/wifi-control-check
./build/wifi-control-check
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library Combo/HotspotControl.swift Tests/HotspotControlCheck.swift -o build/hotspot-control-check
./build/hotspot-control-check
xcrun clang -isysroot "$SDK" -target "$TARGET" -fobjc-arc -framework Foundation -framework IOKit Combo/ChargeHelper.m -o "$APP/Contents/Helpers/ComboChargeHelper"
codesign --force --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/ComboChargeHelper"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 Combo/State.swift Combo/ChargeControl.swift Tests/ChargeControlCheck.swift -o build/charge-control-check
./build/charge-control-check "$APP/Contents/Helpers/ComboChargeHelper"
xcrun clang -isysroot "$SDK" -target "$TARGET" -fobjc-arc -Wall -Wextra -Werror -framework Foundation Combo/EnergyHelper.m -o "$APP/Contents/Helpers/ComboEnergyHelper"
codesign --force --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/ComboEnergyHelper"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library Combo/EnergyApps.swift Tests/EnergyAppsCheck.swift -o build/energy-apps-check
./build/energy-apps-check
xcrun clang -isysroot "$SDK" -target "$TARGET" -dynamiclib -Wall -Wextra -Werror Combo/AirPodsContext.c -framework CoreFoundation -framework Security -o "$APP/Contents/Helpers/ComboAirPodsContext.dylib"
xcrun clang -isysroot "$SDK" -target "$TARGET" -fobjc-arc -Wall -Wextra -Werror Combo/AirPodsHelper.m -framework Foundation -framework CoreAudio -framework IOBluetooth -o "$APP/Contents/Helpers/ComboAirPodsHelper"
codesign --force --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/ComboAirPodsContext.dylib"
codesign --force --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/ComboAirPodsHelper"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library Combo/AudioVolume.swift Combo/AirPodsControl.swift Tests/AirPodsCheck.swift -o build/airpods-check
./build/airpods-check
xcrun clang -isysroot "$SDK" -target "$TARGET" -dynamiclib -fobjc-arc -Wall -Wextra -Werror -framework Foundation Combo/MediaPlaybackHelper.m -o "$APP/Contents/Helpers/ComboMediaPlayback.dylib"
codesign --force --sign "$SIGNING_IDENTITY" "$APP/Contents/Helpers/ComboMediaPlayback.dylib"
xcrun clang -isysroot "$SDK" -target "$TARGET" -fobjc-arc -Wall -Wextra -Werror -framework Foundation Tests/MediaPlaybackHelperCheck.m -o build/media-playback-helper-check
./build/media-playback-helper-check
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library Combo/MediaPlayback.swift Tests/MediaPlaybackCheck.swift -o build/media-playback-check
./build/media-playback-check
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 Combo/State.swift Combo/NetworkStatus.swift Combo/WiFiControl.swift Combo/HotspotControl.swift Combo/MenuBarSetup.swift Combo/MenuDiagnostics.swift Combo/MenuFoldExperiment.swift Combo/PowerModeControl.swift Combo/ChargeControl.swift Combo/EnergyApps.swift Combo/AudioVolume.swift Combo/AirPodsControl.swift Combo/MediaPlayback.swift Combo/Store.swift Combo/Icon.swift Combo/Views.swift Combo/main.swift -o "$APP/Contents/MacOS/Combo"
xcrun swiftc -sdk "$SDK" -target "$TARGET" Tests/RenderBrand.swift -o build/render-brand
mkdir -p build/Combo.iconset
./build/render-brand build/Combo-icon-1024.png
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" build/Combo-icon-1024.png --out "build/Combo.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -s format png -z "$double" "$double" build/Combo-icon-1024.png --out "build/Combo.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/Combo.iconset -o "$APP/Contents/Resources/Combo.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Combo</string>
<key>CFBundleIdentifier</key><string>local.combo.preview</string>
<key>CFBundleName</key><string>Combo</string>
<key>CFBundleDisplayName</key><string>Combo</string>
<key>CFBundleIconFile</key><string>Combo.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocationWhenInUseUsageDescription</key><string>查找可连接的 Wi‑Fi 网络并显示网络名称。</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>读取当前蓝牙耳机的电量并控制聆听模式。</string>
</dict></plist>
PLIST
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
zsh Tests/check-brand.sh "$APP"
printf 'Built: %s\n' "$APP"
