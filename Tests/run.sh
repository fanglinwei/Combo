#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${COMBO_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Separate xcodebuild commands can launch competing AppKit hosts even with parallel testing disabled.
zmodload zsh/system
testLock="${TMPDIR:-/tmp}/Combo-XCTest-${UID}.lock"
touch "$testLock"
if ! zsystem flock -e -t 0 "$testLock" 2>/dev/null; then
  print -u2 'Another Combo test run is active; waiting for it to finish.'
  zsystem flock -e "$testLock"
fi

exec xcodebuild test -project Combo.xcodeproj -scheme ComboTests -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -parallel-testing-enabled NO \
  -derivedDataPath "${COMBO_TEST_DERIVED_DATA:-${TMPDIR:-/tmp}/Combo-XCTest}" "$@"
