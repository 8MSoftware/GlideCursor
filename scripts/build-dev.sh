#!/bin/zsh
# 開発用ビルド。Developer ID で署名するので、作り直してもアクセシビリティの許可が消えない。
# 出力: build/Debug/GlideCursor.app
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcodebuild -project GlideCursor.xcodeproj -target GlideCursor -configuration Debug SYMROOT=build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=BSUN46UA74 \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp=none \
  build | grep -E "error|BUILD"
