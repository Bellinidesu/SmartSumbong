// SmartSumbong — the barangay map, rebuilt in the admin portal's style.
//
// 19 Nov 2026 (Ace: "scratch out the mobile version of the map and
// replace it with the portal one"). Every map in the app is this one
// widget, and it now looks and handles like the portal's Spatial
// Distribution (admin/spatial.php, assets/js/spatial.js, map-theme.js,
// sd-light.css, sd-dark.css), drawn natively with MapLibre rather than in a
// web view:
//
//  * the portal's map styles (assets/map/style-{light,dark}.json, copied
//    from admin/assets/map), for residents and tanods alike;
//  * the portal's pins: a solid disc in the complaint type's colour, a
//    white edge, the type's own symbol in white (map_glyphs.dart), lifted
//    by two shadows; sized with the zoom exactly as the portal sizes them;
//  * the soft fog of war outside Barangay 183 (no hard outline since
//    10 Oct) and the large faint place names under everything;
//  * the portal's Material controls: the dock of square buttons on the
//    right, the zoom pair under it, the Layers tile at the bottom left
//    that opens its row of layers, the legend card, a scale bar, the
//    compact attribution;
//  * the same framing: the residential grid, zoom 15 to 18 (MapLibre's
//    scale) where the map is pinned to the barangay.
//
// ONE WIDGET, SEVERAL USES. What a map shows is the screen's data (pins,
// route, position); how it looks and handles is its [BrgyMapUse]:
//
//   BrgyMapUse.browse    the resident's Map tab
//   BrgyMapUse.report    the picture of a place on a report page
//   BrgyMapUse.pick      the pin picker on the report form
//   BrgyMapUse.job       a tanod's dispatch (the job and the tanod)
//   BrgyMapUse.navigate  turn-by-turn, the camera following the tanod
//
// LEFT OUT ON PURPOSE. The portal's heat map, hotspots, density grid and
// list of every complaint are an administrator's view behind a login; a
// resident's map shows only what reports_resident_read and
// public_incidents already return (their own reports, and the incidents
// the barangay published: category and status). Project NOAH's flood
// zones are for the admins too (Ace, 19 Nov), so the app has none.
//
// WHY MAPLIBRE (branch B). Vector tiles from OpenFreeMap
// (tiles.openfreemap.org): free for production apps, no key, no limit.
// Map data © OpenStreetMap contributors; the attribution button says so.

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

import '../d/d_ui.dart' show DTr;
import '../theme.dart';
import 'map_glyphs.dart';

/// Barangay 183's residential centre — the value the admin portal's
/// Spatial Distribution uses. Not the OSM relation's centroid, which sits
/// on the NAIA apron.
const brgyCentre = ll.LatLng(14.526905, 121.015543);

/// Zooms in this file's API are the old raster maps' (256-pixel tiles), so
/// callers keep the numbers they had; MapLibre counts 512-pixel tiles, one
/// level further in for the same framing.
double _mlZoom(double z) => z - 1;

/// How far the Barangay map may pan from [brgyCentre] (the portal's SPAN).
const _spanLat = 0.0110;
const _spanLng = 0.0115;

/// The portal's slack past that box, so a pin on the edge can be reached.
const _pad = 0.12;

/// Whether [p] is inside the area the Barangay map frames.
bool withinBrgyBounds(ll.LatLng p) =>
    (p.latitude - brgyCentre.latitude).abs() <= _spanLat &&
    (p.longitude - brgyCentre.longitude).abs() <= _spanLng;

/// What a map is for. The screen gives the data; this decides the look,
/// the framing and the controls.
enum BrgyMapMode { browse, report, pick, job, navigate }

@immutable
class BrgyMapUse {
  const BrgyMapUse._(
    this.mode, {
    required this.interactive,
    required this.bounded,
    this.zoomButtons = false,
    this.fitButton = false,
    this.layers = false,
    this.legend = false,
    this.scale = false,
  });

  /// The resident's Map tab: pinned to the barangay like the portal, the
  /// whole dock, layers and legend.
  static const browse = BrgyMapUse._(BrgyMapMode.browse,
      interactive: true, bounded: true, zoomButtons: true, fitButton: true, layers: true, legend: true, scale: true);

  /// A picture of a place (View Report): no gestures, no controls.
  static const report = BrgyMapUse._(BrgyMapMode.report, interactive: false, bounded: false);

  /// The report form's pin picker: the map slides under a fixed pin.
  static const pick = BrgyMapUse._(BrgyMapMode.pick, interactive: true, bounded: false);

  /// A tanod's dispatch: the job's pin, the route, the tanod; zoom and
  /// frame buttons and a scale bar.
  static const job = BrgyMapUse._(BrgyMapMode.job,
      interactive: true, bounded: false, zoomButtons: true, fitButton: true, scale: true);

  /// Turn-by-turn: the screen moves the camera; the map shows a scale
  /// bar and leaves the rest of the glass to the directions.
  static const navigate = BrgyMapUse._(BrgyMapMode.navigate, interactive: true, bounded: false, scale: true);

  final BrgyMapMode mode;

  /// Pan, zoom and taps.
  final bool interactive;

  /// Keep the camera over the residential grid, zoom 15 to 18 (MapLibre).
  final bool bounded;

  final bool zoomButtons;

  /// The portal's "Frame every complaint" button.
  final bool fitButton;

  /// The Layers tile and its row (dim outside, places).
  final bool layers;

  /// The legend button and card.
  final bool legend;

  final bool scale;

  /// Any control drawn over the map.
  bool get hasControls => zoomButtons || fitButton || layers || legend || scale;

  /// MapLibre zooms: the portal's 15 to 18 on the barangay; further out
  /// elsewhere, so a tanod far from the job can still frame the route.
  double get minZoom => bounded ? 15 : 3;
  double get maxZoom => 18;
}

/// One report on the map, in the portal's look: a disc in the complaint
/// type's [colour] with its symbol ([glyph], a category icon key) in
/// white. [muted] is an incident the barangay published that is not the
/// viewer's own (0073): a white disc ringed in the colour. [dot] is the
/// status on the disc's shoulder; [pulse] a soft halo (in progress).
@immutable
class BrgyMapPin {
  const BrgyMapPin({
    required this.id,
    required this.point,
    required this.colour,
    required this.glyph,
    this.dot,
    this.muted = false,
    this.pulse = false,
  });

  final String id;
  final ll.LatLng point;
  final Color colour;
  final String glyph;
  final Color? dot;
  final bool muted;
  final bool pulse;

  String get imageKey => 'p${colour.toARGB32()}-${dot?.toARGB32()}-$glyph-${muted ? 1 : 0}-${pulse ? 1 : 0}';

  @override
  bool operator ==(Object other) =>
      other is BrgyMapPin &&
      other.id == id &&
      other.point == point &&
      other.colour == colour &&
      other.glyph == glyph &&
      other.dot == dot &&
      other.muted == muted &&
      other.pulse == pulse;

  @override
  int get hashCode => Object.hash(id, point, colour, glyph, dot, muted, pulse);
}

/// One row of the legend card: a complaint type and how many are shown.
@immutable
class BrgyMapLegendEntry {
  const BrgyMapLegendEntry({required this.label, required this.colour, required this.glyph, required this.count});

  final String label;
  final Color colour;
  final String glyph;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is BrgyMapLegendEntry && other.label == label && other.colour == colour && other.glyph == glyph && other.count == count;

  @override
  int get hashCode => Object.hash(label, colour, glyph, count);
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

  void move(ll.LatLng p, double zoom) => _apply(ml.CameraUpdate.newLatLngZoom(_ml(p), _mlZoom(zoom)));

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
  void fit(List<ll.LatLng> points, {double padding = 48, double? top, double? bottom}) {
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
      top: top ?? padding,
      right: padding,
      bottom: bottom ?? padding,
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
    required this.use,
    this.controller,
    this.initialCenter = brgyCentre,
    this.initialZoom = 17,
    this.pins = const [],
    this.selectedPinId,
    this.onPinTap,
    this.onMoved,
    this.accuracyCentre,
    this.accuracyMetres,
    this.route = const [],
    this.me,
    this.legend = const [],
    this.controlsPadding = EdgeInsets.zero,
    this.cornerRadius = 0,
    this.cornerColour,
  });

  final BrgyMapUse use;
  final BrgyMapController? controller;
  final ll.LatLng initialCenter;
  final double initialZoom;

  final List<BrgyMapPin> pins;

  /// The pin whose card is open: drawn larger, on top of the others.
  final String? selectedPinId;
  final ValueChanged<String>? onPinTap;

  /// Where the camera settled after a person moved the map.
  final ValueChanged<ll.LatLng>? onMoved;

  /// A GPS fix's accuracy, drawn as a circle on the ground.
  final ll.LatLng? accuracyCentre;
  final double? accuracyMetres;

  /// A route to draw (the walking route to a dispatch).
  final List<ll.LatLng> route;

  /// Where the person is, as a blue dot (navigation).
  final ll.LatLng? me;

  /// The legend card's rows ([BrgyMapUse.legend]).
  final List<BrgyMapLegendEntry> legend;

  /// Keeps the controls and the attribution clear of what the screen
  /// draws over the map's edges (a card at the bottom, a bar at the top).
  final EdgeInsets controlsPadding;

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
  static Future<Map<String, dynamic>?>? _fogSteps;
  static Future<Map<String, dynamic>?>? _landmarkData;

  late final BrgyMapController _ctl = widget.controller ?? BrgyMapController();
  ml.MapLibreMapController? _map;
  final _images = <String>{};
  bool _styleReady = false;
  String? _style;
  bool? _styleDark;

  // the overlay's state: which card is open, which layers are on, the scale
  BrgyMapPanel _panel = BrgyMapPanel.none;
  bool _dim = true;
  bool _places = true;
  final _scale = ValueNotifier<double?>(null);

  Future<String> _loadStyle(bool dark) =>
      _styles[dark] ??= rootBundle.loadString('assets/map/style-${dark ? 'dark' : 'light'}.json');

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
    if (!listEquals(old.pins, widget.pins) || old.selectedPinId != widget.selectedPinId) unawaited(_setPins());
    if (!listEquals(old.route, widget.route)) unawaited(_setRoute());
    if (old.me != widget.me) unawaited(_setMe());
    if (old.accuracyCentre != widget.accuracyCentre || old.accuracyMetres != widget.accuracyMetres) {
      unawaited(_setAccuracy());
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _created(ml.MapLibreMapController map) {
    _map = map;
    _ctl._attach(map);
    map.onFeatureTapped.add((point, latLng, id, layerId, annotation) {
      if (layerId == 'pins') _tapPin(id);
    });
  }

  void _tapPin(String id) {
    final tap = widget.onPinTap;
    if (tap == null) return;
    if (_panel != BrgyMapPanel.none) setState(() => _panel = BrgyMapPanel.none);
    // As the portal opens a case: the camera eases to the pin, close
    // enough to read the street, with the pin in the upper part of the
    // map so the card that rises from the bottom does not cover it.
    for (final p in widget.pins) {
      if (p.id != id) continue;
      final map = _map;
      final cam = map?.cameraPosition;
      if (map != null && cam != null) {
        final z = math.min(math.max(cam.zoom, 17.0), widget.use.maxZoom);
        final h = context.size?.height ?? 600;
        final lat = p.point.latitude - _metresPerPixel(p.point.latitude, z) * h * .23 / 110574;
        _ctl._programmatic = true;
        unawaited(map.animateCamera(ml.CameraUpdate.newLatLngZoom(ml.LatLng(lat, p.point.longitude), z),
            duration: const Duration(milliseconds: 600)));
      }
      break;
    }
    tap(id);
  }

  void _idle() {
    _updateScale();
    final c = _ctl;
    if (c._programmatic) {
      c._programmatic = false;
      return;
    }
    final target = _map?.cameraPosition?.target;
    if (target != null) widget.onMoved?.call(ll.LatLng(target.latitude, target.longitude));
  }

  /// Ground metres under one screen point at MapLibre zoom [z].
  static double _metresPerPixel(double lat, double z) =>
      2 * math.pi * 6378137 * math.cos(lat * math.pi / 180) / (512 * math.pow(2, z));

  void _updateScale() {
    if (!widget.use.scale) return;
    final cam = _map?.cameraPosition;
    if (cam == null) return;
    _scale.value = _metresPerPixel(cam.target.latitude, cam.zoom);
  }

  void _fit() {
    final pts = [
      for (final p in widget.pins)
        if (!widget.use.bounded || withinBrgyBounds(p.point)) p.point,
      ?widget.me,
      if (widget.me == null) ?widget.accuracyCentre,
    ];
    if (pts.isEmpty) {
      _ctl.move(widget.use.bounded ? brgyCentre : widget.initialCenter, widget.use.bounded ? 16 : widget.initialZoom);
    } else {
      final pad = widget.controlsPadding;
      _ctl.fit(pts, padding: 56, top: pad.top + 56, bottom: pad.bottom + 56);
    }
  }

  void _togglePanel(BrgyMapPanel p) => setState(() => _panel = _panel == p ? BrgyMapPanel.none : p);

  Future<void> _setDim(bool on) async {
    setState(() => _dim = on);
    final map = _map;
    if (map == null || !_styleReady) return;
    for (final id in ['brgy-fog', for (var k = 1; k <= 6; k++) 'fog-s$k']) {
      try {
        await map.setLayerVisibility(id, on);
      } catch (_) {}
    }
  }

  Future<void> _setPlaces(bool on) async {
    setState(() => _places = on);
    final map = _map;
    if (map == null || !_styleReady) return;
    for (final id in ['landmarks-badge', 'landmarks-label']) {
      try {
        await map.setLayerVisibility(id, on);
      } catch (_) {}
    }
  }

  // ---------- layers -------------------------------------------

  Future<void> _styleLoaded() async {
    final map = _map;
    if (map == null) return;
    _styleReady = true;
    // a new style is a new map: every image goes in again
    _images.clear();
    final dark = context.isDark;
    try {
      await _addFog(map, dark);
      await _addPlaceNames(map, dark);
      await _addLandmarks(map, dark);

      await map.addGeoJsonSource('accuracy', _empty);
      await map.addFillLayer('accuracy', 'accuracy-fill', const ml.FillLayerProperties(fillColor: '#00308F', fillOpacity: 0.12),
          enableInteraction: false);
      await map.addLineLayer('accuracy', 'accuracy-line',
          const ml.LineLayerProperties(lineColor: '#00308F', lineOpacity: 0.4, lineWidth: 1),
          enableInteraction: false);
      await _setAccuracy();

      // The walking route to a dispatch, under the pins.
      await map.addGeoJsonSource('route', _empty);
      await map.addLineLayer('route', 'route-casing',
          const ml.LineLayerProperties(lineColor: '#FFFFFF', lineWidth: 7, lineJoin: 'round', lineCap: 'round'),
          enableInteraction: false);
      await map.addLineLayer('route', 'route-line',
          const ml.LineLayerProperties(lineColor: '#FF9800', lineWidth: 4, lineJoin: 'round', lineCap: 'round'),
          enableInteraction: false);
      await _setRoute();

      // The pins: the portal's icon-size for each zoom, a third larger
      // for the one whose card is open, which is also drawn on top.
      await map.addGeoJsonSource('pins', _empty, promoteId: 'id');
      await map.addSymbolLayer(
        'pins',
        'pins',
        const ml.SymbolLayerProperties(
          iconImage: ['get', 'img'],
          iconSize: [
            'interpolate', ['linear'], ['zoom'],
            15, ['case', ['get', 'sel'], .81, .62],
            16, ['case', ['get', 'sel'], .96, .74],
            18, ['case', ['get', 'sel'], 1.24, .95],
          ],
          iconAnchor: 'center',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          symbolSortKey: ['case', ['get', 'sel'], 1, 0],
        ),
        enableInteraction: widget.onPinTap != null,
      );
      await _setPins();

      // You-are-here, over everything.
      await map.addGeoJsonSource('me', _empty);
      await map.addCircleLayer(
        'me',
        'me-dot',
        const ml.CircleLayerProperties(circleRadius: 8, circleColor: '#1A73E8', circleStrokeColor: '#FFFFFF', circleStrokeWidth: 3),
        enableInteraction: false,
      );
      await _setMe();
      _updateScale();
    } catch (e) {
      debugPrint('BrgyMap layers: $e');
    }
  }

  static const _empty = {'type': 'FeatureCollection', 'features': []};

  /// The fog of war (spatial.js): the world with the barangay cut out,
  /// dimmed rather than hidden so the bordering streets still help, and
  /// six steps of fog cut in metres round the line (assets/map/fog.json,
  /// tools/build_fog.py) for a soft edge instead of an outline. The
  /// portal lets its fog breathe; on a phone it holds still (no work per
  /// frame), at the middle of the portal's range.
  Future<void> _addFog(ml.MapLibreMapController map, bool dark) async {
    final rings = await (_rings ??= _loadRings());
    final vis = _dim ? 'visible' : 'none';
    if (rings.isNotEmpty) {
      List<List<double>> coords(List<ll.LatLng> r) => [
            for (final p in r) [p.longitude, p.latitude],
            if (r.first != r.last) [r.first.longitude, r.first.latitude],
          ];
      await map.addGeoJsonSource('brgy-fog', {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[-179.9, -85], [179.9, -85], [179.9, 85], [-179.9, 85], [-179.9, -85]],
                for (final r in rings) coords(r),
              ],
            },
          },
        ],
      });
      await map.addFillLayer('brgy-fog', 'brgy-fog', ml.FillLayerProperties(fillColor: '#0D1117', fillOpacity: .28, visibility: vis),
          enableInteraction: false);
    }
    final steps = await (_fogSteps ??= _loadJson('assets/map/fog.json'));
    if (steps == null) return;
    await map.addGeoJsonSource('fog-steps', steps);
    for (var k = 1; k <= 6; k++) {
      await map.addFillLayer(
        'fog-steps',
        'fog-s$k',
        ml.FillLayerProperties(fillColor: dark ? '#070A18' : '#0D1117', fillOpacity: .08, visibility: vis),
        filter: ['==', ['get', 'step'], k],
        enableInteraction: false,
      );
    }
  }

  /// The names of the places round the barangay, large and faint under
  /// the pins (spatial.js biglab): the barangay itself, Villamor, the
  /// airport terminal, Newport and the neighbouring barangays, fading out
  /// as you zoom in. Orange at night, as on the portal.
  Future<void> _addPlaceNames(ml.MapLibreMapController map, bool dark) async {
    Map<String, dynamic> pt(double lng, double lat, String name, String? sub, double k, double o, int p) => {
          'type': 'Feature',
          'properties': {'name': name, 'sub': ?sub, 'k': k, 'o': o, 'p': p},
          'geometry': {'type': 'Point', 'coordinates': [lng, lat]},
        };
    await map.addGeoJsonSource('biglab', {
      'type': 'FeatureCollection',
      'features': [
        pt(brgyCentre.longitude, brgyCentre.latitude + 0.0004, 'BARANGAY 183', 'PASAY CITY · ZONE 20', 1, .11, 0),
        pt(121.02433, 14.51713, 'VILLAMOR AIR BASE', 'PHILIPPINE AIR FORCE', .8, .12, 1),
        pt(121.01375, 14.51922, 'NAIA TERMINAL 3', 'NINOY AQUINO INTERNATIONAL AIRPORT', .75, .12, 1),
        pt(121.01768, 14.51954, 'NEWPORT CITY', 'RESORTS WORLD MANILA', .6, .105, 2),
        pt(121.0209, 14.5249, 'VILLAMOR GOLF COURSE', 'VILLAMOR AIR BASE', .55, .1, 2),
        pt(121.02057, 14.53049, 'HUMABON PLACE', 'MAGALLANES', .55, .1, 2),
        pt(121.00790, 14.53148, 'MARICABAN', 'PASAY CITY', .55, .1, 2),
        pt(121.00774, 14.52843, 'BARANGAY 184', null, .4, .09, 3),
        pt(121.01100, 14.52751, 'BARANGAY 185', null, .4, .09, 3),
        pt(121.01029, 14.53044, 'BARANGAY 182', null, .4, .09, 3),
        pt(121.01130, 14.53002, 'BARANGAY 181', null, .33, .08, 4),
        pt(121.01170, 14.53019, 'BARANGAY 180', null, .33, .08, 4),
        pt(121.00489, 14.53177, 'BARANGAY 186', null, .4, .09, 3),
        pt(121.00811, 14.53198, 'BARANGAY 168', null, .33, .08, 4),
      ],
    });
    final m = dark ? 1.45 : 1.0;
    await map.addSymbolLayer(
      'biglab',
      'biglab',
      ml.SymbolLayerProperties(
        textField: const [
          'format',
          ['get', 'name'], <String, dynamic>{},
          ['case', ['has', 'sub'], '\n', ''], <String, dynamic>{},
          ['coalesce', ['get', 'sub'], ''], {'font-scale': .3},
        ],
        textFont: const ['Noto Sans Bold'],
        textLetterSpacing: .16,
        textPadding: 12,
        symbolSortKey: const ['get', 'p'],
        textMaxWidth: 40,
        textSize: const [
          'interpolate', ['exponential', 2], ['zoom'],
          15, ['*', ['get', 'k'], 30],
          18, ['*', ['get', 'k'], 240],
        ],
        textColor: dark ? '#FF9D3C' : '#141B34',
        textOpacity: [
          'interpolate', ['linear'], ['zoom'],
          15, ['*', m, ['get', 'o']],
          16.4, ['*', m * .45, ['get', 'o']],
          17.2, 0,
        ],
      ),
      enableInteraction: false,
    );
  }

  /// The barangay hall, schools, chapels, police posts, clinics, parks,
  /// malls — the same curated OpenStreetMap file and group colours as the
  /// portal (assets/map/landmarks.geojson), as round icon badges (Ace's
  /// pick, 5 Oct); names from zoom 15.5 in the portal's label colours.
  /// Under the pins, and never tappable, so a tap always means a pin.
  Future<void> _addLandmarks(ml.MapLibreMapController map, bool dark) async {
    try {
      final data = await (_landmarkData ??= _loadJson('assets/map/landmarks.geojson'));
      if (data == null || !mounted) return;
      await map.addGeoJsonSource('landmarks', data);
      if (!mounted) return;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      for (final g in _landmarkLook.entries) {
        await map.addImage('lm-${g.key}', await _landmarkPng(g.value.$1, g.value.$2, dpr));
      }
      await map.addImage('lm-other', await _landmarkPng(Icons.place_rounded, const Color(0xFF64748B), dpr));
      final vis = _places ? 'visible' : 'none';
      await map.addSymbolLayer(
        'landmarks',
        'landmarks-badge',
        ml.SymbolLayerProperties(
          iconImage: ['match', ['get', 'group'], for (final k in _landmarkLook.keys) ...[k, 'lm-$k'], 'lm-other'],
          iconSize: const ['interpolate', ['linear'], ['zoom'], 14, 0.62, 18, 1.0],
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          visibility: vis,
        ),
        enableInteraction: false,
      );
      await map.addSymbolLayer(
        'landmarks',
        'landmarks-label',
        ml.SymbolLayerProperties(
          textField: const ['get', 'name'],
          textFont: const ['Noto Sans Bold'],
          textSize: const ['interpolate', ['linear'], ['zoom'], 15.5, 10.5, 18, 13],
          textOffset: const [0, 1.55],
          textAnchor: 'top',
          textMaxWidth: 9,
          textOptional: true,
          textColor: dark ? '#F3F3F3' : '#1F2937',
          textHaloColor: dark ? 'rgba(20,24,29,0.9)' : 'rgba(255,255,255,0.95)',
          textHaloWidth: 1.4,
          visibility: vis,
        ),
        minzoom: 15.5,
        enableInteraction: false,
      );
    } catch (e) {
      debugPrint('BrgyMap landmarks: $e');
    }
  }

  static Future<Map<String, dynamic>?> _loadJson(String asset) async {
    try {
      return jsonDecode(await rootBundle.loadString(asset)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setPins() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final dark = context.isDark;
    for (final p in widget.pins) {
      if (_images.add(p.imageKey)) await map.addImage(p.imageKey, await pinPng(p, dpr, dark: dark));
    }
    await map.setGeoJsonSource('pins', pinFeatures(widget.pins, selected: widget.selectedPinId));
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
                  'geometry': {'type': 'LineString', 'coordinates': [for (final p in r) [p.longitude, p.latitude]]},
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
                  'geometry': {'type': 'Point', 'coordinates': [p.longitude, p.latitude]},
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
                  'geometry': {'type': 'Polygon', 'coordinates': [_circle(c, m)]},
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
        [c.longitude + dLng * math.cos(2 * math.pi * i / 64), c.latitude + dLat * math.sin(2 * math.pi * i / 64)],
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
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: 13, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    return _toPng(rec, size, dpr);
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
          for (final p in (m['geometry'] as List)) ll.LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
        ]);
      }
      bool near(ll.LatLng a, ll.LatLng b) =>
          (a.latitude - b.latitude).abs() < 1e-7 && (a.longitude - b.longitude).abs() < 1e-7;
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
    final use = widget.use;
    final corner = widget.cornerColour;
    return Stack(
      fit: StackFit.expand,
      children: [
        _mapView(context),
        if (widget.cornerRadius > 0 && corner != null)
          IgnorePointer(child: CustomPaint(painter: _CornerMask(radius: widget.cornerRadius, colour: corner))),
        if (use.hasControls)
          BrgyMapOverlay(
            use: use,
            padding: widget.controlsPadding,
            panel: _panel,
            dim: _dim,
            places: _places,
            legend: widget.legend,
            scale: _scale,
            onZoomIn: () => _ctl.zoomBy(1),
            onZoomOut: () => _ctl.zoomBy(-1),
            onFit: _fit,
            onPanel: _togglePanel,
            onDim: _setDim,
            onPlaces: _setPlaces,
          ),
      ],
    );
  }

  Widget _mapView(BuildContext context) {
    final style = _style;
    final bg = context.colors.bg;
    if (style == null) return ColoredBox(color: bg);
    final use = widget.use;
    final i = use.interactive;
    final pad = widget.controlsPadding;
    // the portal's box, with its slack
    const bLat = _spanLat * (1 + _pad), bLng = _spanLng * (1 + _pad);
    return ml.MapLibreMap(
      // A new style (dark mode switched) is a new map, so the layers are
      // added again on top of it.
      key: ValueKey(_styleDark),
      styleString: style,
      initialCameraPosition: ml.CameraPosition(target: _ml(widget.initialCenter), zoom: _mlZoom(widget.initialZoom)),
      onMapCreated: _created,
      onStyleLoadedCallback: _styleLoaded,
      onCameraIdle: _idle,
      onMapClick: (_, _) {
        if (_panel != BrgyMapPanel.none) setState(() => _panel = BrgyMapPanel.none);
      },
      trackCameraPosition: true,
      cameraTargetBounds: use.bounded
          ? ml.CameraTargetBounds(ml.LatLngBounds(
              southwest: ml.LatLng(brgyCentre.latitude - bLat, brgyCentre.longitude - bLng),
              northeast: ml.LatLng(brgyCentre.latitude + bLat, brgyCentre.longitude + bLng),
            ))
          : ml.CameraTargetBounds.unbounded,
      minMaxZoomPreference: ml.MinMaxZoomPreference(use.minZoom, use.maxZoom),
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: i,
      zoomGesturesEnabled: i,
      doubleClickZoomEnabled: i,
      dragEnabled: false,
      compassEnabled: false,
      logoEnabled: false,
      foregroundLoadColor: bg,
      // The portal's compact attribution: bottom right, under the zoom
      // pair, clear of whatever the screen draws over the bottom edge.
      attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
      attributionButtonMargins: math.Point(pad.right + 8, pad.bottom + 8),
      annotationOrder: const [],
      gestureRecognizers: i ? {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)} : null,
    );
  }
}

ml.LatLng _ml(ll.LatLng p) => ml.LatLng(p.latitude, p.longitude);

/// The pins as a GeoJSON source. Reports filed from the very same spot
/// would sit exactly on top of each other and read as one pin (the
/// portal's draw(), Rose 2 Oct 2026), so each repeat is set a few metres
/// round the spot.
@visibleForTesting
Map<String, dynamic> pinFeatures(List<BrgyMapPin> pins, {String? selected}) {
  final seen = <String, int>{};
  final features = <Map<String, dynamic>>[];
  for (final p in pins) {
    final key = '${p.point.latitude.toStringAsFixed(5)},${p.point.longitude.toStringAsFixed(5)}';
    final n = seen[key] ?? 0;
    seen[key] = n + 1;
    var lng = p.point.longitude, lat = p.point.latitude;
    if (n > 0) {
      final ang = n * 2.4, d = 0.00004 * (n / 6).ceil();
      lng += d * math.cos(ang) / math.cos(lat * math.pi / 180);
      lat += d * math.sin(ang);
    }
    features.add({
      'type': 'Feature',
      'id': p.id,
      'properties': {'id': p.id, 'img': p.imageKey, 'sel': p.id == selected},
      'geometry': {'type': 'Point', 'coordinates': [lng, lat]},
    });
  }
  return {'type': 'FeatureCollection', 'features': features};
}

/// Paints one pin, 56 x 56 logical pixels, centred: the portal's pinTear()
/// (a 30 px disc, a 2 px white edge inside it, the symbol at 17 px with a
/// 2.2 stroke, two shadows: navy by day, black at night), with the app's
/// status dot and halo.
void paintBrgyPin(Canvas canvas, BrgyMapPin p, {required bool dark}) {
  const c = Offset(28, 28);
  final glyph = categoryMapGlyph(p.glyph);
  if (p.muted) {
    canvas.saveLayer(Offset.zero & const Size(56, 56), Paint()..color = const Color(0xD9FFFFFF));
    canvas.drawCircle(c + const Offset(0, 1.5), 15,
        Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6));
    canvas.drawCircle(c, 15, Paint()..color = Colors.white);
    canvas.drawCircle(c, 13.8, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = p.colour);
    glyph.paint(canvas, c, 17, p.colour, stroke: 2.2);
    canvas.restore();
    return;
  }
  if (p.pulse) canvas.drawCircle(c, 22, Paint()..color = p.colour.withValues(alpha: .22));
  final sh = dark ? const Color(0xFF000000) : const Color(0xFF141B34);
  canvas.drawCircle(c + const Offset(0, 3), 15,
      Paint()..color = sh.withValues(alpha: dark ? .5 : .26)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6));
  canvas.drawCircle(c + const Offset(0, 1), 15,
      Paint()..color = sh.withValues(alpha: dark ? .72 : .42)..maskFilter = const MaskFilter.blur(BlurStyle.normal, .9));
  canvas.drawCircle(c, 15, Paint()..color = p.colour);
  canvas.drawCircle(c, 14, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white);
  glyph.paint(canvas, c, 17, Colors.white, stroke: 2.2);
  final dot = p.dot;
  if (dot != null) {
    const at = Offset(39, 17);
    canvas.drawCircle(at, 5.6, Paint()..color = Colors.white);
    canvas.drawCircle(at, 4, Paint()..color = dot);
  }
}

/// [paintBrgyPin] as a map image at the phone's pixel ratio (MapLibre
/// shows image pixels as physical pixels).
Future<Uint8List> pinPng(BrgyMapPin p, double dpr, {required bool dark}) async {
  const size = Size(56, 56);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..scale(dpr);
  paintBrgyPin(canvas, p, dark: dark);
  return _BrgyMapState._toPng(rec, size, dpr);
}

/// A pin as a widget, the size the map draws it at zoom 16: for legends,
/// previews and tests.
class BrgyMapPinPreview extends StatelessWidget {
  const BrgyMapPinPreview(this.pin, {super.key, this.scale = .74});

  final BrgyMapPin pin;
  final double scale;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 56 * scale,
        child: CustomPaint(painter: _PinPainter(pin, context.isDark, scale)),
      );
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.pin, this.dark, this.scale);

  final BrgyMapPin pin;
  final bool dark;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    paintBrgyPin(canvas, pin, dark: dark);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.pin != pin || old.dark != dark || old.scale != scale;
}

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
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    canvas.drawPath(outside, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_CornerMask old) => old.radius != radius || old.colour != colour;
}

// ---------- the controls over the map ----------------------------------

/// Which card over the map is open: the portal shows one at a time.
enum BrgyMapPanel { none, layers, legend }

/// The portal's Material surfaces (sd-light.css, sd-dark.css): white by
/// day lifted by navy shadows; graphite at night, a little lighter for
/// each level, lifted by black ones. The active control is brand orange
/// with dark lettering.
@immutable
class BrgyMapSkin {
  const BrgyMapSkin(this.dark);

  factory BrgyMapSkin.of(BuildContext context) => BrgyMapSkin(context.isDark);

  final bool dark;

  static const orange = Color(0xFFFF9800);
  static const onOrange = Color(0xFF2B1A00);

  /// Controls (level 1), panels (2), the case card (3).
  Color surface(int level) =>
      dark ? const [Color(0xFF22242A), Color(0xFF22242A), Color(0xFF272930), Color(0xFF2D3037)][level.clamp(0, 3)] : Colors.white;
  Color get ink => dark ? const Color(0xFFE9EBF2) : const Color(0xFF141B34);
  Color get muted => dark ? const Color(0xFFA9AEBB) : const Color(0xFF5B6178);
  Color get line => dark ? const Color(0x17FFFFFF) : const Color(0x1A141B34);
  Color get link => dark ? const Color(0xFF8DB2FF) : const Color(0xFF00308F);

  List<BoxShadow> elevation(int level) {
    final k = dark ? const Color(0xFF000000) : const Color(0xFF141B34);
    double a(double light, double night) => dark ? night : light;
    return switch (level) {
      3 => [
          BoxShadow(color: k.withValues(alpha: a(.16, .5)), blurRadius: 8, spreadRadius: 3, offset: const Offset(0, 4)),
          BoxShadow(color: k.withValues(alpha: a(.26, .7)), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      2 => [
          BoxShadow(color: k.withValues(alpha: a(.22, .62)), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: k.withValues(alpha: a(.14, .46)), blurRadius: 6, spreadRadius: 2, offset: const Offset(0, 2)),
        ],
      _ => [
          BoxShadow(color: k.withValues(alpha: a(.22, .62)), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: k.withValues(alpha: a(.12, .4)), blurRadius: 3, spreadRadius: 1, offset: const Offset(0, 1)),
        ],
    };
  }
}

/// The controls a [BrgyMapUse] asks for, laid out for a thumb: the dock
/// and the zoom pair on the right above the screen's bottom card, the
/// Layers tile and the scale bar on the left, the open card beside them.
/// Public so tests and captures can draw it without a map under it.
class BrgyMapOverlay extends StatelessWidget {
  const BrgyMapOverlay({
    super.key,
    required this.use,
    this.padding = EdgeInsets.zero,
    this.panel = BrgyMapPanel.none,
    this.dim = true,
    this.places = true,
    this.legend = const [],
    this.scale,
    this.onZoomIn,
    this.onZoomOut,
    this.onFit,
    this.onPanel,
    this.onDim,
    this.onPlaces,
  });

  final BrgyMapUse use;
  final EdgeInsets padding;
  final BrgyMapPanel panel;
  final bool dim;
  final bool places;
  final List<BrgyMapLegendEntry> legend;

  /// Ground metres per screen point, null until the map has settled.
  final ValueListenable<double?>? scale;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onFit;
  final ValueChanged<BrgyMapPanel>? onPanel;
  final ValueChanged<bool>? onDim;
  final ValueChanged<bool>? onPlaces;

  @override
  Widget build(BuildContext context) {
    final showLegend = use.legend && legend.isNotEmpty;
    // the attribution button sits in the bottom-right corner, under the column
    final bottom = padding.bottom + 8;
    final right = padding.right + 12;
    final left = padding.left + 12;
    final s = scale;
    return Stack(children: [
      // the dock and the zoom pair
      if (use.fitButton || showLegend || use.zoomButtons)
        Positioned(
          right: right,
          bottom: bottom + 34,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (use.fitButton)
              BrgyMapButton(glyph: MapIcons.focus, label: context.tr('Frame the map', 'Ipakita ang buong mapa'), onTap: onFit),
            if (showLegend) ...[
              const SizedBox(height: 8),
              BrgyMapButton(
                glyph: MapIcons.list,
                label: context.tr('Legend', 'Alamat'),
                on: panel == BrgyMapPanel.legend,
                onTap: () => onPanel?.call(BrgyMapPanel.legend),
              ),
            ],
            if (use.zoomButtons) ...[
              const SizedBox(height: 14),
              BrgyMapButton(glyph: MapIcons.plus, label: context.tr('Zoom in', 'Lapitan'), onTap: onZoomIn),
              const SizedBox(height: 8),
              BrgyMapButton(glyph: MapIcons.minus, label: context.tr('Zoom out', 'Lumayo'), onTap: onZoomOut),
            ],
          ]),
        ),
      // the Layers tile, its row beside it, the scale bar under it
      Positioned(
        left: left,
        bottom: bottom,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (use.layers)
            Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              BrgyMapLayersTile(on: panel == BrgyMapPanel.layers, onTap: () => onPanel?.call(BrgyMapPanel.layers)),
              if (panel == BrgyMapPanel.layers) ...[
                const SizedBox(width: 8),
                BrgyMapLayersRow(dim: dim, places: places, onDim: onDim, onPlaces: onPlaces),
              ],
            ]),
          if (use.scale && s != null) ...[
            if (use.layers) const SizedBox(height: 10),
            ValueListenableBuilder<double?>(
              valueListenable: s,
              builder: (_, mpp, _) => mpp == null ? const SizedBox(height: 18) : BrgyMapScaleBar(metresPerPixel: mpp),
            ),
          ],
        ]),
      ),
      if (showLegend && panel == BrgyMapPanel.legend)
        Positioned(
          right: right + 44 + 10,
          bottom: bottom + 34,
          child: BrgyMapLegendCard(entries: legend),
        ),
    ]);
  }
}

/// A dock button (spatial.php .p-dock-btn): a 44 px Material square,
/// 14 px corners, the portal's outline icon; orange while its card is
/// open.
class BrgyMapButton extends StatelessWidget {
  const BrgyMapButton({super.key, required this.glyph, required this.label, this.onTap, this.on = false});

  final MapGlyph glyph;
  final String label;
  final VoidCallback? onTap;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: on ? BrgyMapSkin.orange : k.surface(1),
              borderRadius: BorderRadius.circular(14),
              boxShadow: k.elevation(on ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Center(child: MapGlyphIcon(glyph, size: 19, colour: on ? BrgyMapSkin.onOrange : k.ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The portal's Layers tile (lyr-tile): a square at the map's bottom left
/// with the layers mark and its name; an orange edge while it is open.
class BrgyMapLayersTile extends StatelessWidget {
  const BrgyMapLayersTile({super.key, required this.on, this.onTap});

  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    return Semantics(
      button: true,
      selected: on,
      label: context.tr('Map layers', 'Mga layer ng mapa'),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: k.surface(1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (on) const BoxShadow(color: BrgyMapSkin.orange, spreadRadius: 2),
              ...k.elevation(2),
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            MapGlyphIcon(MapIcons.layers, size: 22, colour: on ? BrgyMapSkin.orange : k.ink, stroke: 2.2),
            const SizedBox(height: 3),
            Text(context.tr('Layers', 'Layers'),
                maxLines: 1, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, height: 1.1, color: k.ink)),
          ]),
        ),
      ),
    );
  }
}

/// The row of layers that opens beside the tile: a small picture per
/// layer with its name under it, ringed in orange when it is on. The app
/// has two: the fog outside the barangay and the places to steer by.
class BrgyMapLayersRow extends StatelessWidget {
  const BrgyMapLayersRow({super.key, required this.dim, required this.places, this.onDim, this.onPlaces});

  final bool dim;
  final bool places;
  final ValueChanged<bool>? onDim;
  final ValueChanged<bool>? onPlaces;

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 7),
      decoration: BoxDecoration(color: k.surface(2), borderRadius: BorderRadius.circular(16), boxShadow: k.elevation(2)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _LayerSwitch(
          on: dim,
          label: context.tr('Dim outside', 'I-dim sa labas'),
          picture: const CustomPaint(painter: _DimPainter()),
          glyph: MapIcons.dim,
          onTap: () => onDim?.call(!dim),
        ),
        const SizedBox(width: 6),
        _LayerSwitch(
          on: places,
          label: context.tr('Places', 'Mga lugar'),
          picture: const CustomPaint(painter: _PlacesPainter()),
          glyph: MapIcons.places,
          onTap: () => onPlaces?.call(!places),
        ),
      ]),
    );
  }
}

class _LayerSwitch extends StatelessWidget {
  const _LayerSwitch({required this.on, required this.label, required this.picture, required this.glyph, required this.onTap});

  final bool on;
  final String label;
  final Widget picture;
  final MapGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    return Semantics(
      toggled: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 70,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  if (on) const BoxShadow(color: BrgyMapSkin.orange, spreadRadius: 3),
                  ...k.elevation(1),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  picture,
                  Center(child: MapGlyphIcon(glyph, size: 20, colour: Colors.white.withValues(alpha: on ? 1 : .75), stroke: 2.4)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, height: 1.1, color: on ? k.ink : k.muted)),
          ]),
        ),
      ),
    );
  }
}

/// The portal's DIMPIC: a lit shape in a dimmed square.
class _DimPainter extends CustomPainter {
  const _DimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF3A4150));
    final shape = Path()
      ..moveTo(24 * s, 20 * s)
      ..lineTo(72 * s, 14 * s)
      ..lineTo(88 * s, 42 * s)
      ..lineTo(72 * s, 80 * s)
      ..lineTo(36 * s, 84 * s)
      ..lineTo(14 * s, 56 * s)
      ..close();
    canvas.drawPath(shape, Paint()..color = const Color(0xFF6B7385));
    canvas.drawPath(shape, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = BrgyMapSkin.orange.withValues(alpha: .9));
  }

  @override
  bool shouldRepaint(_DimPainter old) => false;
}

/// Three landmark dots in their group colours across a street.
class _PlacesPainter extends CustomPainter {
  const _PlacesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2E3A4C));
    canvas.drawLine(Offset(0, 70 * s), Offset(100 * s, 30 * s), Paint()..color = const Color(0xFF46536A)..strokeWidth = 7 * s);
    for (final (x, y, c) in const [(20.0, 26.0, Color(0xFF7C3AED)), (80.0, 76.0, Color(0xFF16A34A)), (84.0, 18.0, Color(0xFF0891B2))]) {
      canvas.drawCircle(Offset(x * s, y * s), 9 * s, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x * s, y * s), 7 * s, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_PlacesPainter old) => false;
}

/// The legend card (spatial.php #map-legend): "Complaint type", a row per
/// type with its symbol on a disc in its colour and how many are on the
/// map; a type with none is faded. Only a legend (Ace, 9 Oct): pressing a
/// row does nothing.
class BrgyMapLegendCard extends StatelessWidget {
  const BrgyMapLegendCard({super.key, required this.entries});

  final List<BrgyMapLegendEntry> entries;

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    final total = entries.fold<int>(0, (a, e) => a + e.count);
    final screen = MediaQuery.sizeOf(context);
    return Container(
      width: math.min(270, screen.width - 100),
      constraints: BoxConstraints(maxHeight: screen.height * .5),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: k.surface(2), borderRadius: BorderRadius.circular(16), boxShadow: k.elevation(2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(context.tr('COMPLAINT TYPE', 'URI NG SUMBONG'),
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 1.1, color: k.muted)),
        const SizedBox(height: 6),
        Flexible(
          child: SingleChildScrollView(
            child: Column(children: [
              for (final e in entries)
                Opacity(
                  opacity: e.count == 0 ? .45 : 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: e.colour,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: k.dark ? .6 : .2), blurRadius: 2, offset: const Offset(0, 1))],
                        ),
                        child: Center(child: MapGlyphIcon(categoryMapGlyph(e.glyph), size: 15, colour: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.label,
                            maxLines: 2, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.2, color: k.ink)),
                      ),
                      const SizedBox(width: 8),
                      Text('${e.count}',
                          style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: k.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(context.tr(total == 1 ? '1 report on the map' : '$total reports on the map', '$total ulat sa mapa'),
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 11, color: k.muted)),
      ]),
    );
  }
}

/// The portal's scale (MapLibre's ScaleControl, metric): a round distance
/// and a bar that long, read when the map settles rather than every frame.
class BrgyMapScaleBar extends StatelessWidget {
  const BrgyMapScaleBar({super.key, required this.metresPerPixel, this.maxWidth = 96});

  final double metresPerPixel;
  final double maxWidth;

  /// The largest 1, 2, 3 or 5 x 10^n metres that fits in [maxWidth].
  static double niceMetres(double metresPerPixel, double maxWidth) {
    final most = metresPerPixel * maxWidth;
    final p = math.pow(10, (math.log(most) / math.ln10).floor()).toDouble();
    final d = most / p;
    final n = d >= 5 ? 5 : d >= 3 ? 3 : d >= 2 ? 2 : 1;
    return n * p;
  }

  static String label(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km' : '${m.round()} m';

  @override
  Widget build(BuildContext context) {
    final k = BrgyMapSkin.of(context);
    final m = niceMetres(metresPerPixel, maxWidth);
    final w = m / metresPerPixel;
    final edge = k.dark ? Colors.white.withValues(alpha: .6) : const Color(0x99141B34);
    return Semantics(
      label: context.tr('Scale: ${label(m)}', 'Sukat: ${label(m)}'),
      excludeSemantics: true,
      child: Container(
        width: w,
        height: 18,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        decoration: BoxDecoration(
          color: k.surface(1).withValues(alpha: .78),
          border: Border(left: BorderSide(color: edge, width: 1.5), right: BorderSide(color: edge, width: 1.5), bottom: BorderSide(color: edge, width: 1.5)),
        ),
        child: Text(label(m), maxLines: 1, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 10, height: 1, color: k.ink)),
      ),
    );
  }
}

/// Barangay 183's outline, the bundled OSM relation the map draws
/// (7 Oct 2026, Rose): the report form keeps a pin inside it.
Future<List<List<ll.LatLng>>> brgyBoundary() => _BrgyMapState._rings ??= _BrgyMapState._loadRings();

/// Even-odd ray casting over every ring, so a hole stays outside. True
/// when the outline could not be read: the check never blocks a report
/// because a file failed to load.
bool insideBrgy(List<List<ll.LatLng>> rings, ll.LatLng p) {
  if (rings.isEmpty) return true;
  var inside = false;
  for (final r in rings) {
    for (var i = 0, j = r.length - 1; i < r.length; j = i++) {
      final a = r[i], b = r[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude < (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
        inside = !inside;
      }
    }
  }
  return inside;
}
