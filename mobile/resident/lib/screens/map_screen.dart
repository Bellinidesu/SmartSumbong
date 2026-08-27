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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '(${p.trackingId} - ${context.s.reportStatusLabel(p.status.wire)}) '
              '${p.subject}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
                color: context.colors.navy,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/report', arguments: p.id);
                },
                child: Text(context.s.mapViewReport),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;
    final pins = _pins ?? const <_Pin>[];

    return Scaffold(
      bottomNavigationBar: const ResidentNavBar(current: ResidentTab.map),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(s.mapTitle,
                style: t.headlineLarge?.copyWith(fontSize: 28)),
            const SizedBox(height: 16),

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
                                      child: GestureDetector(
                                        onTap: () => _openPin(p),
                                        child: Icon(
                                          Icons.location_on,
                                          size: 38,
                                          color: p.status.labelColour(
                                                      context) ==
                                                  context.colors.bg
                                              ? context.colors.navy
                                              : const Color(0xFFFF4949),
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

                        // The drag affordance from the design, bottom
                        // left of the map frame.
                        const Positioned(
                          left: 12,
                          bottom: 12,
                          child: Icon(Icons.open_with,
                              color: Color(0xFFFF9800), size: 26),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 16),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _MapCard(showing: _showReports, onToggle: _toggle),

                  // The orange pin straddling the card's top-left corner
                  // in the design. Decorative only — the card's left
                  // padding is already cut to make room for it.
                  const Positioned(
                    left: -12,
                    top: -22,
                    child: IgnorePointer(
                      child: Icon(
                        Icons.location_on_outlined,
                        size: 44,
                        color: Color(0xFFFF9800),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(34, 15, 18, 15),
      decoration: BoxDecoration(
        color: context.colors.field,
        border: Border.all(color: context.colors.navy, width: 2),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showing ? s.mapReportsSpotted : s.mapWantToSeeReports,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: context.colors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                      fontSize: 14, height: 1.25, color: context.colors.navy),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 60,
              height: 45,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                showing ? Icons.visibility : Icons.visibility_off,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
