#!/bin/zsh
set -eu
cd "${0:A:h}"
export DEVELOPER_DIR="${COMBO_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
./build.sh "$@"
python3 Tests/Views/PanelLocalizationCheck.py
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="$(uname -m)-apple-macosx26.0"
APP="$(xcodebuild -project Combo.xcodeproj -scheme Combo -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -showBuildSettings -json "$@" | python3 -c 'import json,sys; s=json.load(sys.stdin)[0]["buildSettings"]; print(s["TARGET_BUILD_DIR"] + "/" + s["FULL_PRODUCT_NAME"])')"
OUT="$PWD/build/checks"
mkdir -p "$OUT"
RESULTS="$(mktemp -d "$OUT/xctest.XXXXXX")"
./Tests/run.sh -resultBundlePath "$RESULTS/ComboTests.xcresult" "$@"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 Combo/App/Localization.swift Combo/App/State.swift Combo/Audio/OutputDevice.swift Combo/Battery/ChargeControl.swift -parse-as-library Tests/Tools/ChargeHelperCheck.swift -o "$OUT/charge-helper-check"
"$OUT/charge-helper-check" "$APP/Contents/Helpers/ComboChargeHelper"
codesign --verify --deep --strict "$APP"
zsh Tests/App/check-brand.sh "$APP"
printf 'Verified: %s\n' "$APP"
