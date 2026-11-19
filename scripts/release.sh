#!/bin/zsh
# リリース用 .pkg を作り、公証してステープルする。
# 使い方: scripts/release.sh <version> [notary-profile]
#   例:   scripts/release.sh 2.0
# 公証用の資格情報は、事前に一度だけ次で保存しておく:
#   xcrun notarytool store-credentials notary --apple-id <Apple ID> --team-id BSUN46UA74
# 出力: dist/GlideCursor-<version>.pkg
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?version を指定してください（例: 2.0）}
PROFILE=${2:-notary}
TEAM=BSUN46UA74
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

BUILD=build/release
DIST=dist
rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"

echo "== build $VERSION"
xcodebuild -project GlideCursor.xcodeproj -target GlideCursor -configuration Release SYMROOT="$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=$TEAM \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
  build | grep -E "error|BUILD"
APP="$BUILD/Release/GlideCursor.app"
codesign --verify --strict --deep "$APP"

echo "== pkg"
PKG="$DIST/GlideCursor-$VERSION.pkg"
pkgbuild --component "$APP" --install-location /Applications \
  --identifier jp.yaoyorozu.glidecursor.pkg --version "$VERSION" \
  --sign "Developer ID Installer: COUNTER SPACE, K.K. ($TEAM)" --timestamp "$PKG"

echo "== notarize ($PROFILE)"
xcrun notarytool submit "$PKG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$PKG"
spctl --assess --type install -vv "$PKG"
shasum -a 256 "$PKG"
