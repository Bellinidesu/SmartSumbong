// SmartSumbong — the barangay's complaint catalogue on the phone (0146).
//
// complaint_catalogue() answers with the categories residents can pick and
// the options under each, in the barangay's order. The last answer is kept
// (JsonCache), so a cold start with no signal still shows what the barangay
// set; before the first answer ever, the built-in list stands in.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'complaint_category.dart';

class ComplaintCatalogue {
  ComplaintCatalogue._();

  static const _cacheKey = 'complaint_catalogue';

  static List<ComplaintCategory> _current = ComplaintCategory.builtIn;

  /// Every category this phone has seen, switched off ones too, so an old
  /// report keeps its name and colour after the barangay retires its category.
  static final Map<String, ComplaintCategory> _seen = {for (final c in ComplaintCategory.builtIn) c.wire: c};

  static Future<void>? _loading;

  /// What residents can pick, in order.
  static List<ComplaintCategory> get current => _current;

  /// A category by its key, if this phone has seen it.
  static ComplaintCategory? find(String wire) => _seen[wire];

  /// The copy kept from last time; quick, and safe to await before the first frame.
  static Future<void> loadCached() async {
    final c = await JsonCache.read(_cacheKey);
    if (c is List) apply(c);
  }

  /// Asks the database again (once at a time). Never throws: no signal keeps what is there.
  static Future<void> refresh() => _loading ??= _fetch().whenComplete(() => _loading = null);

  static Future<void> _fetch() async {
    try {
      final r = await Supabase.instance.client.rpc('complaint_catalogue').timeout(const Duration(seconds: 10));
      if (r is List && r.isNotEmpty && apply(r)) unawaited(JsonCache.write(_cacheKey, r));
    } catch (_) {}
  }

  /// Takes the Control Room's draft (live preview, 0160): its categories as the forms say them right now, in the portal's own field names.
  /// A category not made yet has no key and is given a stand-in one. false (and nothing changed) when no category would show.
  static bool applyDraft(List cats) {
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < cats.length; i++) {
      final c = cats[i];
      if (c is! Map) continue;
      final key = c['key'];
      rows.add({
        'key': key is String && key.isNotEmpty ? key : 'draft_$i',
        'en': c['label_en'],
        'fil': c['label_fil'],
        'colour': c['colour'],
        'icon': c['icon'],
        'active': c['active'],
        'options': [
          for (final o in (c['options'] as List? ?? const []))
            if (o is Map) {'en': o['label_en'], 'fil': o['label_fil'], 'active': o['active']},
        ],
      });
    }
    return apply(rows);
  }

  /// Takes an answer of complaint_catalogue(); false (and nothing changed) when it holds no category.
  @visibleForTesting
  static bool apply(List rows) {
    final out = <ComplaintCategory>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final key = row['key'];
      final en = row['en'];
      if (key is! String || key.isEmpty || en is! String) continue;
      final hex = (row['colour'] as String? ?? '').replaceFirst('#', '');
      final c = ComplaintCategory(
        key,
        en,
        row['fil'] as String? ?? en,
        hex.length == 6 ? int.tryParse('FF$hex', radix: 16) ?? ComplaintCategory.other.colour : ComplaintCategory.other.colour,
        row['icon'] as String? ?? 'other',
        [
          for (final o in (row['options'] as List? ?? const []))
            if (o is Map && o['en'] is String && o['active'] != false) ComplaintOption(o['en'] as String, o['fil'] as String?),
        ],
      );
      _seen[key] = c;
      if (row['active'] != false) out.add(c);
    }
    if (out.isEmpty) return false;
    _current = out;
    return true;
  }
}
