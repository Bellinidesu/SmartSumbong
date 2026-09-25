// SmartSumbong — Barangay 183 Map.
//
// Figma nodes 2212:45 and 2269:2809 (MAP - SEE REPORTS).
//
// The eye toggles the resident's own report pins on and off. Off by
// default, matching the design: a resident opening this tab is usually
// orienting themselves in the barangay, not auditing their own filings.
//
// The pins are the resident's own reports only. reports_resident_read
// enforces that, and it is the right scope — a public map of every
// complaint in the barangay would tell anyone which houses have reported
// their neighbours, which is exactly what the anonymous option exists to
// prevent.
//
// A barangay-wide heatmap is the admin's Spatial Distribution screen,
// where it is aggregated and behind a login.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import '../widgets/resident_nav_bar.dart';
import 'reports_screen.dart' show ReportStatus;

/// Barangay 183, Zone 20, Villamor, Pasay City — from OSM relation
/// 2988704. The same constant as the submit screen; if the barangay
/// boundary is ever corrected, both move together.
// The relation covers the whole barangay, most of which is the airport
// apron and Villamor Air Base — land with no residents and no
// complaints. Centring on the relation's centroid puts a resident over
// the runway. These are the values the admin portal's Spatial
// Distribution uses, kept identical so the two maps frame the same
// place; if the barangay revises one, revise both.
const _residentialCentre = LatLng(14.526905, 121.015543);
const _spanLat = 0.0110;
const _spanLng = 0.0115;

/// Google's 17z at this centre, which frames 1st Street through 31st.
const _defaultZoom = 17.0;

/// A ring large enough to cover the visible world. The fog is this
/// polygon with the barangay punched out of it.
const _world = <LatLng>[
  LatLng(-89.9, -179.9),
  LatLng(-89.9, 179.9),
  LatLng(89.9, 179.9),
  LatLng(89.9, -179.9),
];

class _Pin {
  const _Pin({
    required this.id,
    required this.point,
    required this.trackingId,
    required this.subject,
    required this.status,
  });

  final String id;
  final LatLng point;
  final String trackingId;
  final String subject;
  final ReportStatus status;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();

  bool _showReports = false;
  List<_Pin>? _pins;
  bool _loading = false;
  List<List<LatLng>> _rings = const [];

  @override
  void initState() {
    super.initState();
    _loadBoundary();
  }

  /// OSM returns the relation's ways unordered and unclosed, so they are
  /// joined end-to-end into rings. Same algorithm as the admin portal's
  /// Spatial Distribution, reading the same file.
  ///
  /// Bundled rather than fetched: the outline does not change between
  /// releases, and a resident on the edge of signal should still see
  /// which side of the boundary they are on.
  Future<void> _loadBoundary() async {
    try {
      final raw = await rootBundle.loadString('assets/geo/brgy183.json');
      final elements = (jsonDecode(raw) as Map)['elements'] as List;
      final rel = elements.firstWhere((e) => e['type'] == 'relation');

      final pool = <List<LatLng>>[];
      for (final m in (rel['members'] as List)) {
        if (m['type'] != 'way' || m['geometry'] == null) continue;
        pool.add([
          for (final p in (m['geometry'] as List))
            LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
        ]);
      }

      bool near(LatLng a, LatLng b) =>
          (a.latitude - b.latitude).abs() < 1e-7 &&
          (a.longitude - b.longitude).abs() < 1e-7;

      final rings = <List<LatLng>>[];
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

      if (!mounted || rings.isEmpty) return;
      setState(() => _rings = rings);
    } catch (_) {
      // The map is still useful without the outline.
    }
  }

  Future<void> _toggle() async {
    if (_showReports) {
      setState(() => _showReports = false);
      return;
    }

    setState(() {
      _showReports = true;
      _loading = _pins == null;
    });

    if (_pins != null) return;

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final rows = await client
          .from('reports')
          .select('id, tracking_id, subject, status, latitude, longitude')
          .eq('resident_id', uid)
          .isFilter('deleted_at', null);

      final pins = <_Pin>[];
      for (final r in rows) {
        final lat = (r['latitude'] as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        pins.add(_Pin(
          id: r['id'] as String,
          point: LatLng(lat, lng),
          trackingId: r['tracking_id'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          status: ReportStatus.parse(r['status'] as String?),
        ));
      }

      if (!mounted) return;
      setState(() {
        _pins = pins;
        _loading = false;
      });

      // Frame them, so a resident with one report far from the centre is
      // not left staring at an empty map.
      if (pins.isNotEmpty) _fitTo(pins);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pins = const [];
        _loading = false;
      });
    }
  }

  void _fitTo(List<_Pin> pins) {
    if (pins.length == 1) {
      _map.move(pins.first.point, 17);
      return;
    }
    final lats = pins.map((p) => p.point.latitude);
    final lngs = pins.map((p) => p.point.longitude);
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(lats.reduce((a, b) => a < b ? a : b),
              lngs.reduce((a, b) => a < b ? a : b)),
          LatLng(lats.reduce((a, b) => a > b ? a : b),
              lngs.reduce((a, b) => a > b ? a : b)),
        ),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  void _openPin(_Pin p) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '(${p.trackingId} - ${context.s.reportStatusLabel(p.status.wire)}) '
              '${p.subject}',
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
                color: context.colors.navy,
              ),
            ),
            const SizedBox(height: 18),
            FigmaPill(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/report', arguments: p.id);
              },
              child: Text(context.s.mapViewReport),
            ),
          ],
        ),
      ),
    );
  }

  // Figma MAP / MAP - SEE REPORTS: the title 28/800 50 from the top of
  // the screen, the 352-wide map 14 under it, the card 25 under the map
  // and 47 above the nav bar. The frame's map is a static picture; the
  // live tiles stand in for it and take whatever height is left.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final pins = _pins ?? const <_Pin>[];

    return Scaffold(
      bottomNavigationBar: const ResidentNavBar(current: ResidentTab.map),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
                height: (50 - MediaQuery.paddingOf(context).top)
                    .clamp(8.0, 50.0)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 43),
              child: Text(
                s.mapTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  height: 43.68 / 28,
                  color: context.colors.navy,
                ),
              ),
            ),
            const SizedBox(height: 14),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.colors.navy),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: _residentialCentre,
                            initialZoom: _defaultZoom,
                            // Pinned to the residential grid: the only
                            // area that can be panned to, and it cannot
                            // be zoomed out far enough to lose it.
                            cameraConstraint: CameraConstraint.contain(
                              bounds: LatLngBounds(
                                const LatLng(14.526905 - _spanLat,
                                    121.015543 - _spanLng),
                                const LatLng(14.526905 + _spanLat,
                                    121.015543 + _spanLng),
                              ),
                            ),
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.pinchZoom |
                                  InteractiveFlag.drag |
                                  InteractiveFlag.doubleTapZoom,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ph.smartsumbong.resident',
                              maxZoom: 19,
                            ),
                            // Everything outside 183 is dimmed rather
                            // than hidden, so a resident can still see
                            // the bordering streets and orient
                            // themselves. Permanent here: the admin
                            // portal has a toggle because an admin
                            // sometimes needs the surrounding city, but
                            // a resident filing a complaint only needs
                            // to know where the boundary is.
                            if (_rings.isNotEmpty)
                              PolygonLayer(
                                polygons: [
                                  Polygon(
                                    points: _world,
                                    holePointsList: _rings,
                                    color: const Color(0x8C0D1117),
                                  ),
                                  for (final ring in _rings)
                                    Polygon(
                                      points: ring,
                                      borderColor: const Color(0xE614181D),
                                      borderStrokeWidth: 2,
                                    ),
                                ],
                              ),

                            if (_showReports)
                              MarkerLayer(
                                markers: [
                                  for (final p in pins)
                                    Marker(
                                      point: p.point,
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.topCenter,
                                      // The frame's 22x23 tilted pin, its
                                      // tip on the report, inside the
                                      // same 40x40 tap target as before.
                                      child: GestureDetector(
                                        onTap: () => _openPin(p),
                                        child: CustomPaint(
                                          painter: _PinPainter(
                                            radius: 9.9,
                                            ring: 2.8,
                                            stroke: 2.2,
                                            colour: p.status.labelColour(
                                                        context) ==
                                                    context.colors.bg
                                                ? context.colors.navy
                                                : const Color(0xFFFF4949),
                                            fill: const Color(0xFFFBFBFB),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),

                        if (_loading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.2),
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                                color: Colors.white),
                          ),

                        // The drag affordance from the design, 25x25
                        // at 11/13 from the frame's bottom-left corner,
                        // with its y1 / blur 1 shadow.
                        const Positioned(
                          left: 11,
                          bottom: 13,
                          child: Icon(
                            Icons.open_with,
                            color: Color(0xFFFF9800),
                            size: 25,
                            shadows: [
                              Shadow(
                                color: Color(0xCC121212),
                                blurRadius: 1,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 47),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _MapCard(showing: _showReports, onToggle: _toggle),

                  // The orange pin straddling the card's top-left corner
                  // in the design (its 68x73 group at -16/-23).
                  // Decorative only — the title is indented to clear it.
                  // Filled with the card's own `field` (the frame's
                  // #FBFBFB) so it isn't a white blob in dark mode.
                  Positioned(
                    left: -16,
                    top: -23,
                    width: 68,
                    height: 73,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _PinPainter(
                          radius: 25.5,
                          ring: 9.4,
                          stroke: 2.5,
                          colour: const Color(0xFFFF9800),
                          fill: context.colors.field,
                          tip: const Offset(41.7, 64),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The white card under the map, with the eye button.
class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.showing,
    required this.onToggle,
  });

  final bool showing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // Verbatim from the MAP and MAP - SEE REPORTS frames. The grammar in
    // the second string ("you will back to") is the designer's; it is
    // reproduced as drawn because the copy was signed off as-is. The
    // Filipino translation (in i18n.dart) carries the meaning rather
    // than that grammar quirk.
    final s = context.s;
    final String body = showing ? s.mapCardBodyShowing : s.mapCardBodyHidden;

    // The frame's 352x131 card: the title at 52/17 across the width, the
    // body at 36 stopping at the pill (9 short of it in SEE REPORTS), and
    // the 60x45 orange pill 20 in from the right, centred on the card.
    return Container(
      constraints: const BoxConstraints(minHeight: 131),
      decoration: BoxDecoration(
        color: context.colors.field,
        border: Border.all(color: context.colors.navy, width: 2),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Padding(
            // The title's 31.2 line is kept as 3.6 above and below a 24
            // line, so the English single line sits where the frame has
            // it and a longer (Filipino) title doesn't wrap into gaps.
            padding: EdgeInsets.fromLTRB(34, 19, showing ? 87 : 78, 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    showing ? s.mapReportsSpotted : s.mapWantToSeeReports,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      height: 24 / 20,
                      color: context.colors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    height: 21.84 / 14,
                    color: context.colors.navy,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(50),
              child: Container(
                width: 60,
                height: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: showing
                    ? Image.asset('assets/images/eye-open.png',
                        width: 32, height: 20, color: context.colors.bg)
                    : Image.asset('assets/images/eye-closed.png',
                        width: 30, height: 11, color: context.colors.bg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's map pin: a teardrop outline tilted ~17° so its tip points
/// down and to the right, with a ring at its centre. [tip] is where the
/// point lands in the paint box; by default the bottom centre, which is
/// where a [Marker] with topCenter alignment puts the location.
class _PinPainter extends CustomPainter {
  const _PinPainter({
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
  bool shouldRepaint(_PinPainter old) =>
      old.colour != colour || old.fill != fill || old.tip != tip;
}
