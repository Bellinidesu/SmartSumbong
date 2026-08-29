// SmartSumbong — best-effort street name for the reports list/detail
// footer meta line, 29 Aug 2026.
//
// THE GAP THIS FILLS. The reference mockup's report cards show a
// "📍 <place>" line next to the date ("📍 Covered Court", "📍 Mabini
// Street") — but that text came from a form field the mockup's resident
// typed by hand at submission ("Location" on screen-report, seeded with
// "Covered Court, Brgy. San Isidro"). 0001's `reports` table only stores
// `latitude`/`longitude`, no free-text address column, and reports_screen
// .dart's own ReportSummary doc comment (see the field above) already
// flagged this gap and left the line out entirely for that reason.
//
// Adding a stored address column is a real schema decision — a new
// migration, a form field, and an RLS question (can a resident's own row
// be updated after submission, or does the audit trail require it stay
// immutable?) — three weeks from defence, for a field the manuscript
// does not describe. Same reasoning complaint_category.dart's own header
// gives for not adding a subcategory column. So this stays client-side
// and best-effort instead: a reverse-geocode lookup against OpenStreetMap
// Nominatim (free, keyless, the same OSM stack ReportViewScreen's
// _MiniMap and the incident-map screen already render tiles from — no
// new provider), never written back to the database.
//
// ACCURACY. This is an approximation the resident never confirmed, not a
// stored fact — never conflate it with `latitude`/`longitude` themselves,
// which are exact. A street corner is the clearest failure mode:
// Nominatim resolves to whichever of the two intersecting roads its own
// nearest-feature search considers closer, and there is no reliable way
// to detect "this is a corner" and name both without a heavier Overpass
// query, so this takes the single nearest name Nominatim returns. On
// failure (offline, timeout, rate-limited, no usable address in the
// response) this returns null — callers must treat null as "omit the
// location line entirely," never fall back to showing the raw
// coordinates or an error string in its place.
//
// RATE LIMITS. Nominatim's usage policy caps the public server at
// roughly one request per second and requires a real identifying
// User-Agent (set below) — fine for a barangay-scale resident list (a
// handful of reports per screen open), but the first thing to revisit if
// this app ever needs a self-hosted Nominatim instance or a paid
// provider at higher traffic. The in-memory cache below is what keeps a
// single screen's re-renders and pull-to-refreshes from re-querying the
// same coordinates repeatedly.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ReverseGeocode {
  ReverseGeocode._();

  /// Keyed to 4 decimal places (~11m) so nearby reports share one lookup
  /// instead of firing one request each. In-memory only, cleared on cold
  /// start — nothing here is persisted server-side, see the file header.
  static final Map<String, String?> _cache = {};

  static const _userAgent =
      'SmartSumbong/1.0 (barangay complaint mapping app, resident client)';

  static String _key(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Null on any failure or when Nominatim has nothing usable. Never
  /// throws — every failure path is caught and folded into a null
  /// result, since a missing location line is always the safe fallback
  /// here, not a crash.
  static Future<String?> lookup(double lat, double lng) async {
    final key = _key(lat, lng);
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'zoom': '17',
        'addressdetails': '1',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        return _cache[key] = null;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final address = body['address'] as Map<String, dynamic>?;
      // Prefer an actual road/street name (what the mockup's own
      // examples show — "Mabini Street", "Covered Court"); fall back to
      // progressively broader area names rather than nothing, since a
      // barangay-level complaint map still benefits from "somewhere near
      // X" over no location at all.
      final name = _firstNonEmpty([
        address?['road'],
        address?['pedestrian'],
        address?['neighbourhood'],
        address?['suburb'],
      ]);
      return _cache[key] = name;
    } catch (_) {
      return _cache[key] = null;
    }
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
