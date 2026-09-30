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
import 'package:latlong2/latlong.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../models/complaint_category.dart';
import '../theme.dart';
import '../widgets/brgy_map.dart';
import '../widgets/figma_ui.dart';
import '../widgets/resident_nav_bar.dart';
import 'reports_screen.dart' show ReportStatus;

class _Pin {
  const _Pin({
    required this.id,
    required this.point,
    required this.trackingId,
    required this.subject,
    required this.status,
    this.mine = true,
  });

  final String id;
  final LatLng point;
  final String trackingId;

  /// For someone else's published incident, its category.
  final String subject;
  final ReportStatus status;

  /// False for an incident the barangay published (0073): category and
  /// status only, no link to the report.
  final bool mine;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // The barangay's centre, bounds, boundary outline and fog now live in
  // widgets/brgy_map.dart, shared with the other maps.
  final _map = BrgyMapController();

  bool _showReports = false;
  bool _hazards = false;
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

      // The incidents the barangay chose to publish (use case "Monitor
      // Real-Time Map"): category, status and place only.
      List<dynamic> published = const [];
      try {
        published = await client.rpc('public_incidents') as List<dynamic>;
      } catch (_) {}

      final pins = <_Pin>[];
      final ownIds = {for (final r in rows) r['id'] as String};
      for (final r in published.cast<Map<String, dynamic>>()) {
        final lat = (r['latitude'] as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble();
        final id = r['id'] as String;
        if (lat == null || lng == null || ownIds.contains(id)) continue;
        pins.add(_Pin(
          id: 'pub:$id',
          point: LatLng(lat, lng),
          trackingId: '',
          subject: ComplaintCategory.parse(r['category'] as String?).label,
          status: ReportStatus.parse(r['status'] as String?),
          mine: false,
        ));
      }
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
      final mine = pins.where((p) => p.mine).toList();
      if (mine.isNotEmpty) _fitTo(mine);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pins = const [];
        _loading = false;
      });
    }
  }

  // Only the pins the map can pan to: one filed from outside the
  // barangay would drag the frame off the grid, and the camera cannot
  // follow it there anyway.
  void _fitTo(List<_Pin> pins) => _map.fit([
        for (final p in pins)
          if (withinBrgyBounds(p.point)) p.point,
      ]);

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
              p.mine
                  ? '(${p.trackingId} - ${context.s.reportStatusLabel(p.status.wire)}) '
                      '${p.subject}'
                  : '${p.subject} - ${context.s.reportStatusLabel(p.status.wire)}',
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
                color: context.colors.navy,
              ),
            ),
            const SizedBox(height: 18),
            if (p.mine)
              FigmaPill(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/report', arguments: p.id);
                },
                child: Text(context.s.mapViewReport),
              )
            else
              Text(context.s.mapPublishedNote,
                  style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontSize: 13,
                      color: context.colors.hint)),
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
                    // In front of the map, which would otherwise cover it.
                    foregroundDecoration: BoxDecoration(
                      border: Border.all(color: context.colors.navy),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Stack(
                      children: [
                        // Pinned to the residential grid, the outside of
                        // 183 dimmed rather than hidden so a resident can
                        // still see the bordering streets. The pins are
                        // the design's tilted pin, red where the status
                        // label is.
                        BrgyMap(
                          controller: _map,
                          boundary: true,
                          hazards: _hazards,
                          restrictToBarangay: true,
                          attributionBottom: 12,
                          cornerRadius: 25,
                          cornerColour: context.colors.bg,
                          pins: [
                            if (_showReports)
                              for (final p in pins)
                                BrgyMapPin(
                                  id: p.id,
                                  point: p.point,
                                  muted: !p.mine,
                                  alert: p.mine &&
                                      p.status.labelColour(context) !=
                                          context.colors.bg,
                                ),
                          ],
                          onPinTap: (id) {
                            for (final p in pins) {
                              if (p.id == id) return _openPin(p);
                            }
                          },
                        ),

                        if (_loading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.2),
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                                color: Colors.white),
                          ),

                        // Project NOAH's flood zones on demand (branch B),
                        // with their three levels spelled out.
                        Positioned(
                          top: 12,
                          right: 12,
                          child: _HazardChip(
                            on: _hazards,
                            onTap: () => setState(() => _hazards = !_hazards),
                          ),
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
                        painter: FigmaPinPainter(
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

/// Flood-hazard toggle on the map, and its legend while on.
class _HazardChip extends StatelessWidget {
  const _HazardChip({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = context.colors;
    final text = TextStyle(
        fontFamily: 'Urbanist', fontSize: 11.5, fontWeight: FontWeight.w600, color: c.navy);
    Widget swatch(Color colour, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text(label, style: text),
          ]),
        );
    return Material(
      color: c.field,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(on ? Icons.water_drop : Icons.water_drop_outlined,
                    size: 16, color: const Color(0xFF0891B2)),
                const SizedBox(width: 5),
                Text(s.mapHazardToggle,
                    style: text.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
              if (on) ...[
                const SizedBox(height: 5),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  swatch(const Color(0xFFFACC15), s.mapHazardLow),
                  swatch(const Color(0xFFF97316), s.mapHazardMedium),
                  swatch(const Color(0xFFDC2626), s.mapHazardHigh),
                ]),
                const SizedBox(height: 3),
                Text(s.mapHazardSource,
                    style: text.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: c.muted)),
              ],
            ],
          ),
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
