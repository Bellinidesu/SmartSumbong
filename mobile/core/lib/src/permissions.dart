// SmartSumbong — camera and gallery permission prompts.
//
// The team's own screenshot during the QA exchange (26 Aug 2026) — a
// phone's Settings → App → Permissions page showing nothing listed —
// was the actual complaint: nothing in this app ever explained, in its
// own words, why it wants the camera or the gallery before asking for
// them. image_picker and geolocator both request their own permissions
// when they need to, and that already worked (see the note on
// _locate() in report_details_screen.dart) — what was missing was the
// app-side rationale in between "resident taps a button" and "Android's
// dialog appears", which is the only part a plugin cannot supply for
// you, because it doesn't know why *your* app wants it.
//
// WHY OUR OWN AppPermission ENUM, NOT permission_handler'S Permission
// DIRECTLY. Same reasoning as Strings in i18n.dart: exactly one file
// should import the underlying package, so every screen goes through
// one gate that already knows what to say and what to do when it's
// denied, rather than five copies of the same three-state dance.
//
// A NOTE ON WHY THE DIALOG BELOW SOMETIMES NEVER APPEARS. Android 13+'s
// system Photo Picker — what image_picker uses for ImageSource.gallery —
// needs no runtime permission at all; it grants access to only the
// items the resident actually taps, without the app ever holding a
// standing "read all photos" grant. That is Android choosing not to ask,
// on purpose, for privacy reasons better than anything this app could
// build itself — not a bug, and not this file failing to show a prompt.
// AppPermission.photos still exists for the versions where it matters
// (Android 12 and below, where image_picker falls back to a real
// gallery read needing READ_EXTERNAL_STORAGE) and is harmless to check
// on newer versions, where it simply reports already-granted.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

enum AppPermission { camera, photos }

extension on AppPermission {
  ph.Permission get _underlying => switch (this) {
        AppPermission.camera => ph.Permission.camera,
        AppPermission.photos => ph.Permission.photos,
      };
}

/// Asks once, explains first. `ensure()` is the only entry point: it
/// checks the current status, shows [rationale] before Android's own
/// dialog if a request is actually going to happen, requests, and — if
/// the resident denied it before and Android will no longer ask again —
/// offers a way to Settings instead of failing silently.
class PermissionGate {
  const PermissionGate._();

  /// True only if the permission ends up granted (or, on iOS,
  /// [ph.PermissionStatus.limited] — partial photo-library access,
  /// which is enough to pick a photo). False for every other outcome,
  /// including the resident dismissing this app's own rationale dialog
  /// before Android's ever appears.
  static Future<bool> ensure(
    BuildContext context, {
    required AppPermission permission,
    required String title,
    required String rationale,
  }) async {
    final p = permission._underlying;

    final current = await p.status;
    if (current.isGranted || current.isLimited) return true;
    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(rationale),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return false;

    final result = await p.request();
    if (result.isGranted || result.isLimited) return true;

    // Android stops showing its own dialog after a resident denies
    // twice — a third .request() call would just silently return
    // denied forever with no way back except Settings, so this is the
    // one case worth a second dialog rather than just failing quietly.
    if (result.isPermanentlyDenied && context.mounted) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Permission turned off'),
          content: Text(
            '$title is turned off for SmartSumbong. Open Settings to '
            'allow it, then try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) await ph.openAppSettings();
    }

    return false;
  }
}
