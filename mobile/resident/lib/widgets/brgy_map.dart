// SmartSumbong — the barangay map, on MapLibre (branch B).
//
// Every map in the app goes through this widget: the Barangay 183 map,
// the pin picker on the report form, the small map on View Report, and
// (branch C, one app) the tanod dispatch map with its walking route. At
// night a tanod gets the ink map (style-dark-ink.json), a resident the
// navy one (style-dark.json), matching each role's own colours.
//
// WHY MAPLIBRE. The maps used to be flutter_map drawing raster tiles from
// tile.openstreetmap.org. That server is a donated service whose usage
// policy rules out production apps; it can throttle or block us without
// warning, and every map would go grey at once. These are vector tiles
// from OpenFreeMap (tiles.openfreemap.org), which exists to serve
// production apps for free, with no API key and no usage limit, drawn by
// MapLibre with our own styles: assets/map/style-light.json and
// style-dark.json, built from OpenFreeMap's Positron and recoloured to the
// app's palettes — so the map finally follows dark mode instead of
// staying a light rectangle at night. Map data © OpenStreetMap
// contributors; the attribution button on the map says so.
//
// The boundary fog, the report pins and the GPS accuracy circle are map
// layers (GeoJSON sources) rather than Flutter widgets over the map.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../theme.dart';

/// Barangay 183's residential centre — the value the admin portal's
/// Spatial Distribution uses. Not the OSM relation's centroid, which sits
/// on the NAIA apron.
const brgyCentre = ll.LatLng(14.526905, 121.015543);

/// Zooms in this file's API are the old raster maps' (256-pixel tiles), so
/// callers keep the numbers they had; MapLibre counts 512-pixel tiles, one
/// level further in for the same framing.
double _mlZoom(double z) => z - 1;

/// How far the Barangay map may pan from [brgyCentre].
const _spanLat = 0.0110;
const _spanLng = 0.0115;

/// Whether [p] is inside the area the Barangay map can pan to.
bool withinBrgyBounds(ll.LatLng p) =>
    (p.latitude - brgyCentre.latitude).abs() <= _spanLat &&
    (p.longitude - brgyCentre.longitude).abs() <= _spanLng;

/// One report on the map. [alert] draws it red; [muted] grey, for an
/// incident the barangay published that is not the viewer's own (0073).
class BrgyMapPin {
  const BrgyMapPin({
    required this.id,
    required this.point,
    this.alert = false,
    this.muted = false,
    this.glyph,
    this.statusColour,
    this.catColour,
    this.pulse = false,
  });

  final String id;
  final ll.LatLng point;
  final bool alert;
  final bool muted;

  /// A status badge (Ace's pick, 5 Oct): a round badge in [statusColour]
  /// with the category's [glyph] inside and a dot in [catColour] on its
  /// shoulder; [pulse] adds a soft halo (a report in progress). Without a
  /// [glyph] the pin is the design's tilted one.
  final IconData? glyph;
  final Color? statusColour;
  final Color? catColour;
  final bool pulse;

  bool get isBadge => glyph != null && statusColour != null;

  @override
  bool operator ==(Object other) =>
      other is BrgyMapPin &&
      other.id == id &&
      other.point == point &&
      other.alert == alert &&
      other.muted == muted &&
      other.glyph == glyph &&
      other.statusColour == statusColour &&
      other.catColour == catColour &&
      other.pulse == pulse;

  @override
  int get hashCode => Object.hash(id, point, alert, muted, glyph, statusColour, catColour, pulse);
}

/// Moves a [BrgyMap]'s camera. A move asked for before the map is ready
/// is kept and made once it is.
class BrgyMapController {
  ml.MapLibreMapController? _map;
  ml.CameraUpdate? _pending;

  // Set while a move made here is settling, so [BrgyMap.onMoved] reports
  // only the moves a person made.
  bool _programmatic = false;

  void zoomBy(double d) => _apply(ml.CameraUpdate.zoomBy(d));

  void move(ll.LatLng p, double zoom) =>
      _apply(ml.CameraUpdate.newLatLngZoom(_ml(p), _mlZoom(zoom)));

  /// Navigation (branch C): the camera on [p], turned to [bearing]
  /// degrees and tilted, so the way ahead is up the screen.
  void follow(ll.LatLng p, {double bearing = 0, double zoom = 18, double tilt = 45}) =>
      _apply(ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
        target: _ml(p),
        zoom: _mlZoom(zoom),
        bearing: bearing,
        tilt: tilt,
      )));

  /// Frames [points] with [padding] around them; one point is shown at
  /// zoom 17.
  void fit(List<ll.LatLng> points, {double padding = 48}) {
    if (points.isEmpty) return;
    if (points.length == 1) return move(points.first, 17);
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    _apply(ml.CameraUpdate.newLatLngBounds(
      ml.LatLngBounds(
        southwest: ml.LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
        northeast: ml.LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
      ),
      left: padding,
      top: padding,
      right: padding,
      bottom: padding,
    ));
  }

  void _apply(ml.CameraUpdate u) {
    final map = _map;
    if (map == null) {
      _pending = u;
      return;
    }
    _programmatic = true;
    unawaited(map.animateCamera(u, duration: const Duration(milliseconds: 350)));
  }

  void _attach(ml.MapLibreMapController map) {
    _map = map;
    final u = _pending;
    _pending = null;
    if (u != null) {
      _programmatic = true;
      unawaited(map.moveCamera(u));
    }
  }
}

class BrgyMap extends StatefulWidget {
  const BrgyMap({
    super.key,
    this.controller,
    this.initialCenter = brgyCentre,
    this.initialZoom = 17,
    this.boundary = false,
    this.hazards = false,
    this.restrictToBarangay = false,
    this.interactive = true,
    this.pins = const [],
    this.onPinTap,
    this.onMoved,
    this.accuracyCentre,
    this.accuracyMetres,
    this.route = const [],
    this.me,
    this.attributionBottom = 8,
    this.cornerRadius = 0,
    this.cornerColour,
  });

  final BrgyMapController? controller;
  final ll.LatLng initialCenter;
  final double initialZoom;

  /// Dim everything outside Barangay 183 and outline it.
  final bool boundary;

  /// Project NOAH's flood and storm-surge hazard zones (branch B).
  final bool hazards;

  /// Keep the camera over the residential grid, zoom 15 and closer.
  final bool restrictToBarangay;

  /// False for a picture of a place: no pan, zoom or taps.
  final bool interactive;

  final List<BrgyMapPin> pins;
  final ValueChanged<String>? onPinTap;

  /// Where the camera settled after a person moved the map.
  final ValueChanged<ll.LatLng>? onMoved;

  /// A GPS fix's accuracy, drawn as a circle on the ground.
  final ll.LatLng? accuracyCentre;
  final double? accuracyMetres;

  /// A route to draw (branch B: the walking route to a dispatch).
  final List<ll.LatLng> route;

  /// Where the person is, as a blue dot (branch C: navigation).
  final ll.LatLng? me;

  /// Keeps the attribution button clear of anything drawn over the
  /// map's bottom edge.
  final double attributionBottom;

  /// The native map view does not always honour a Flutter clip, so
  /// rounded corners are painted over in [cornerColour] (what is behind
  /// the map) instead.
  final double cornerRadius;
  final Color? cornerColour;

  @override
  State<BrgyMap> createState() => _BrgyMapState();
}

class _BrgyMapState extends State<BrgyMap> {
  static final _styles = <bool, Future<String>>{};
  static Future<List<List<ll.LatLng>>>? _rings;

  ml.MapLibreMapController? _map;
  final _images = <String>{};
  bool _styleReady = false;
  String? _style;
  bool? _styleDark;

  Future<String> _loadStyle(bool dark) => _styles[dark] ??=
      rootBundle.loadString('assets/map/style-${!dark ? 'light' : AppRoleController.instance.value == AppRole.tanod ? 'dark-ink' : 'dark'}.json');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = context.isDark;
    if (dark == _styleDark) return;
    _styleDark = dark;
    _styleReady = false;
    _loadStyle(dark).then((s) {
      if (mounted) setState(() => _style = s);
    });
  }

  @override
  void didUpdateWidget(BrgyMap old) {
    super.didUpdateWidget(old);
    if (!_styleReady) return;
    if (!listEquals(old.pins, widget.pins)) unawaited(_setPins());
    if (old.hazards != widget.hazards) {
      unawaited(_map?.setLayerVisibility('hazard-fill', widget.hazards));
    }
    if (!listEquals(old.route, widget.route)) unawaited(_setRoute());
    if (old.me != widget.me) unawaited(_setMe());
    if (old.accuracyCentre != widget.accuracyCentre ||
        old.accuracyMetres != widget.accuracyMetres) {
      unawaited(_setAccuracy());
    }
  }

  void _created(ml.MapLibreMapController map) {
    _map = map;
    widget.controller?._attach(map);
    map.onFeatureTapped.add((point, latLng, id, layerId, annotation) {
      if (layerId == 'pins' || layerId == 'badges') widget.onPinTap?.call(id);
    });
  }

  void _idle() {
    final c = widget.controller;
    if (c != null && c._programmatic) {
      c._programmatic = false;
      return;
    }
    final target = _map?.cameraPosition?.target;
    if (target != null) {
      widget.onMoved?.call(ll.LatLng(target.latitude, target.longitude));
    }
  }

  // ---------- layers -------------------------------------------

  Future<void> _styleLoaded() async {
    final map = _map;
    if (map == null) return;
    _styleReady = true;
    final dark = context.isDark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    try {
      if (widget.boundary) await _addBoundary(map, dark);
      await _addHazards(map);
      await _addLandmarks(map, dark);

      await map.addGeoJsonSource('accuracy', _empty);
      await map.addFillLayer(
        'accuracy',
        'accuracy-fill',
        const ml.FillLayerProperties(
          fillColor: '#00308F',
          fillOpacity: 0.12,
        ),
      );
      await map.addLineLayer(
        'accuracy',
        'accuracy-line',
        const ml.LineLayerProperties(
          lineColor: '#00308F',
          lineOpacity: 0.4,
          lineWidth: 1,
        ),
      );
      await _setAccuracy();

      // The walking route to a dispatch, under the pins.
      await map.addGeoJsonSource('route', _empty);
      await map.addLineLayer(
        'route',
        'route-casing',
        const ml.LineLayerProperties(
            lineColor: '#FFFFFF', lineWidth: 7, lineJoin: 'round', lineCap: 'round'),
        enableInteraction: false,
      );
      await map.addLineLayer(
        'route',
        'route-line',
        const ml.LineLayerProperties(
            lineColor: '#FF9800', lineWidth: 4, lineJoin: 'round', lineCap: 'round'),
        enableInteraction: false,
      );
      await _setRoute();

      // Navy on #FBFBFB on the light map; the pale ink on the dark field
      // on the navy night map, where navy would disappear.
      final c = context.colors;
      await map.addImage('pin-navy', await _pinPng(c.navy, c.field, dpr));
      await map.addImage(
          'pin-red', await _pinPng(const Color(0xFFFF4949), c.field, dpr));
      await map.addImage(
          'pin-grey', await _pinPng(const Color(0xFF8A93A6), c.field, dpr));
      await map.addGeoJsonSource('pins', _empty, promoteId: 'id');
      await map.addSymbolLayer(
        'pins',
        'badges',
        const ml.SymbolLayerProperties(
          iconImage: ['get', 'badge'],
          iconSize: 1,
          iconAnchor: 'bottom',
          // the badge is drawn with room for its halo under it
          iconOffset: [0, 8],
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        filter: ['has', 'badge'],
        enableInteraction: widget.onPinTap != null,
      );
      await map.addSymbolLayer(
        'pins',
        'pins',
        filter: ['!', ['has', 'badge']],
        ml.SymbolLayerProperties(
          iconImage: [
            'case',
            ['get', 'muted'],
            'pin-grey',
            ['get', 'alert'],
            'pin-red',
            'pin-navy',
          ],
          // Drawn at the phone's pixel ratio; MapLibre shows image
          // pixels as physical pixels, so full size is the 40x40 design.
          iconSize: 1,
          iconAnchor: 'bottom',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: widget.onPinTap != null,
      );
      await _setPins();

      // You-are-here, over everything.
      await map.addGeoJsonSource('me', _empty);
      await map.addCircleLayer(
        'me',
        'me-dot',
        const ml.CircleLayerProperties(
          circleRadius: 8,
          circleColor: '#1A73E8',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
        enableInteraction: false,
      );
      await _setMe();
    } catch (e) {
      debugPrint('BrgyMap layers: $e');
    }
  }

  static const _empty = {'type': 'FeatureCollection', 'features': []};

  /// Project NOAH's 100-year flood map and worst-case storm surge,
  /// clipped to Barangay 183 (UP NOAH Center, ODbL) — the same file and
  /// colours as the admin portal (assets/map/hazards.geojson). Hidden
  /// unless [BrgyMap.hazards]; under the landmarks and pins.
  Future<void> _addHazards(ml.MapLibreMapController map) async {
    try {
      final data =
          jsonDecode(await rootBundle.loadString('assets/map/hazards.geojson'));
      await map.addGeoJsonSource('hazards', data as Map<String, dynamic>);
      await map.addFillLayer(
        'hazards',
        'hazard-fill',
        ml.FillLayerProperties(
          fillColor: const [
            'match',
            ['concat', ['get', 'hazard'], '-', ['to-string', ['get', 'level']]],
            'flood-1', '#FACC15', 'flood-2', '#F97316', 'flood-3', '#DC2626',
            'surge-1', '#C4B5FD', 'surge-2', '#8B5CF6', 'surge-3', '#5B21B6',
            '#94A3B8',
          ],
          fillOpacity: 0.38,
          fillAntialias: false,
          visibility: widget.hazards ? 'visible' : 'none',
        ),
        enableInteraction: false,
      );
    } catch (e) {
      debugPrint('BrgyMap hazards: $e');
    }
  }

  /// The barangay hall, schools, chapels, police posts, clinics, parks,
  /// malls — reference points to steer by (branch B). The same curated
  /// OpenStreetMap file and colours as the admin portal's maps
  /// (assets/map/landmarks.geojson). Dots always; names from zoom 15.5.
  /// Under the pins, and never tappable, so a tap always means a pin.
  Future<void> _addLandmarks(ml.MapLibreMapController map, bool dark) async {
    try {
      final data = jsonDecode(
          await rootBundle.loadString('assets/map/landmarks.geojson'));
      await map.addGeoJsonSource('landmarks', data as Map<String, dynamic>);
      // Icon badges (Ace's pick, 5 Oct), in the portal's group colours.
      for (final g in _landmarkLook.entries) {
        await map.addImage('lm-${g.key}', await _landmarkPng(g.value.$1, g.value.$2, MediaQuery.devicePixelRatioOf(context)));
      }
      await map.addImage('lm-other', await _landmarkPng(Icons.place_rounded, const Color(0xFF64748B), MediaQuery.devicePixelRatioOf(context)));
      await map.addSymbolLayer(
        'landmarks',
        'landmarks-badge',
        ml.SymbolLayerProperties(
          iconImage: [
            'match', ['get', 'group'],
            for (final k in _landmarkLook.keys) ...[k, 'lm-$k'],
            'lm-other',
          ],
          iconSize: const ['interpolate', ['linear'], ['zoom'], 14, 0.62, 18, 1.0],
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: false,
      );
      await map.addSymbolLayer(
        'landmarks',
        'landmarks-label',
        ml.SymbolLayerProperties(
          textField: ['get', 'name'],
          textFont: const ['Noto Sans Bold'],
          textSize: const ['interpolate', ['linear'], ['zoom'], 15.5, 10.5, 18, 13],
          textOffset: const [0, 1.55],
          textAnchor: 'top',
          textMaxWidth: 9,
          textOptional: true,
          textColor: dark ? '#EAF0FF' : '#1F2937',
          textHaloColor: dark ? 'rgba(13,27,51,0.9)' : 'rgba(255,255,255,0.95)',
          textHaloWidth: 1.4,
        ),
        minzoom: 15.5,
        enableInteraction: false,
      );
    } catch (e) {
      debugPrint('BrgyMap landmarks: $e');
    }
  }

  Future<void> _addBoundary(ml.MapLibreMapController map, bool dark) async {
    final rings = await (_rings ??= _loadRings());
    if (rings.isEmpty) return;
    List<List<double>> coords(List<ll.LatLng> r) => [
          for (final p in r) [p.longitude, p.latitude],
          if (r.first != r.last) [r.first.longitude, r.first.latitude],
        ];
    // The world with the barangay punched out: everything outside 183
    // is dimmed rather than hidden, so the bordering streets still help
    // a resident orient themselves.
    await map.addGeoJsonSource('brgy-fog', {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [-179.9, -85], [179.9, -85], [179.9, 85], [-179.9, 85],
                [-179.9, -85],
              ],
              for (final r in rings) coords(r),
            ],
          },
        },
      ],
    });
    await map.addFillLayer(
      'brgy-fog',
      'brgy-fog',
      ml.FillLayerProperties(
        fillColor: dark ? '#000000' : '#0D1117',
        fillOpacity: dark ? 0.5 : 0.55,
      ),
    );
    await map.addGeoJsonSource('brgy-line', {
      'type': 'FeatureCollection',
      'features': [
        for (final r in rings)
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {'type': 'LineString', 'coordinates': coords(r)},
          },
      ],
    });
    await map.addLineLayer(
      'brgy-line',
      'brgy-line',
      ml.LineLayerProperties(
        lineColor: dark ? '#EAF0FF' : '#14181D',
        lineOpacity: dark ? 0.8 : 0.9,
        lineWidth: 2,
      ),
    );
  }

  Future<void> _setPins() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final p in widget.pins) {
      if (!p.isBadge) continue;
      final key = _badgeKey(p);
      if (_images.add(key)) {
        await map.addImage(key, await _badgePng(p, dpr));
      }
    }
    await map.setGeoJsonSource('pins', {
      'type': 'FeatureCollection',
      'features': [
        for (final p in widget.pins)
          {
            'type': 'Feature',
            'id': p.id,
            'properties': {
              'id': p.id,
              'alert': p.alert,
              'muted': p.muted,
              if (p.isBadge) 'badge': _badgeKey(p),
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [p.point.longitude, p.point.latitude],
            },
          },
      ],
    });
  }

  Future<void> _setRoute() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final r = widget.route;
    await map.setGeoJsonSource(
      'route',
      r.length < 2
          ? _empty
          : {
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [for (final p in r) [p.longitude, p.latitude]],
                  },
                },
              ],
            },
    );
  }

  Future<void> _setMe() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final p = widget.me;
    await map.setGeoJsonSource(
      'me',
      p == null
          ? _empty
          : {
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [p.longitude, p.latitude],
                  },
                },
              ],
            },
    );
  }

  Future<void> _setAccuracy() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final c = widget.accuracyCentre;
    final m = widget.accuracyMetres;
    await map.setGeoJsonSource(
      'accuracy',
      c == null || m == null
          ? _empty
          : {
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'properties': <String, dynamic>{},
                  'geometry': {
                    'type': 'Polygon',
                    'coordinates': [_circle(c, m)],
                  },
                },
              ],
            },
    );
  }

  /// A ring of 64 points [metres] around [c] — a circle on the ground,
  /// whatever the zoom.
  static List<List<double>> _circle(ll.LatLng c, double metres) {
    const earth = 6378137.0;
    final dLat = metres / earth * 180 / math.pi;
    final dLng = dLat / math.cos(c.latitude * math.pi / 180);
    return [
      for (var i = 0; i <= 64; i++)
        [
          c.longitude + dLng * math.cos(2 * math.pi * i / 64),
          c.latitude + dLat * math.sin(2 * math.pi * i / 64),
        ],
    ];
  }

  /// The portal's landmark colours (admin/assets/js/map-theme.js) and a
  /// glyph for each group.
  static const _landmarkLook = <String, (IconData, Color)>{
    'hall': (Icons.account_balance_rounded, Color(0xFFFF9800)),
    'school': (Icons.school_rounded, Color(0xFF7C3AED)),
    'worship': (Icons.church_rounded, Color(0xFF0891B2)),
    'safety': (Icons.local_police_rounded, Color(0xFFDC2626)),
    'health': (Icons.local_hospital_rounded, Color(0xFF16A34A)),
    'park': (Icons.park_rounded, Color(0xFF65A30D)),
    'shop': (Icons.shopping_basket_rounded, Color(0xFFDB2777)),
    'transport': (Icons.directions_bus_rounded, Color(0xFF475569)),
    'military': (Icons.shield_rounded, Color(0xFF57534E)),
    'government': (Icons.gavel_rounded, Color(0xFF1D4ED8)),
  };

  static void _glyph(Canvas canvas, IconData icon, Offset c, double size, Color colour) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: colour),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  static Future<Uint8List> _toPng(ui.PictureRecorder rec, Size size, double dpr) async {
    final img = await rec.endRecording().toImage((size.width * dpr).ceil(), (size.height * dpr).ceil());
    return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  /// A landmark: a 24 px circle in the group's colour, a white edge, the
  /// glyph in white.
  static Future<Uint8List> _landmarkPng(IconData icon, Color colour, double dpr) async {
    const size = Size(28, 28);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    const c = Offset(14, 14);
    canvas.drawCircle(c, 12.5, Paint()..color = const Color(0x33000000));
    canvas.drawCircle(c, 12, Paint()..color = Colors.white);
    canvas.drawCircle(c, 10, Paint()..color = colour);
    _glyph(canvas, icon, c, 13, Colors.white);
    return _toPng(rec, size, dpr);
  }

  static String _badgeKey(BrgyMapPin p) =>
      'b${p.statusColour!.toARGB32()}-${p.catColour?.toARGB32()}-${p.glyph!.codePoint}-${p.muted ? 1 : 0}-${p.pulse ? 1 : 0}';

  /// A report's status badge: round, the status colour, the category glyph
  /// inside, a dot in the category colour on its shoulder, a soft halo
  /// when it is in progress; a barangay-published one is faded and
  /// hollow. Bottom of the badge sits 8 px above the image's foot.
  static Future<Uint8List> _badgePng(BrgyMapPin p, double dpr) async {
    const size = Size(60, 60);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    const c = Offset(30, 34);
    final status = p.statusColour!;
    if (p.muted) {
      canvas.saveLayer(Offset.zero & size, Paint()..color = const Color(0xB3FFFFFF));
      canvas.drawCircle(c, 16.5, Paint()..color = Colors.white);
      canvas.drawCircle(c, 16.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = status);
      _glyph(canvas, p.glyph!, c, 17, p.catColour ?? status);
      canvas.restore();
      return _toPng(rec, size, dpr);
    }
    if (p.pulse) canvas.drawCircle(c, 24, Paint()..color = status.withValues(alpha: .24));
    canvas.drawCircle(c + const Offset(0, 1.5), 16.5, Paint()..color = const Color(0x33000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(c, 16.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, 13.5, Paint()..color = status);
    _glyph(canvas, p.glyph!, c, 17, Colors.white);
    final dot = c + const Offset(11, 11);
    canvas.drawCircle(dot, 6.5, Paint()..color = Colors.white);
    canvas.drawCircle(dot, 4.5, Paint()..color = p.catColour ?? status);
    return _toPng(rec, size, dpr);
  }

  /// The design's tilted pin, drawn once per colour as a map image.
  static Future<Uint8List> _pinPng(Color colour, Color fill, double dpr) async {
    const size = Size(40, 40);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    FigmaPinPainter(
      radius: 9.9,
      ring: 2.8,
      stroke: 2.2,
      colour: colour,
      fill: fill,
    ).paint(canvas, size);
    final img = await rec
        .endRecording()
        .toImage((size.width * dpr).ceil(), (size.height * dpr).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  /// OSM returns the relation's ways unordered and unclosed, so they are
  /// joined end-to-end into rings — the same algorithm as the admin
  /// portal's Spatial Distribution, reading the same file. Bundled, so a
  /// resident on the edge of signal still sees the boundary.
  static Future<List<List<ll.LatLng>>> _loadRings() async {
    try {
      final raw = await rootBundle.loadString('assets/geo/brgy183.json');
      final elements = (jsonDecode(raw) as Map)['elements'] as List;
      final rel = elements.firstWhere((e) => e['type'] == 'relation');
      final pool = <List<ll.LatLng>>[];
      for (final m in (rel['members'] as List)) {
        if (m['type'] != 'way' || m['geometry'] == null) continue;
        pool.add([
          for (final p in (m['geometry'] as List))
            ll.LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
        ]);
      }
      bool near(ll.LatLng a, ll.LatLng b) =>
          (a.latitude - b.latitude).abs() < 1e-7 &&
          (a.longitude - b.longitude).abs() < 1e-7;
      final rings = <List<ll.LatLng>>[];
      while (pool.isNotEmpty) {
        var ring = pool.removeAt(0);
        var joined = true;
        while (joined) {
          joined = false;
          for (var i = 0; i < pool.length; i++) {
            final w = pool[i];
            if (near(ring.last, w.first)) {
              ring = [...ring, ...w.skip(1)];
            } else if (near(ring.last, w.last)) {
              ring = [...ring, ...w.reversed.skip(1)];
            } else {
              continue;
            }
            pool.removeAt(i);
            joined = true;
            break;
          }
        }
        if (ring.length > 3) rings.add(ring);
      }
      return rings;
    } catch (_) {
      // The map is still useful without the outline.
      return const [];
    }
  }

  // ---------- widget -------------------------------------------

  @override
  Widget build(BuildContext context) {
    final map = _map2(context);
    final corner = widget.cornerColour;
    if (widget.cornerRadius <= 0 || corner == null) return map;
    return Stack(
      fit: StackFit.expand,
      children: [
        map,
        IgnorePointer(
          child: CustomPaint(
            painter: _CornerMask(radius: widget.cornerRadius, colour: corner),
          ),
        ),
      ],
    );
  }

  Widget _map2(BuildContext context) {
    final style = _style;
    final bg = context.colors.bg;
    if (style == null) return ColoredBox(color: bg);
    final i = widget.interactive;
    return ml.MapLibreMap(
      // A new style (dark mode switched) is a new map, so the layers are
      // added again on top of it.
      key: ValueKey(_styleDark),
      styleString: style,
      initialCameraPosition: ml.CameraPosition(
        target: _ml(widget.initialCenter),
        zoom: _mlZoom(widget.initialZoom),
      ),
      onMapCreated: _created,
      onStyleLoadedCallback: _styleLoaded,
      onCameraIdle: _idle,
      trackCameraPosition: true,
      cameraTargetBounds: widget.restrictToBarangay
          ? ml.CameraTargetBounds(ml.LatLngBounds(
              southwest: ml.LatLng(brgyCentre.latitude - _spanLat,
                  brgyCentre.longitude - _spanLng),
              northeast: ml.LatLng(brgyCentre.latitude + _spanLat,
                  brgyCentre.longitude + _spanLng),
            ))
          : ml.CameraTargetBounds.unbounded,
      minMaxZoomPreference: widget.restrictToBarangay
          ? ml.MinMaxZoomPreference(_mlZoom(15), _mlZoom(20))
          : ml.MinMaxZoomPreference(_mlZoom(4), _mlZoom(20)),
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: i,
      zoomGesturesEnabled: i,
      doubleClickZoomEnabled: i,
      dragEnabled: false,
      compassEnabled: false,
      logoEnabled: false,
      foregroundLoadColor: bg,
      attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
      attributionButtonMargins: math.Point(8, widget.attributionBottom),
      annotationOrder: const [],
      gestureRecognizers: i
          ? {
              Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new),
            }
          : null,
    );
  }
}

ml.LatLng _ml(ll.LatLng p) => ml.LatLng(p.latitude, p.longitude);

/// Paints [colour] outside a rounded rectangle the size of the box.
class _CornerMask extends CustomPainter {
  const _CornerMask({required this.radius, required this.colour});

  final double radius;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    canvas.drawPath(outside, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_CornerMask old) =>
      old.radius != radius || old.colour != colour;
}

/// The design's map pin: a teardrop outline tilted ~17° so its tip points
/// down and to the right, with a ring at its centre. [tip] is where the
/// point lands in the paint box; by default the bottom centre.
class FigmaPinPainter extends CustomPainter {
  const FigmaPinPainter({
    required this.radius,
    required this.ring,
    required this.stroke,
    required this.colour,
    required this.fill,
    this.tip,
  });

  final double radius;
  final double ring;
  final double stroke;
  final Color colour;
  final Color fill;
  final Offset? tip;

  static const _tilt = 16.9 * math.pi / 180;
  static const _reach = 1.27;

  @override
  void paint(Canvas canvas, Size size) {
    final end = tip ?? Offset(size.width / 2, size.height - stroke);
    final dir = Offset(math.sin(_tilt), math.cos(_tilt));
    final centre = end - dir * (radius * _reach);

    // Tangents from the tip meet the circle this far either side of it.
    final spread = math.acos(1 / _reach);
    final towardsTip = math.atan2(dir.dy, dir.dx);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(centre.dx + radius * math.cos(towardsTip + spread),
          centre.dy + radius * math.sin(towardsTip + spread))
      ..arcTo(Rect.fromCircle(center: centre, radius: radius),
          towardsTip + spread, 2 * math.pi - 2 * spread, false)
      ..close();

    final line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(path, line)
      ..drawCircle(centre, ring, line);
  }

  @override
  bool shouldRepaint(FigmaPinPainter old) =>
      old.colour != colour || old.fill != fill || old.tip != tip;
}
