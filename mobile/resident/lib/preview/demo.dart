// SmartSumbong — the Dart preview (branch D).
//
// The app itself, run with dummy data: no Supabase, no Firebase, no phone
// sensors. main_preview.dart boots the real screens against an in-memory
// backend (fake_backend.dart) so what you see is the Flutter UI, not a
// second copy of it in HTML. Everything here is inert in the real app.

import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../tanod/navigation.dart';

/// True only in the preview build (main_preview.dart sets it).
bool kDemo = false;

/// A position of the demo tanod near [target]: about 330 m south-west.
Position demoPosition(LatLng target) => _pos(target.latitude - 0.0021, target.longitude - 0.0023);

Position _pos(double lat, double lng, {double heading = 0, double speed = 0}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 6,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

/// A walk along [route], one fix a second at a brisk pace, ending on the
/// destination — what the phone's GPS stream would give a tanod on foot.
Stream<Position> demoWalk(NavRoute route) async* {
  const dist = Distance();
  final line = route.line;
  if (line.length < 2) return;
  var seg = 0;
  var at = line.first;
  yield _pos(at.latitude, at.longitude);
  const step = 9.0; // metres a second, sped up so the demo does not take minutes
  while (seg < line.length - 1) {
    await Future<void>.delayed(const Duration(seconds: 1));
    var left = step;
    while (seg < line.length - 1 && left > 0) {
      final next = line[seg + 1];
      final d = dist(at, next);
      if (d <= left) {
        left -= d;
        at = next;
        seg++;
      } else {
        final t = left / d;
        at = LatLng(at.latitude + (next.latitude - at.latitude) * t, at.longitude + (next.longitude - at.longitude) * t);
        left = 0;
      }
    }
    final head = seg < line.length - 1 ? dist.bearing(at, line[seg + 1]) : 0.0;
    yield _pos(at.latitude, at.longitude, heading: head < 0 ? head + 360 : head, speed: step);
  }
}
