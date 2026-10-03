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
import '../d/d_theme.dart';
import '../d/d_ui.dart';
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
    final d = context.d;
    final s = context.s;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: d.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: DColors.orange.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
              child: Text(s.reportStatusLabel(p.status.wire),
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFFB26A00))),
            ),
            const SizedBox(width: 8),
            if (p.mine) Text(p.trackingId, style: DType.mono(d.link, size: 12.5)),
          ]),
          const SizedBox(height: 8),
          Text(p.subject, style: DType.h2(d.ink)),
          const SizedBox(height: 14),
          if (p.mine)
            DButton(s.mapViewReport, expand: true, onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/report', arguments: p.id);
            })
          else
            Text(s.mapPublishedNote, style: DType.body(d.muted, size: 13)),
        ]),
      ),
    );
  }

  // Branch D (go list: the Map): the real map of Barangay 183 edge to
  // edge, in the app's day or night colours; a floating title card with
  // the two switches — your reports (the eye) and Project NOAH's flood
  // hazard — and a sheet like Google Maps' when a pin is tapped.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final pins = _pins ?? const <_Pin>[];
    return Scaffold(
      backgroundColor: d.bg,
      bottomNavigationBar: const ResidentNavBar(current: ResidentTab.map),
      body: Stack(children: [
        Positioned.fill(
          child: BrgyMap(
            controller: _map,
            boundary: true,
            hazards: _hazards,
            restrictToBarangay: true,
            attributionBottom: 12,
            pins: [
              if (_showReports)
                for (final p in pins)
                  BrgyMapPin(
                    id: p.id,
                    point: p.point,
                    muted: !p.mine,
                    alert: p.mine && p.status.labelColour(context) != context.colors.bg,
                  ),
            ],
            onPinTap: (id) {
              for (final p in pins) {
                if (p.id == id) return _openPin(p);
              }
            },
          ),
        ),
        if (_loading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: .2),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: Colors.white),
            ),
          ),
        Positioned(
          left: 14,
          right: 14,
          top: MediaQuery.paddingOf(context).top + 10,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: d.card.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: d.line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .16), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.mapTitle, style: DType.h3(d.accent).copyWith(fontSize: 18)),
              Text(_showReports ? s.mapCardBodyShowing : s.mapCardBodyHidden, style: DType.body(d.muted, size: 12.5)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _Switch(
                    on: _showReports,
                    icon: _showReports ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    label: context.tr('My reports', 'Aking mga ulat'),
                    colour: DColors.orange,
                    onTap: _toggle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Switch(
                    on: _hazards,
                    icon: Icons.water_rounded,
                    label: s.mapHazardToggle,
                    colour: const Color(0xFF0891B2),
                    onTap: () => setState(() => _hazards = !_hazards),
                  ),
                ),
              ]),
              if (_hazards) ...[
                const SizedBox(height: 10),
                Row(children: [
                  _swatch(const Color(0xFFFACC15), s.mapHazardLow, d),
                  _swatch(const Color(0xFFF97316), s.mapHazardMedium, d),
                  _swatch(const Color(0xFFDC2626), s.mapHazardHigh, d),
                  const Spacer(),
                  Text(s.mapHazardSource, style: DType.body(d.muted, size: 10.5)),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _swatch(Color c, String label, DColors d) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: c.withValues(alpha: .85), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(label, style: DType.body(d.ink2, size: 11.5, w: FontWeight.w700)),
        ]),
      );
}

/// A switch chip: an icon, a label and a small sliding toggle.
class _Switch extends StatelessWidget {
  const _Switch({required this.on, required this.icon, required this.label, required this.colour, required this.onTap});

  final bool on;
  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Material(
      color: on ? colour.withValues(alpha: .14) : d.field,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: on ? colour.withValues(alpha: .6) : d.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            Icon(icon, size: 18, color: on ? colour : d.muted),
            const SizedBox(width: 7),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 13, w: FontWeight.w800))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 30,
              height: 18,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: on ? colour : d.line),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(width: 14, height: 14, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }
}
