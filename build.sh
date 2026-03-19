#!/bin/bash
#
# build.sh — Speech2Text xcodebuild wrapper
#
# WHY xcodebuild (not swift build):
#   Metal shaders are compiled into default.metallib by Xcode's build system.
#   Running `swift build` silently omits Metal compilation, which causes
#   runtime failures for any Metal-backed framework — including mlx-swift,
#   which Speech2Text uses for LLM GPU inference via mlx-swift-lm.
#   Always use xcodebuild for this project. Never use swift build.
#
# CLEAN-RESOLUTION TEST PROCEDURE:
#   To verify that package dependencies resolve correctly on a clean checkout:
#
#   rm Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
#   xcodebuild -project Speech2Text.xcodeproj -resolvePackageDependencies
#
#   This should complete without errors and re-create Package.resolved.
#

set -euo pipefail

xcodebuild \
    -project Speech2Text.xcodeproj \
    -scheme Speech2Text \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Release \
    build
