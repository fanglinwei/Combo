#!/bin/zsh
set -eu
cd "${0:A:h}"
export DEVELOPER_DIR="${COMBO_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
configuration="${COMBO_CONFIGURATION:-Debug}"
xcodebuild -project Combo.xcodeproj -scheme Combo -configuration "$configuration" -destination "platform=macOS,arch=$(uname -m)" build "$@"
