# smartsumbong_core

The shared Flutter package behind the [SmartSumbong app](../resident): the
services every screen relies on, kept apart from the screens so they can be
tested and reused. Not published; the app depends on it by path.

| File (`lib/src/`) | Does |
|---|---|
| `auth.dart` | sign-in, registration, sign-out, password changes against Supabase Auth |
| `secure_session_storage.dart` | keeps the session tokens in the OS keystore, not in plain preferences |
| `saved_login.dart` | remembered sign-in details, one set per role |
| `biometric_auth.dart`, `biometric_lock_gate.dart` | fingerprint or face unlock, and the lock when the app returns from the background |
| `media_upload.dart` | photo and video uploads to Cloudinary: signed by the `sign-upload` function, EXIF stripped first, the unsigned preset only as a fallback |
| `video_location_strip.dart` | strips location metadata from videos |
| `media_viewer.dart` | shared video playback |
| `push_notifications.dart` | registers the device's FCM token and opens the right screen from a push |
| `crash_reporting.dart` | Firebase Crashlytics |
| `id_ocr.dart` | on-device ML Kit reading of ID photos (`kIdOcrEnabled`, off); only what it reads is sent, the server judges it |
| `json_cache.dart` | the last-seen copy of each screen's data, for opening offline |
| `connectivity_banner.dart` | the offline strip |
| `permissions.dart` | camera and gallery permission prompts |
| `names.dart` | how a name is written: casual "Ace Lediac" for greetings, formal "Lediac, Ace" for records, as the portal |
| `app_dialog.dart` | the design's dialog card for core's own prompts |

`lib/smartsumbong_core.dart` exports them.

```bash
flutter pub get
flutter analyze      # must report nothing
flutter test
```

Nothing here may hold a secret: everything in this package ships inside the
APK.
