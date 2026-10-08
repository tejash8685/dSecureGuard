# D SecureGuard — Android and iOS

Product branding and launcher icons use D SecureGuard. The Dart package is
`d_secureguard`. Existing Android/iOS application IDs, Windows project folder,
method-channel names, storage keys and signing key are retained for compatibility.
The logo master and regeneration instructions are under `assets/branding/`.

The mobile app uses the same API and role-based management flow as the web app.

## Android interface

Material 3 styling provides phone-friendly bottom navigation, a responsive overview,
status badges, searchable lists, clear Accept/Reject controls, an Account screen,
pull-to-refresh, and sticky save buttons on forms. Administrator navigation includes
Home, Requests, Products, Users, and Account; assignments and device activation are
available under Account. User navigation includes Home, Products, Requests, and
Account. Existing roles, permissions, login and background monitoring continue to
use the same API.

- Administrator: dashboard statistics and recent records, users and permissions,
  products, assignments, activation Accept/Reject/Deactivate, and full details.
- User: dashboard, assigned products and activations, profile, and Accept/Reject
  where the account has activation permission and an active assignment.
- Login is stored in Android secure storage until the server's 10-hour JWT expires.
  Passwords are not stored. Logout and expiry clear all authenticated screens.
- The same administrator credentials work simultaneously on web and Android.
  Regular user accounts retain the existing single-device binding policy.
- Authentication codes are entered manually as digits and filled when editing.
- Activation filters: All, Pending, Approved, Deactivated; rejected records appear in All.
- Pending-request badges refresh every 15 seconds while open and on resume.
- After login, a native foreground service checks the API every 30 seconds with
  a permanent "Monitoring activation requests" notification. It continues after
  leaving or swiping away the app, independently of Flutter, and alerts for newly
  observed pending requests. Tap an alert to open Pending. Existing requests at
  initial startup form the baseline rather than generating repeated alerts.
- Allow Android notification permission. The monitoring token is encrypted with
  an Android Keystore key; logout, HTTP 401 and session expiry stop monitoring.
  No Firebase account or additional package is needed for this polling mode.
- Android 15+ limits dataSync foreground services to six background hours; the
  service handles the timeout safely. Reopening the app restarts monitoring;
  "Restart background alerts" is also available in the menu. Force-stop,
  stopping the service in Android's Active apps controls, device reboot, battery
  restrictions or no network may prevent/delay alerts. This is polling, not
  push delivery, and timing is not guaranteed while the phone is asleep.
  See https://developer.android.com/develop/background-work/services/fgs/timeout.
- Device activation requests are available under Account after login, with
  saved requests, status refresh, and status-change notifications.

## Configure the API address

The default is the local IIS API `http://192.168.1.110:8080/api`, so a plain
`flutter build apk --split-per-abi` uses the same API as the IDE run configuration.
To use another host, override `API_URL` when building, for example:

```sh
flutter build apk --split-per-abi --dart-define=API_URL=http://192.168.1.110:8080/api
```

The API host must allow inbound connections on port 8080. Plain HTTP is enabled for
local development. Use HTTPS for production.

## VS Code build

Open the `DharmajFlutter` folder and press Ctrl+Shift+B to run "Build Android split
APKs". The local task uses the installed Flutter SDK and JDK 21. For debugging,
select "D SecureGuard (local IIS)" and an Android device, then press F5.

The Android Gradle settings limit worker/memory use and disable Kotlin incremental
compilation to avoid the C: pub-cache / D: project "different roots" cache error.
This can make Kotlin rebuilds slower. Do not run several builds concurrently.

If a build fails with just `25.0.3`, it is using Android Studio's bundled Java 25.
The project pins the Gradle daemon to JDK 21 in
`android/gradle/gradle-daemon-jvm.properties`. Workspace settings also select
`C:\src\flutter` and JDK 21 for new VS Code terminals; settings exist for both
the Activation root and DharmajFlutter folder. Close existing terminals and run
"Developer: Reload Window", then create a new terminal to pick up the settings.
JDK 21 must remain installed locally; other computers must install it and adjust
the machine-specific VS Code SDK paths as needed.

## Build and analyze

```sh
flutter analyze
flutter build apk --release
```

Split APKs are written to `build/app/outputs/flutter-apk/` for ARM32, ARM64, and x86_64.
Release builds use a dedicated signing key from the ignored `android/key.properties`
and `android/app/dharmaj-release.jks` files. Debug builds retain the development key.

## Protected Android release

Build distributable APKs with the VS Code build task or:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/Build-SecureApk.ps1
```

The script enables Dart name obfuscation and removes Dart debug information from
the APK. Release Gradle settings enable R8 Java/Kotlin shrinking and obfuscation,
resource shrinking, and disable debugging. Android backup and device transfer of
private app data are disabled. Login sessions remain in secure storage and native
monitoring tokens use AES-GCM with an Android Keystore key; passwords are not saved.
No database password, JWT signing key or custom decryption key is embedded in the app.

Each protected build saves its Dart symbols, Android R8 mapping and APK SHA-256
hashes in `artifacts/android-symbols/<build-id>/`. Archive these privately with the
corresponding release so crash reports can be decoded; do not distribute them with
the APK. A plain `flutter build apk` does not enable Dart obfuscation; use the script
for every distribution build.

For a new app only, initialize signing once with
`scripts/Initialize-AndroidSigning.ps1` (requires JDK `keytool`). Existing apps must
restore/reuse their signing files. Back up the keystore and properties privately;
losing them can prevent updates. This project's older APKs were signed with the
debug key. Android cannot install this new release over those APKs because the
signatures differ; uninstalling the development app first removes its local session
and device installation ID and may require regular users' device binding to be reset.

Obfuscation makes reverse engineering harder; it cannot encrypt all APK content or
guarantee protection on a compromised device. Permissions and business rules must
remain enforced by the API. The current local HTTP endpoint still sends login
traffic without transport encryption. Configure a trusted HTTPS API and build with
`-ApiUrl https://your-host/api` for production. The anonymous legacy API endpoint
`/api/User/GetConMulti` returns database credentials encrypted with a legacy shared
key, which can be decrypted independently of APK protection;
Android does not call it. Restrict that endpoint on the server before public hosting.

References: [Flutter obfuscation](https://docs.flutter.dev/deployment/obfuscate),
[Android R8](https://developer.android.com/topic/performance/app-optimization/enable-app-optimization).

## Check background alerts

1. Install the updated APK, sign in and allow notifications.
2. Confirm "Monitoring activation requests" appears in Android notifications.
3. Swipe the app away, then submit a new activation request for an active product
   through another device/client. An administrator sees all active-product
   requests; regular users see only products they can manage under active assignments.
4. With the phone awake and API reachable, wait approximately 30 seconds and
   tap the new-request alert. The app opens the Pending list.
5. Log out and confirm the monitoring notification disappears.

## iOS build on a Mac

To build from Windows using a cloud Mac, follow [Codemagic setup](CODEMAGIC-SETUP.md).

The `ios/` Xcode project targets iOS 13 or newer and includes device identification,
Keychain login storage, notification permission/local notifications and notification
tap navigation. Android fingerprints are unchanged; iOS requests use IOS hardware
markers and the vendor identifier with the app's securely saved installation ID.
The iOS project has been prepared on Windows but has not been compiled or run in Xcode.

1. Copy this project to a Mac with Flutter, Xcode's iOS SDK and CocoaPods installed.
2. Run `flutter pub get`, then `cd ios && pod install && cd ..`.
3. Open `ios/Runner.xcworkspace` in Xcode. Select Runner, set your unique bundle
   identifier and Apple signing team under Signing & Capabilities. Keep Keychain
   Sharing enabled. Distribution requires a suitable certificate/provisioning profile.
4. Connect an iPhone on the API server's LAN and allow Local Network and notification
   permissions. Use a trusted HTTPS API for production. The local-network ATS allowance
   is only intended for local IIS use; no global arbitrary-load exemption is enabled.
5. Run `bash scripts/build-ios.sh` to build an obfuscated, signed IPA. Optionally pass
   your HTTPS API URL as the first argument. The IPA is written under `build/ios/ipa/`,
   and private Dart crash symbols under `artifacts/ios-symbols/<build-id>/`.

Windows cannot compile/sign an iOS IPA. See [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup)
and [iOS release builds](https://docs.flutter.dev/deployment/ios).

The Android foreground polling service is Android-only. On iOS, request lists and
local alerts refresh while the app is open; detecting new requests after the app is
closed requires APNs/FCM push notifications and server configuration, which is not
included in this build preparation. See [Apple background notifications](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).
