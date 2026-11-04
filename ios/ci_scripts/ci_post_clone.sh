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

if ! brew list --versions ruby >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install ruby
fi
export PATH="$(brew --prefix ruby)/bin:$PATH"
export GEM_HOME="$CI_WORKSPACE_PATH/cocoapods-gems"
gem install cocoapods --version 1.16.2 --no-document

cd ios
"$GEM_HOME/bin/pod" install --deployment
