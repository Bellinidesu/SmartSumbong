// SmartSumbong — Face ID / fingerprint unlock.
//
// Shared by both apps: identical mechanics for a resident and a tanod,
// nothing here is role-specific. A "password alternative" in one narrow
// sense only -- it never touches Supabase, and it never touches the
// account's actual credential. What it gates is purely local: whether
// each app's own launch_gate.dart is allowed to silently restore an
// already-remembered session on cold start (see biometric_lock_gate.dart
// for the second half -- gating a resume from the background, not just a
// cold start). A declined, failed, cancelled, or unsupported prompt
// always falls back to the password screen; it never signs anyone out on
// its own and never blocks anyone who has not opted in via their app's
// Settings toggle.
//
// local_auth reads whatever fingerprint or face the resident or tanod
// already enrolled in their phone's own OS settings. Nothing captured by
// that scan ever reaches this app's code, let alone SmartSumbong's
// servers -- the OS hands back only a yes/no.
//
// Android native setup this package needs, done separately in EACH app's
// own Android project (not shared, unlike this Dart code): MainActivity
// must extend FlutterFragmentActivity rather than FlutterActivity
// (local_auth's biometric prompt is an androidx Fragment), and
// AndroidManifest.xml needs the USE_BIOMETRIC permission.

import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this handset should gate a remembered session behind Face ID
/// / fingerprint. Off by default -- opt-in, set from each app's Settings
/// toggle. Absent means off, the opposite default from a "remember me"
/// flag: an unset "remember me" means an existing install keeps working
/// the way it always did, but an unset biometric flag must not suddenly
/// start demanding a prompt nobody turned on.
const biometricUnlockKey = 'biometric_unlock_enabled';

class BiometricAuthService {
  final _auth = LocalAuthentication();

  /// True only when the phone both supports biometrics and already has at
  /// least one fingerprint or face enrolled in its own OS settings.
  /// canCheckBiometrics alone can be true on hardware that supports the
  /// sensor with nothing enrolled yet, which would surface as an empty,
  /// confusing system dialog rather than a clean "not available" message
  /// -- checking getAvailableBiometrics() is what actually answers "would
  /// a prompt right now have anything to check against."
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Shows the OS's own Face ID / fingerprint prompt. Returns false --
  /// never throws -- for every failure case: a decline, a cancel, a
  /// system lockout after too many bad attempts, or a platform error.
  /// Deliberately not distinguished, because every caller does the exact
  /// same thing on any of them: fall back to the password screen. Nobody
  /// is worse off for this returning false than they would be if the
  /// feature did not exist at all.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
        biometricOnly: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Absent or unreadable means off -- see [biometricUnlockKey].
  static Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(biometricUnlockKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(biometricUnlockKey, value);
    } catch (_) {
      // Storage unavailable: the toggle did not persist, so the next
      // cold start behaves as though it were never turned on -- the
      // safer of the two directions for this to fail in, same reasoning
      // as every other SharedPreferences write in either app.
    }
  }
}
