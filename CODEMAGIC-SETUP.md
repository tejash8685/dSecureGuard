# Build iOS from Windows with Codemagic

## Prepared workflows

`codemagic.yaml` pins Flutter 3.29.3 and Xcode 16.4 on a cloud Mac. Builds run
manually; the configuration does not automatically upload to TestFlight or an app store.

- **ios-compile:** compiles the obfuscated iOS app without Apple signing. The
  resulting unsigned archive cannot be installed on your iPhone. Use it to check
  whether the prepared native iOS project compiles on macOS.
- **ios-device:** creates an obfuscated Ad Hoc IPA using Apple signing files
  stored in your Codemagic team. Only devices registered in the provisioning
  profile can install it.

No cloud build has run yet. iOS native code is not verified until that first build.

## Connect the project

1. Create a private GitHub, GitLab or Bitbucket repository with **DharmajFlutter as
   its root**, then upload the mobile project's source. Keep `codemagic.yaml` at
   that repository's root. Do not upload the parent Activation directory: it
   contains server configuration and local deployment secrets.
2. Exclude Android signing files, private keys, build outputs and private crash
   symbols. The project's `.gitignore` handles these files. Keep your own backups
   of signing keys so future Android releases remain compatible.
3. Sign in at https://codemagic.io/apps, select **Add application**, connect the
   repository and select Flutter. Scan the branch for `codemagic.yaml`.
4. Run **ios-compile** first. Download the logs if it fails; this workflow does
   not need Apple signing credentials, but cloud build minutes can have a cost.

If the whole Activation solution is already in a repository, Codemagic requires
configuration at that repository root and scripts must explicitly enter
`DharmajFlutter`. This supplied file is for a mobile-only repository; do not copy
it to a parent repository unchanged.

## Produce an IPA for your iPhone

1. Apple Developer Program membership is required for this Ad Hoc distribution.
2. Register a unique Apple bundle ID and your iPhone's UDID in the Apple Developer
   portal. Create an Apple Distribution certificate and an Ad Hoc provisioning
   profile that includes your device and the required Keychain capability.
3. In Codemagic **Team settings → codemagic.yaml settings → Code signing
   identities**, upload the iOS certificate (including its private key, usually
   `.p12`) and matching provisioning profile (`.mobileprovision`). If you do not
   have a certificate, Codemagic's Developer Portal integration can generate one
   after you connect an App Store Connect API key. Upload these secrets directly
   to Codemagic; do not commit them or send them in chat.
4. Replace **both** `com.example.dharmajFlutter` values in the signed workflow's
   `ios_signing.bundle_identifier` and `IOS_BUNDLE_ID` with your registered ID.
   The workflow applies that ID to the Xcode project before signing.
5. Run **ios-device**. Its build artifacts contain the signed `.ipa` and private
   crash symbols. Install through Codemagic's device installation link on the
   registered iPhone. Symbols contain debugging information: restrict artifact
   access and distribute only the IPA to users.

The configured API is `http://192.168.1.110:8080/api`. The installed iPhone must
be on the same local network and allow Local Network permission. The cloud Mac
does not need to reach this API to compile. For devices outside the LAN, use a
reachable trusted HTTPS API and update `API_URL`. iOS push notifications after
closing the app require separate APNs/FCM server setup.

References: [Codemagic Flutter configuration](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/),
[iOS signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/).
