#!/bin/sh

set -eu

FLUTTER_VERSION="3.44.1"
FLUTTER_ROOT="$CI_WORKSPACE_PATH/flutter"
APP_ROOT="$CI_PRIMARY_REPOSITORY_PATH"

git clone --depth 1 --branch "$FLUTTER_VERSION" \
  https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
export PATH="$FLUTTER_ROOT/bin:$PATH"

flutter config --no-analytics --no-enable-swift-package-manager
flutter precache --ios
cd "$APP_ROOT"
flutter pub get --enforce-lockfile

if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi

cd ios
pod install --deployment
