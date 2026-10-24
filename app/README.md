# Chama app

One Flutter app for Android and the web (iOS and desktop later), built on the
[matrix](https://pub.dev/packages/matrix) Dart SDK with vodozemac for end-to-end encryption.

## Run

Prerequisites: Flutter 3.47.8, rustup (vodozemac compiles from Rust for Android and the web), the
Android SDK with the NDK and an emulator (AVD), and Chrome.

Start the server stack first (`make up` at the repo root). Then:

- Android emulator: start the AVD, then `make app-android`.
- Chrome: `make app-web` (the first run builds vodozemac for the web, about 10 minutes).

Sign in with any Brazilian mobile number (for example `11 91234-5678`) and the code `000000`
(development stack only).

## Test

- `make app-test`: unit and widget tests.
- `make app-e2e-web`, `make app-e2e-android`: the app chats with a scripted peer (`tools/peer`)
  against the local stack. `scripts/e2e.sh <chrome|android> <file>` runs one integration test.
  Android boots the first AVD unless `CHAMA_AVD=<name>` is set. Chrome is found at the macOS path;
  elsewhere set `CHROME=<path to the chrome binary>`.

## Code map

- `lib/services/`: the only code that talks to the Matrix SDK. Widgets get plain models.
- `lib/auth`, `lib/chat_list`, `lib/chat`, `lib/group`, `lib/profile`, `lib/common`: one folder per feature.
- Strings: `lib/l10n/app_pt.arb` (Portuguese, the template) and `app_en.arb`.
- Colours: `lib/common/theme.dart` only.

## Contacts

After sign-in the app reads the address book (READ_CONTACTS; New chat explains why before Android asks) and asks
chama-id which numbers have an account. Only SHA-256 hashes of the numbers leave the phone, each number at most once
a day, at most 1000 per request (docs/chama-id-api.md, "Contact lookup privacy"). Saved names replace display names
everywhere. Without the permission, chats start by typing a number.

## Push notifications

Pushes come through UnifiedPush: the user's distributor app (for example ntfy) or, in the Play build, FCM through
UnifiedPush's embedded distributor. The server (Synapse pusher → Sygnal) sends only room and event IDs, encrypted with
Web Push; the app fetches and decrypts the message and shows it. Without a distributor, Settings → Notificações says so.

On the emulator: start the stack (`make up`) and the emulator, then run `./scripts/ntfy-setup.sh` once. It installs
ntfy and points it at the stack's ntfy (`http://10.0.2.2:8081`).

## Release builds

Two flavors: `fdroid` (the default, no Google code; push needs a UnifiedPush app such as ntfy) and
`play` (adds UnifiedPush's embedded FCM distributor, so push works without one).

- `make app-apk CHAMA_BASE_URL=https://chama.example`: one fdroid APK per ABI (arm64-v8a,
  armeabi-v7a, x86_64) in `build/app/outputs/flutter-apk/`.
- `make app-aab CHAMA_BASE_URL=https://chama.example`: the Play Store bundle,
  `build/app/outputs/bundle/playRelease/app-play-release.aab`.

`CHAMA_BASE_URL` is required and must be `https://`: release and profile builds refuse to start
without it. Android's `network_security_config.xml` (HTTPS only) does not cover Dart's own HTTP
client, so this check is what keeps codes and tokens off cleartext HTTP.

Signing reads the key from the environment, never from the repo: `CHAMA_KEYSTORE` (path to a .jks or
.p12 file outside the repo), `CHAMA_KEYSTORE_PASSWORD`, `CHAMA_KEY_ALIAS` and `CHAMA_KEY_PASSWORD`.
Without them a release build stops with an error. For local testing only, `CHAMA_ALLOW_DEBUG_KEY=1`
signs with the debug key and the version name ends in `-debugkey`; the stores refuse such builds,
and a store-signed build cannot update them (a tester would have to uninstall and lose keys and
chats).

For a store that signs the APK itself (the F-Droid build server), `CHAMA_UNSIGNED=1` builds the
release unsigned and ignores the variables above, for example
`CHAMA_UNSIGNED=1 flutter build apk --release --flavor fdroid --dart-define=CHAMA_BASE_URL=https://chama.example`.
The APK is `build/app/outputs/flutter-apk/app-fdroid-release.apk` (unsigned: it does not install
until signed).

Version: `version: <name>+<code>` in pubspec.yaml. Raise the code for every release; split APKs get
1000 × ABI number on top (armeabi-v7a 1, arm64-v8a 2, x86_64 4).
