// SmartSumbong — encrypted session storage.
//
// supabase_flutter's default LocalStorage is SharedPreferences: a plain
// XML/plist file, unencrypted, readable by anything with a file-manager
// app and the right permissions on a rooted or compromised phone. A
// resident's or tanod's session (access + refresh token) sits there for
// as long as they stay signed in on a personal device. flutter_secure_
// storage backs onto the Android Keystore instead, which is the same
// place a password manager keeps its secrets.
//
// This does not change what supabase_flutter does with the session, only
// where the serialized session string is written and read from — see
// Supabase.initialize's authOptions in each app's main.dart.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureLocalStorage extends LocalStorage {
  static const _key = 'smartsumbong.supabase_session';
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() async =>
      (await _storage.read(key: _key)) != null;

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
