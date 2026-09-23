#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# The running GUI is the real regression condition; never replace its executable.
APP="$PWD/build/Combo.app"
if ! ps -axo command= | grep -Fxq "$APP/Contents/MacOS/Combo"; then
  print 'SKIP: launch build/Combo.app to verify the overwrite guard.'
  exit 0
fi
before=$(shasum -a 256 "$APP/Contents/MacOS/Combo")
if output=$(./build.sh 2>&1); then
  print -u2 'FAIL: build overwrote a running app.'
  exit 1
fi
[[ "$output" == *'Combo is running from the output path.'* ]]
[[ "$before" == "$(shasum -a 256 "$APP/Contents/MacOS/Combo")" ]]
print 'PASS: running app rebuild rejected; executable unchanged.'
