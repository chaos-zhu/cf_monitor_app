# Mobile builds with GitHub Actions

The `Build Android and iOS` workflow runs manually from Actions or when a `v*`
tag is pushed. Analysis, the Flutter suite, and signing configuration tests run
before the two platform jobs. Successful builds provide downloadable Actions
artifacts for 30 days; no GitHub Release or TestFlight upload is performed.

- `cf-monitor-android-<run>`: three release APKs for ARMv7, ARM64, and x86_64.
- `cf-monitor-ios-<run>`: one signed IPA.

Flutter is pinned to 3.44.1. Android uses Java 21 on Ubuntu; iOS uses the
`macos-15` runner and CocoaPods. The Actions run number supplies the build number.

## Android signing

The project uses its own release keystore, independently of EasyNode. These
repository Actions secrets are required:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release JKS |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Private key password |
| `ANDROID_KEY_ALIAS` | Signing key alias |

CI restores signing files temporarily, then verifies the certificate of every
APK against the restored release key. Gradle refuses release tasks when the
signing configuration is missing; it never falls back to the debug key.

Local signing backups are kept in `.signing/android/` with restricted file
permissions. That directory and `android/key.properties` are ignored by Git.
Keep a separate private backup of the JKS and its credentials: updates to an
installed app must retain the same signing key. `android/key.properties.example`
documents the local configuration format without including any credentials.

## Apple signing

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Base64-encoded P12 containing the selected certificate and private key |
| `IOS_CERTIFICATE_PASSWORD` | P12 password |
| `IOS_PROVISIONING_PROFILE_BASE64` | Matching `.mobileprovision` file |

The iOS bundle ID is `dev.cfmonitor.cfMonitorApp`. CI imports the certificate
into a temporary keychain, checks the profile's expiry and bundle ID, and selects
an imported identity whose certificate is included in the profile. Only the
Runner target receives manual signing overrides; CocoaPods targets are left
to their own signing configuration. The exported IPA is checked for its code
signature, bundle ID, signing certificate, and embedded profile.

The initial setup uses the existing **Apple Development** identity and matching
wildcard development profile. It exports a development-signed IPA (`debugging`)
for devices registered in that profile. This is not an App Store or general
distribution package. To use distribution signing later, replace the P12 and
profile secrets together; CI determines the export method from the profile.

The selected identity's encrypted local backup and its password are kept in
`.signing/ios/`, ignored by Git. CI removes temporary signing files and its
keychain even when a build fails. Certificates and private keys are never
uploaded as workflow artifacts.
