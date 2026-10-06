// Remembered sign-in details, one set per role (Ace, 6 Oct 2026): a phone
// used by someone who is both a resident and a tanod shows the resident
// number and password on the resident login and the tanod ones on the
// tanod login. Kept in the platform's encrypted storage (Android Keystore,
// like the session in secure_session_storage.dart), only while "Remember
// me" is on, and never in a backup (allowBackup is off).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth.dart';

class SavedLogin {
  const SavedLogin({required this.mobile, required this.password});

  final String mobile;
  final String password;
}

class SavedLogins {
  SavedLogins._();

  static const _storage = FlutterSecureStorage();

  static String _key(String role, String what) => 'saved_login_${role}_$what';

  /// The details remembered for [role] ('resident' or 'tanod'), if any.
  static Future<SavedLogin?> read(String role) async {
    try {
      final mobile = await _storage.read(key: _key(role, 'mobile'));
      if (mobile == null || mobile.isEmpty) return null;
      final password = await _storage.read(key: _key(role, 'password')) ?? '';
      return SavedLogin(mobile: mobile, password: password);
    } catch (_) {
      return null; // storage unavailable: the login simply starts empty
    }
  }

  static Future<void> write(String role, String mobile, String password) async {
    try {
      await _storage.write(key: _key(role, 'mobile'), value: mobile);
      await _storage.write(key: _key(role, 'password'), value: password);
    } catch (_) {}
  }

  static Future<void> forget(String role) async {
    try {
      await _storage.delete(key: _key(role, 'mobile'));
      await _storage.delete(key: _key(role, 'password'));
    } catch (_) {}
  }

  /// After a password change: the remembered password for [role] follows,
  /// but only if that role has one saved for this same number.
  static Future<void> updatePassword(String role, String mobile, String password) async {
    final saved = await read(role);
    if (saved != null && AuthService.normaliseMobile(saved.mobile) == AuthService.normaliseMobile(mobile)) {
      await write(role, saved.mobile, password);
    }
  }
}
