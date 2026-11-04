# Mobile brand and screenshots

The original mobile logo combines a **C**, a monitoring pulse, and an online
status light. Its Cloudflare-inspired orange/gold palette is `#F38020` →
`#FAAE40`, with a white C and a pale gold (`#FFF1BD`) pulse. It is an original
CF Monitor mark, not the Cloudflare logo. The logo and this project's artwork
are included under the repository's MIT License.

`assets/branding/logo.svg` is the editable master; `logo.png` is the opaque
1024 × 1024 export used by Flutter and the README. iOS receives opaque square
icons, allowing the system to apply its mask. Android receives five legacy PNG
sizes, an adaptive vector foreground/background, and an Android 13 monochrome
variant. The symbol fits inside the adaptive icon's central safe region.

## Regenerate the icons

Requires Node.js and [sharp](https://sharp.pixelplumbing.com/). No app dependency
or launcher-icon plugin is added.

```sh
npm install --prefix /tmp/cf-artwork sharp
SHARP_MODULE=/tmp/cf-artwork/node_modules/sharp node tools/generate_icons.mjs
```

The generator exports the paths and colors from the SVG into Android's vector
drawables and replaces every PNG referenced by iOS `AppIcon.appiconset`.

## Capture and compose

Run from the mobile repository root:

```sh
flutter pub get
flutter test tools/capture_screenshots_test.dart --no-pub
python3 -m venv /tmp/cf-artwork-venv
/tmp/cf-artwork-venv/bin/pip install Pillow
/tmp/cf-artwork-venv/bin/python tools/compose_showcase.py
```

Put `flutter` on PATH, set `FLUTTER_ROOT`, or pass
`--font-dir /path/to/flutter/bin/cache/artifacts/material_fonts` to the
composition script. The capture tool reads Roboto and Material Icons from the
Flutter SDK. On macOS it also loads system fonts for Unicode symbols and emoji;
on other systems, set `SCREENSHOT_SYMBOL_FONT` and `SCREENSHOT_EMOJI_FONT` to
compatible local font files. `SCREENSHOT_MONO_FONT` can optionally supply a
monospace font. Fonts are not copied into the repository or application.

The capture harness navigates the **actual app widgets** with an isolated
in-memory API/storage fixture. It creates four 1170 × 2532 PNGs under
`docs/images/screenshots/`: site management, compact server list, resource
history in dark mode, and network quality in dark mode. It makes no network
requests, writes no device credentials, and is separate from the default
`test/` suite. These are widget renders, not emulator or device screenshots.

`compose_showcase.py` combines the unmodified captures into
`docs/images/showcase.png` (2400 × 1680), used by both README languages.
