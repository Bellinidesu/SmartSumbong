// SmartSumbong — the barangay's own wording on the phone (0149).
//
// A super admin can replace any label (Settings > Wording in the portal):
// the wording table holds the English text the code carries and what to
// show instead, in English, Tagalog or both. Every _t() and context.tr()
// asks here first. The last copy is kept (JsonCache); before the first
// one, the code's own wording shows.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Wording {
  Wording._();

  static const _cacheKey = 'wording';

  static Map<String, (String?, String?)> _own = const {};
  static Future<void>? _loading;

  /// The string to show: the barangay's wording for [en] when it has one, else the code's.
  static String pick(String en, String fil, {required bool filipino}) {
    final o = _own[en];
    if (o == null) return filipino ? fil : en;
    return filipino ? (o.$2 ?? fil) : (o.$1 ?? en);
  }

  static Future<void> loadCached() async {
    final c = await JsonCache.read(_cacheKey);
    if (c is List) apply(c);
  }

  /// Asks the database again (once at a time). Never throws.
  static Future<void> refresh() => _loading ??= _fetch().whenComplete(() => _loading = null);

  static Future<void> _fetch() async {
    try {
      final r = await Supabase.instance.client.from('wording').select('source,en,fil').timeout(const Duration(seconds: 10));
      apply(r);
      unawaited(JsonCache.write(_cacheKey, r));
    } catch (_) {}
  }

  /// Takes the rows of the wording table (an empty list: every label says its own again).
  @visibleForTesting
  static void apply(List rows) {
    _own = {
      for (final r in rows)
        if (r is Map && r['source'] is String) r['source'] as String: (r['en'] as String?, r['fil'] as String?),
    };
  }
}
