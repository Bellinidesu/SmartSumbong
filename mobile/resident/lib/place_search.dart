// SmartSumbong — the address search and the words for a pin.
//
// Moved out of the report details screen (19 Nov 2026) when "Where is it?" became a screen of its own
// (screens/where_screen.dart): the places a resident can pick as they type an address, and "Near X", the few
// words that say where a pin is.
//
// SEARCH. First the barangay's own search (search_places, 0134: OpenStreetMap refreshed every six hours plus the
// barangay's own places; it forgives slips and shorthand and knows Tagalog words for kinds of place, like "botika"
// or "simbahan"), then Photon (komoot's open-source geocoder) for anything it does not have. Only places inside
// the barangay's outline are offered. A typed address only ever moves the pin; it is never sent to file_report()
// as text, and nothing downstream needs to know a pin came from a search box rather than a drag.
//
// NEAR X, in this order, stopping at the first that answers:
//   1. a landmark from assets/map/landmarks.geojson within [PlaceWords.landmarkMetres] (on the phone already:
//      no network);
//   2. a reverse lookup (Nominatim, through ReverseGeocode.lookup), at most one a second, only after the map has
//      stopped moving, a newer pin cancelling an older one.
// (The map's own street labels could be asked at the pin, but that cannot be checked off a phone, so it is not.)
// If none answers the screen says "Near your pin". Whatever happens, none of it can hold up the Confirm button.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_lookup.dart';
import 'preview/demo.dart' show kDemo;
import 'models/barangay_profile.dart';
import 'widgets/brgy_map.dart';

/// One place offered under the address box.
class PlaceHit {
  const PlaceHit(this.title, this.sub, this.at);
  final String title;
  final String sub;
  final LatLng at;
}

typedef Tr = String Function(String en, String fil);

/// Photon's box round the barangay.
const _photonBox = '120.9996,14.5019,121.0328,14.5310';

class PlaceSearch {
  PlaceSearch._();

  /// Tests answer the search themselves; null in the app.
  @visibleForTesting
  static Future<List<PlaceHit>> Function(String q)? override;

  /// Places matching [q]: [near] ranks the barangay's own search by distance, [rings] keeps only what is inside
  /// Barangay 183, [tr] words the kind of place in the app's language.
  static Future<List<PlaceHit>> lookup(String q, {required LatLng near, required List<List<LatLng>> rings, required Tr tr}) async {
    final fake = override;
    if (fake != null) return fake(q);
    final out = <PlaceHit>[];
    try {
      final rows = await Supabase.instance.client.rpc('search_places', params: {
        'p_q': q,
        'p_lat': near.latitude,
        'p_lng': near.longitude,
        'p_limit': 8,
      }).timeout(const Duration(seconds: 6)) as List;
      for (final r in rows) {
        final m = Map<String, dynamic>.from(r as Map);
        final at = LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
        if (!insideBrgy(rings, at)) continue;
        final kind = _kindName(m['grp'] as String?, tr);
        final n = (m['branches'] as num?)?.toInt() ?? 1;
        out.add(PlaceHit('${m['name']}', [
          ?kind,
          if (n > 1) tr('$n branches, nearest shown', '$n sangay, pinakamalapit ang ipinapakita'),
          BarangayProfile.name,
        ].join(' · '), at));
        if (out.length == 5) return out;
      }
    } catch (_) {
      // Offline or the search is down: Photon below may still answer.
    }
    try {
      for (final p in await _photon(q, rings)) {
        if (out.any((o) => o.title.toLowerCase() == p.title.toLowerCase())) continue;
        out.add(p);
        if (out.length == 5) break;
      }
    } catch (_) {
      if (out.isEmpty) rethrow;
    }
    return out;
  }

  /// The kind of place, in the app's language, for a search_places group.
  static String? _kindName(String? grp, Tr tr) => switch (grp) {
        'health' => tr('Health', 'Kalusugan'),
        'school' => tr('School', 'Paaralan'),
        'worship' => tr('Church', 'Simbahan'),
        'safety' => tr('Police and fire', 'Pulis at bumbero'),
        'hall' => tr('Barangay hall', 'Bulwagan ng barangay'),
        'government' => tr('Government', 'Gobyerno'),
        'transport' => tr('Transport', 'Sakayan'),
        'food' => tr('Food', 'Pagkain'),
        'shop' => tr('Shop', 'Tindahan'),
        'service' => tr('Bank and service', 'Bangko at serbisyo'),
        'lodging' => tr('Hotel', 'Tuluyan'),
        'park' => tr('Park', 'Parke'),
        'street' => tr('Street', 'Kalye'),
        _ => null,
      };

  /// Photon (komoot's open-source geocoder over OpenStreetMap, made for search-as-you-type), limited to the
  /// barangay's box.
  static Future<List<PlaceHit>> _photon(String q, List<List<LatLng>> rings) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': q,
      'limit': '8',
      'lang': 'en',
      'lat': '${brgyCentre.latitude}',
      'lon': '${brgyCentre.longitude}',
      'bbox': _photonBox,
    });
    final res = await http.get(uri, headers: {
      'User-Agent': 'SmartSumbong-Resident/1.0 (Barangay 183, Pasay City)',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('geocode ${res.statusCode}');
    final features = (jsonDecode(res.body) as Map)['features'] as List? ?? const [];
    final out = <PlaceHit>[];
    for (final f in features) {
      final c = (f['geometry']?['coordinates'] as List?)?.cast<num>();
      if (c == null || c.length < 2) continue;
      final at = LatLng(c[1].toDouble(), c[0].toDouble());
      if (!insideBrgy(rings, at)) continue;
      final pr = (f['properties'] as Map?) ?? const {};
      final name = (pr['name'] ?? '').toString();
      final street = [pr['housenumber'], pr['street']].where((e) => e != null && '$e'.isNotEmpty).join(' ');
      final title = name.isNotEmpty ? name : (street.isNotEmpty ? street : q);
      final sub = [if (name.isNotEmpty && street.isNotEmpty) street, '${BarangayProfile.name}, ${BarangayProfile.city}'].join(' · ');
      if (out.any((o) => o.title == title && o.sub == sub)) continue;
      out.add(PlaceHit(title, sub, at));
      if (out.length == 5) break;
    }
    return out;
  }
}

/// "Near X": the few words for a pin.
class PlaceWords {
  PlaceWords._();

  /// A landmark closer than this names the spot; further and it would only mislead.
  static const landmarkMetres = 60.0;

  static List<(String, LatLng)>? _landmarks;

  /// The landmarks bundled with the app (the same file the map draws), read once. Empty when it cannot be read.
  static Future<List<(String, LatLng)>> landmarks() async {
    final have = _landmarks;
    if (have != null) return have;
    final out = <(String, LatLng)>[];
    try {
      final data = jsonDecode(await rootBundle.loadString('assets/map/landmarks.geojson')) as Map;
      for (final f in (data['features'] as List)) {
        final name = ((f['properties'] as Map?)?['name'] ?? '').toString().trim();
        final c = ((f['geometry'] as Map?)?['coordinates'] as List?)?.cast<num>();
        if (name.isEmpty || c == null || c.length < 2) continue;
        out.add((name, LatLng(c[1].toDouble(), c[0].toDouble())));
      }
    } catch (_) {}
    return _landmarks = out;
  }

  /// The name of the nearest landmark within [landmarkMetres] of [at], or null.
  static Future<String?> landmarkAt(LatLng at) async {
    const d = Distance();
    String? best;
    var bestM = landmarkMetres;
    for (final (name, p) in await landmarks()) {
      final m = d.as(LengthUnit.Meter, at, p);
      if (m <= bestM) {
        bestM = m;
        best = name;
      }
    }
    return best;
  }

  // Nominatim's policy: about one request a second.
  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static const _gap = Duration(milliseconds: 1100);

  /// Tests answer the reverse lookup themselves; null in the app (ReverseGeocode.lookup, Nominatim).
  @visibleForTesting
  static Future<String?> Function(double lat, double lng)? reverseOverride;

  /// The street or area Nominatim names for [at]; waits its turn (one request a second), and gives up quietly
  /// when [stale] says a newer pin has replaced this one.
  static Future<String?> reverse(LatLng at, {required bool Function() stale}) async {
    final fake = reverseOverride;
    if (fake != null) return fake(at.latitude, at.longitude);
    if (kDemo) return null; // the Dart preview has no network to ask
    final wait = _lastRequest.add(_gap).difference(DateTime.now());
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (stale()) return null;
    _lastRequest = DateTime.now();
    return ReverseGeocode.lookup(at.latitude, at.longitude);
  }
}
