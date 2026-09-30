// SmartSumbong — Walking navigation for a dispatch (branch C).
//
// Turn-by-turn from OpenStreetMap's FOSSGIS foot router (the same free
// router Get directions already uses), followed on the phone: where the
// tanod is along the route, the next turn and how far to it, off-route
// and arrival. Nothing here is sent anywhere — the fixes that drive it
// stay on the phone, and navigation only runs while the tanod has it
// open, so it is not the live tracking the barangay turned off for
// battery (branch B).

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'tanod_strings.dart';

const _metres = Distance();

/// One manoeuvre: where it happens, what it is, and the road after it.
class NavStep {
  NavStep({
    required this.at,
    required this.type,
    required this.modifier,
    required this.road,
    required this.index,
  });

  final LatLng at;

  /// OSRM's maneuver type: depart, turn, new name, continue, end of
  /// road, fork, roundabout, rotary, arrive, …
  final String type;

  /// left, right, slight left, sharp right, straight, uturn, or ''.
  final String modifier;
  final String road;

  /// The route vertex nearest [at].
  final int index;

  bool get isArrive => type == 'arrive';

  IconData get icon {
    if (isArrive) return Icons.place;
    if (type == 'roundabout' || type == 'rotary') {
      return modifier.contains('left')
          ? Icons.roundabout_left
          : Icons.roundabout_right;
    }
    return switch (modifier) {
      'left' => Icons.turn_left,
      'right' => Icons.turn_right,
      'slight left' => Icons.turn_slight_left,
      'slight right' => Icons.turn_slight_right,
      'sharp left' => Icons.turn_sharp_left,
      'sharp right' => Icons.turn_sharp_right,
      'uturn' => Icons.u_turn_left,
      _ => Icons.straight,
    };
  }

  /// "Turn left onto 8th Street", in the app's language.
  String instruction(TanodStrings s) {
    if (isArrive) return s.navArrive;
    final base = type == 'depart'
        ? s.navStart
        : (type == 'roundabout' || type == 'rotary')
        ? s.navRoundabout
        : switch (modifier) {
            'left' => s.navLeft,
            'right' => s.navRight,
            'slight left' => s.navSlightLeft,
            'slight right' => s.navSlightRight,
            'sharp left' => s.navSharpLeft,
            'sharp right' => s.navSharpRight,
            'uturn' => s.navUturn,
            _ => s.navStraight,
          };
    return road.isEmpty ? base : s.navOnto(base, road);
  }
}

class NavRoute {
  NavRoute(this.line, this.steps, this.seconds) : _along = _cumulative(line);

  final List<LatLng> line;
  final List<NavStep> steps;
  final double seconds;

  /// Metres from the start to each vertex.
  final List<double> _along;

  double get metres => _along.isEmpty ? 0 : _along.last;

  /// Walking pace the router assumed, for the time left.
  double get pace => metres <= 0 ? 1.3 : metres / math.max(seconds, 1);

  static List<double> _cumulative(List<LatLng> line) {
    final out = <double>[];
    var sum = 0.0;
    for (var i = 0; i < line.length; i++) {
      if (i > 0) sum += _metres(line[i - 1], line[i]);
      out.add(sum);
    }
    return out;
  }

  /// Where [p] falls on the route: the segment, how far along the route
  /// that point is, and how far [p] is from the line.
  NavFix locate(LatLng p) {
    var bestD = double.infinity;
    var bestSeg = 0;
    var bestAlong = 0.0;
    var bestPoint = line.first;
    // Flat projection is fine at a barangay's scale.
    final k = math.cos(p.latitude * math.pi / 180);
    for (var i = 0; i < line.length - 1; i++) {
      final a = line[i], b = line[i + 1];
      final ax = a.longitude * k, ay = a.latitude;
      final bx = b.longitude * k, by = b.latitude;
      final px = p.longitude * k, py = p.latitude;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final q = LatLng(ay + dy * t, (ax + dx * t) / k);
      final d = _metres(p, q);
      if (d < bestD) {
        bestD = d;
        bestSeg = i;
        bestPoint = q;
        bestAlong = _along[i] + _metres(a, q);
      }
    }
    return NavFix(bestSeg, bestAlong, bestD, bestPoint);
  }

  /// The first step still ahead of [fix], or null past the last.
  NavStep? nextStep(NavFix fix) {
    for (final s in steps) {
      if (s.type == 'depart') continue;
      if (_along[s.index] > fix.along + 3) return s;
    }
    return null;
  }

  double metresTo(NavStep step, NavFix fix) =>
      math.max(0, _along[step.index] - fix.along);

  double metresLeft(NavFix fix) => math.max(0, metres - fix.along);

  /// The route still ahead: the snapped position, then the rest.
  List<LatLng> ahead(NavFix fix) => [
    fix.point,
    ...line.sublist(math.min(fix.segment + 1, line.length)),
  ];

  /// Compass bearing of the route at [fix], for a course-up camera.
  double bearingAt(NavFix fix) {
    final i = math.min(fix.segment, line.length - 2);
    if (i < 0) return 0;
    return _metres.bearing(line[i], line[i + 1]);
  }
}

class NavFix {
  NavFix(this.segment, this.along, this.offRoute, this.point);
  final int segment;
  final double along;

  /// Metres from the route line.
  final double offRoute;
  final LatLng point;
}

/// The walking route from [from] to [to] with its turns.
Future<NavRoute> fetchNavRoute(LatLng from, LatLng to) async {
  final uri = Uri.parse(
    'https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
    '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
    '?overview=full&geometries=geojson&steps=true',
  );
  final res = await http
      .get(
        uri,
        headers: {
          'User-Agent': 'SmartSumbong/1.0 (Barangay 183 tanod app; navigation)',
        },
      )
      .timeout(const Duration(seconds: 12));
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final routes = body['routes'] as List?;
  if (res.statusCode != 200 || routes == null || routes.isEmpty) {
    throw const FormatException('no route');
  }
  final r = routes.first as Map<String, dynamic>;
  final line = ((r['geometry'] as Map)['coordinates'] as List)
      .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList();
  if (line.length < 2) throw const FormatException('no route');

  int nearest(LatLng p) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < line.length; i++) {
      final d = _metres(p, line[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  final steps = <NavStep>[];
  for (final leg in (r['legs'] as List? ?? const [])) {
    for (final st in ((leg as Map)['steps'] as List? ?? const [])) {
      final m = (st as Map)['maneuver'] as Map;
      final loc = m['location'] as List;
      final at = LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble());
      steps.add(
        NavStep(
          at: at,
          type: m['type'] as String? ?? 'turn',
          modifier: m['modifier'] as String? ?? '',
          road: (st['name'] as String? ?? '').trim(),
          index: nearest(at),
        ),
      );
    }
  }
  return NavRoute(line, steps, (r['duration'] as num?)?.toDouble() ?? 0);
}

/// "80 m" / "1.2 km", rounded the way a walker reads them.
String navDistance(double m) {
  if (m >= 950) return '${(m / 1000).toStringAsFixed(1)} km';
  if (m >= 100) return '${(m / 50).round() * 50} m';
  return '${math.max(5, (m / 5).round() * 5)} m';
}
