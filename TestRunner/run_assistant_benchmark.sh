#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

xcodebuild \
  -scheme TestRunner \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived \
  build >/tmp/testrunner-build.log

./.derived/Build/Products/Debug/TestRunner assistant-benchmark "$@"
