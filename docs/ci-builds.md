# Mobile builds

## Android: GitHub Actions

The `Build Android` workflow runs manually from Actions or when a `v*` tag is
pushed. It analyzes and tests the Flutter project before building three signed
release APKs for ARMv7, ARM64, and x86_64. The Actions artifact is retained for
30 days; the workflow does not publish a GitHub Release.

Flutter is pinned to 3.44.1, and Android uses Java 21 on Ubuntu. The Actions
run number supplies the build number. These repository secrets are required:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release JKS |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Private key password |
| `ANDROID_KEY_ALIAS` | Signing key alias |

CI restores signing files temporarily, then verifies the certificate of every
APK against the release key. Gradle refuses release builds when signing is not
configured. Local signing backups are kept in `.signing/android/`, ignored by
Git. Keep a separate private backup of the JKS and its credentials; app updates
must retain the same signing key. `android/key.properties.example` documents
the local configuration without including credentials.

## iOS: Xcode Cloud

The iOS app uses bundle ID `dev.cfmonitor.cfMonitorApp` and the shared `Runner`
scheme. Xcode Cloud's post-clone script installs Flutter 3.44.1, resolves the
locked Dart dependencies and installs the locked CocoaPods dependencies. The
workflow uses Xcode Cloud's managed signing and can archive for TestFlight.
