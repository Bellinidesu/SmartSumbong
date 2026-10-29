// SmartSumbong — the barangay's name and place on the phone (0148).
//
// barangay_profile is one row a super admin edits in the portal (Settings >
// Appearance): "Barangay 183", "Zone 20, Villamor, Pasay City". Readable
// before signing in, so the welcome screens use it too. The last answer is
// kept (JsonCache); before the first one ever, the values below stand in.
// The seal stays the one shipped in the app: it shows offline, at once.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BarangayProfile {
  BarangayProfile._();

  static const _cacheKey = 'barangay_profile';

  static String _name = 'Barangay 183';
  static String _place = 'Zone 20, Villamor, Pasay City';
  static Future<void>? _loading;

  /// "Barangay 183".
  static String get name => _name;

  /// "Zone 20, Villamor, Pasay City".
  static String get place => _place;

  /// The last part of the place: "Pasay City".
  static String get city => _place.split(',').last.trim();

  /// The city in Tagalog: "Lungsod ng Pasay".
  static String get cityFil {
    final m = RegExp(r'^(.+) City$').firstMatch(city);
    return m == null ? city : 'Lungsod ng ${m.group(1)}';
  }

  static Future<void> loadCached() async {
    final c = await JsonCache.read(_cacheKey);
    if (c is Map) apply(c);
  }

  /// Asks the database again (once at a time). Never throws.
  static Future<void> refresh() => _loading ??= _fetch().whenComplete(() => _loading = null);

  static Future<void> _fetch() async {
    try {
      final r = await Supabase.instance.client.from('barangay_profile').select('name,place').eq('id', 1).maybeSingle().timeout(const Duration(seconds: 10));
      if (r != null && apply(r)) unawaited(JsonCache.write(_cacheKey, r));
    } catch (_) {}
  }

  /// Takes a row of barangay_profile; false (and nothing changed) when it is not one.
  @visibleForTesting
  static bool apply(Map row) {
    final n = row['name'], p = row['place'];
    if (n is! String || p is! String || n.trim().length < 3 || p.trim().length < 3) return false;
    _name = n.trim();
    _place = p.trim();
    return true;
  }
}
