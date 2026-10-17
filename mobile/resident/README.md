# SmartSumbong app

The Android app for **residents and tanods** of Barangay 183, in one APK. The
role picked at sign-in decides the screens, the colours (navy for residents,
ink for tanods) and the bottom bar. Package `ph.smartsumbong.resident`;
minimum Android 7.0. Shared services come from [`../core`](../core).

## Run it

```bash
flutter pub get
flutter run --dart-define-from-file=dart_defines.json        # against the configured Supabase project
flutter run -d web-server --web-port 5000 -t lib/main_preview.dart
```

The second command is the **preview**: the real screens, theme and navigation
over an in-memory backend, no account or network needed. Open
http://localhost:5000; add `?role=tanod` to start as the demo tanod, or
`?role=none` to start signed out (0927 126 9625 with any password signs in as
the tanod, any other number as the demo resident).

## Build a release

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=dart_defines.json
```

`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` for almost every
phone, `app-armeabi-v7a-release.apk` for 32-bit ones. With
`android/key.properties` present (never committed) the APK is signed with the
barangay's release key; without it, with the debug key. CI fails a release
APK over 60 MB. Signing and Firebase setup: [DEPLOY.md](../../DEPLOY.md),
section 7.

`dart_defines.json` is committed and holds only public client values (the
Supabase URL and publishable key, Cloudinary's cloud name and presets).
Never put a secret in it: anything in an APK can be read out of it.

## Inside

```
lib/main.dart             start-up: Firebase, Supabase, routes, the launch gate, the tablet frame
lib/main_preview.dart     the preview's entry point (lib/preview/: fake backend and demo data)
lib/screens/              resident screens, and the shared ones (sign-in, settings, profile)
lib/tanod/                tanod screens: home, dispatch order and window, navigation, history
lib/d/                    the design system: DColors, DPage, DCard, DButton, switches, flood watch
lib/widgets/              the map (MapLibre), the nav bar, Figma-matched parts
lib/outbox.dart           complaints filed without signal, sent once when the phone reconnects
lib/i18n.dart             English and Filipino for every string
lib/theme.dart            light and dark, per role
```

- **Sign-in** is by mobile number; Supabase sees a derived address that can
  receive no mail. Remembered sign-in is per role; biometric unlock optional.
- **Offline**: every main screen opens on its last saved copy and refreshes
  when it can; a complaint filed without signal waits in the outbox.
- **Location**: a tanod's position is taken only at key moments (on duty,
  returning to the app, each dispatch step, starting navigation).
- **Switches**: `kIdOcrEnabled` (on-device ID reading, in core) and
  `kSmsResetEnabled` (SMS codes, `lib/screens/forgot_password_screen.dart`)
  are off until the barangay turns them on.

## Tests

```bash
flutter analyze      # must report nothing
flutter test
```

| Test | Covers |
|---|---|
| `sign_in_flow_test.dart` | signing in, on the real screens over the preview backend |
| `resident_flow_test.dart` | a resident's own reports |
| `tanod_flow_test.dart` | a tanod's dispatch |
| `preview_smoke_test.dart` | opens every preview screen and fails on any error |
| `accessibility_test.dart` | touch targets, contrast, 200% text on the main screens |
| `translations_test.dart` | every English string has its Filipino |
