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

## Release APKs

M2 release APKs are signed with the debug key: they are for development only, not for
distribution. A store-signed build cannot update them, so a tester would have to uninstall and lose
keys and chats. Release signing comes with M3.

`make app-apk CHAMA_BASE_URL=https://chama.example` builds one APK per ABI (arm64-v8a,
armeabi-v7a, x86_64). `CHAMA_BASE_URL` is required and must be `https://`: release and profile
builds refuse to start without it. Android's `network_security_config.xml` (HTTPS only) does not
cover Dart's own HTTP client, so this check is what keeps codes and tokens off cleartext HTTP.
