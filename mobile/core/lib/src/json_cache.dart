// SmartSumbong — the last-seen copy of each screen's data (branch B).
//
// Screens open on what was loaded last time, at once, then refresh from
// the network; with no signal they keep showing that copy (the offline
// strip already says why) instead of an error. The way professional
// apps behave on patchy mobile data.
//
// Private app storage, one folder per signed-in account, so a phone
// shared between two residents never shows one the other's reports; the
// whole cache goes on sign-out (AuthService.signOut). Values are the
// JSON the API returned, stored as-is.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JsonCache {
  JsonCache._();

  static Future<Directory?> _dir({bool create = false}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/screen_cache/$uid');
    if (create && !await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _name(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  /// The last copy stored under [key] for the signed-in account, or null.
  static Future<Object?> read(String key) async {
    try {
      final d = await _dir();
      if (d == null) return null;
      final f = File('${d.path}/${_name(key)}.json');
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null; // A bad cache is no cache.
    }
  }

  /// Replaces the copy under [key]. Never throws: a cache that cannot be
  /// written only costs the next open its head start.
  static Future<void> write(String key, Object? value) async {
    try {
      final d = await _dir(create: true);
      if (d == null) return;
      final f = File('${d.path}/${_name(key)}.json');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(value));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Every account's cache, gone — on sign-out.
  static Future<void> clearAll() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/screen_cache');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}
