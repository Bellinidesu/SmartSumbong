// SmartSumbong — flood watch (branch D).
//
// The portal's live rain reading (admin/spatial.php fwRead), on the phone:
// Open-Meteo's last four quarter-hours of precipitation over Barangay 183,
// summed to mm in the past hour, and graded the way PAGASA grades rainfall
// warnings — Yellow 7.5, Orange 15, Red 30 mm/h. Read when Home opens and
// every 10 minutes while it stays open; no key, no account.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../i18n.dart';
import 'd_theme.dart';
import 'd_ui.dart';

class FloodReading {
  const FloodReading({required this.online, this.mm});

  final bool online;
  final double? mm;

  int get level {
    final v = mm ?? 0;
    return v >= 30 ? 3 : v >= 15 ? 2 : v >= 7.5 ? 1 : 0;
  }

  static Future<FloodReading> read() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=14.5269&longitude=121.0155'
              '&minutely_15=precipitation&past_minutely_15=4&forecast_minutely_15=0&timezone=Asia%2FManila'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const FloodReading(online: false);
      final q = ((jsonDecode(res.body) as Map)['minutely_15']['precipitation'] as List).whereType<num>().toList();
      if (q.isEmpty) return const FloodReading(online: false);
      return FloodReading(online: true, mm: q.fold<double>(0, (a, v) => a + v.toDouble()));
    } catch (_) {
      return const FloodReading(online: false);
    }
  }
}

/// The flood watch strip on Home: a coloured dot, the warning, the mm/h.
class DFloodCard extends StatelessWidget {
  const DFloodCard({super.key, required this.reading, this.onTap});

  final FloodReading? reading;
  final VoidCallback? onTap;

  static const _cols = [Color(0xFF22C55E), Color(0xFFEAB308), Color(0xFFF97316), Color(0xFFDC2626)];

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final r = reading;
    final fil = AppLocaleScope.of(context) == AppLocale.fil;
    final lvl = r?.level ?? 0;
    final col = r == null || !r.online ? d.muted : _cols[lvl];
    final title = r == null
        ? context.tr('Flood watch · checking…', 'Bantay-baha · tinitingnan…')
        : !r.online
            ? context.tr('Flood watch · offline', 'Bantay-baha · offline')
            : switch (lvl) {
                0 => context.tr('Flood watch · No rain warning', 'Bantay-baha · Walang babala'),
                1 => fil ? 'Bantay-baha · Dilaw na babala' : 'Flood watch · Yellow warning',
                2 => fil ? 'Bantay-baha · Kahel na babala' : 'Flood watch · Orange warning',
                _ => fil ? 'Bantay-baha · Pulang babala' : 'Flood watch · Red warning',
              };
    final sub = switch (lvl) {
      0 => context.tr('Live rain over Barangay 183, checked every 10 minutes', 'Live na ulan sa Barangay 183, tinitingnan bawat 10 minuto'),
      1 => context.tr('Flooding possible in high-hazard areas.', 'Posibleng bumaha sa mga lugar na mataas ang panganib.'),
      2 => context.tr('Flooding threatening in high and medium-hazard areas.', 'Banta ng baha sa mataas at katamtamang panganib.'),
      _ => context.tr('Serious flooding expected in every flood zone.', 'Inaasahan ang malubhang baha sa lahat ng bahaing lugar.'),
    };
    return DSheet(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: lvl > 0 ? col.withValues(alpha: .6) : null,
      child: Row(children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: col, boxShadow: [BoxShadow(color: col.withValues(alpha: .25), spreadRadius: 5)]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: DType.body(d.ink, size: 14.5, w: FontWeight.w800)),
            Text(sub, style: DType.body(d.muted, size: 12.5)),
          ]),
        ),
        if (r != null && r.online) ...[
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(r.mm!.toStringAsFixed(1), style: DType.mono(d.ink, size: 18)),
            Text('mm/h', style: DType.body(d.muted, size: 10)),
          ]),
        ],
      ]),
    );
  }
}


/// The Project NOAH 100-year flood level at a point — 0 outside the
/// zones, 1 low, 2 medium, 3 high — read from the same hazard file the
/// map draws (assets/map/hazards.geojson).
class FloodHazard {
  static List<(int, List<List<List<double>>>)>? _zones;

  static Future<List<(int, List<List<List<double>>>)>> _load() async {
    if (_zones != null) return _zones!;
    final data = jsonDecode(await rootBundle.loadString('assets/map/hazards.geojson')) as Map;
    final out = <(int, List<List<List<double>>>)>[];
    for (final f in (data['features'] as List)) {
      final props = f['properties'] as Map;
      if (props['hazard'] != 'flood') continue;
      final g = f['geometry'] as Map;
      final polys = g['type'] == 'Polygon' ? [g['coordinates'] as List] : (g['coordinates'] as List).cast<List>();
      for (final poly in polys) {
        out.add((
          (props['level'] as num).toInt(),
          [
            for (final ring in poly)
              [for (final c in (ring as List)) [(c[0] as num).toDouble(), (c[1] as num).toDouble()]],
          ],
        ));
      }
    }
    return _zones = out;
  }

  static bool _inRing(double x, double y, List<List<double>> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }

  static Future<int> levelAt(double lat, double lng) async {
    var best = 0;
    for (final (level, rings) in await _load()) {
      if (level <= best) continue;
      // inside the outer ring and not in a hole
      if (_inRing(lng, lat, rings.first) && !rings.skip(1).any((h) => _inRing(lng, lat, h))) best = level;
    }
    return best;
  }
}
