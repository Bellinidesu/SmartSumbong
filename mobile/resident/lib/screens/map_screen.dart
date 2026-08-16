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

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/resident_nav_bar.dart';
import 'reports_screen.dart' show ReportStatus;

/// Barangay 183, Zone 20, Villamor, Pasay City — from OSM relation
/// 2988704. The same constant as the submit screen; if the barangay
/// boundary is ever corrected, both move together.
const _barangayCentre = LatLng(14.51646, 121.01621);

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
      backgroundColor: Tokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '(${p.trackingId} - ${p.status.label}) ${p.subject}',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
                color: Tokens.navy,
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
                child: const Text('View report'),
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
    final pins = _pins ?? const <_Pin>[];

    return Scaffold(
      bottomNavigationBar: const ResidentNavBar(current: ResidentTab.map),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text('Barangay 183 Map',
                style: t.headlineLarge?.copyWith(fontSize: 28)),
            const SizedBox(height: 16),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Tokens.navy),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _map,
                          options: const MapOptions(
                            initialCenter: _barangayCentre,
                            initialZoom: 15,
                            interactionOptions: InteractionOptions(
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
                                          color: p.status.labelColour ==
                                                  Tokens.bg
                                              ? Tokens.navy
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
    // reproduced as drawn because the copy was signed off as-is.
    final String body = showing
        ? 'Just click the \u2018eye\u2019 again and you will back to the '
            'normal map. You can also move the map around.'
        : 'Just click the \u2018eye\u2019 and you will see the locations '
            'of your reports. You can also move the map around.';

    return Container(
      padding: const EdgeInsets.fromLTRB(34, 15, 18, 15),
      decoration: BoxDecoration(
        color: Tokens.field,
        border: Border.all(color: Tokens.navy, width: 2),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showing ? 'Reports spotted!' : 'Want to see your reports?',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: Tokens.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                      fontSize: 14, height: 1.25, color: Tokens.navy),
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
