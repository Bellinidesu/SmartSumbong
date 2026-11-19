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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../models/complaint_category.dart';
import '../widgets/brgy_map.dart';
import '../widgets/brgy_map_card.dart';
import '../widgets/map_glyphs.dart';
import '../d/d_theme.dart';
import '../d/d_categories.dart';
import '../d/d_ui.dart';
import '../d/flood_watch.dart';
import '../widgets/resident_nav_bar.dart';
import '../models/barangay_profile.dart';
import 'reports_screen.dart' show ReportStatus, reportStatusColour, reportSteps;

class _Pin {
  const _Pin({
    required this.id,
    required this.point,
    required this.trackingId,
    required this.subject,
    required this.status,
    this.category,
    this.createdAt,
    this.locationLabel,
    this.referredTo,
    this.mine = true,
  });

  final String id;
  final LatLng point;
  final String trackingId;

  /// For someone else's published incident, its category.
  final String subject;
  final ReportStatus status;
  final ComplaintCategory? category;
  final DateTime? createdAt;
  final String? locationLabel;
  final String? referredTo;

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

  FloodReading? _flood;

  @override
  void initState() {
    super.initState();
    FloodReading.read().then((r) {
      if (mounted) setState(() => _flood = r);
    });
  }

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
          .select('id, tracking_id, subject, status, category, created_at, location_label, referred_to, latitude, longitude')
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
          category: ComplaintCategory.parse(r['category'] as String?),
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
          category: ComplaintCategory.parse(r['category'] as String?),
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
          locationLabel: r['location_label'] as String?,
          referredTo: r['referred_to'] as String?,
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
      ], top: MediaQuery.paddingOf(context).top + 150, bottom: _cardHeight + 60);

  /// The pin whose card is open, drawn larger on the map.
  String? _selected;

  /// The eye card's height, so the map's controls sit just above it.
  double _cardHeight = 96;
  final _cardKey = GlobalKey();

  // The portal's case sheet (spatial.js showDetail), rising from the
  // bottom: the hero in the complaint type's colour, the subject, the
  // ticket and status, the rows, Progress, and Open this report.
  Future<void> _openPin(_Pin p) async {
    final s = context.s;
    final cat = p.category ?? ComplaintCategory.other;
    final skin = BrgyMapSkin.of(context);
    final assigned = p.status.index >= ReportStatus.assigned.index && p.status != ReportStatus.rejected && p.status != ReportStatus.cancelled;
    final steps = reportSteps(context, p.status, office: p.referredTo);
    final created = p.createdAt?.toLocal();
    setState(() => _selected = p.id);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: skin.surface(3),
      barrierColor: Colors.black.withValues(alpha: .25),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      builder: (ctx) => SafeArea(
        top: false,
        child: BrgyMapCaseCard(
          colour: categoryColour(cat),
          glyph: cat.icon,
          category: context.tr(cat.label, cat.labelFil),
          title: p.subject,
          ticket: p.mine ? p.trackingId : null,
          statusLabel: s.reportStatusLabel(p.status.wire),
          statusColour: reportStatusColour(p.status),
          rows: [
            if (p.mine)
              BrgyMapCardRow(
                glyph: MapIcons.pin,
                title: (p.locationLabel?.isNotEmpty ?? false) ? p.locationLabel! : BarangayProfile.name,
                sub: '${BarangayProfile.name}, ${BarangayProfile.place}',
              ),
            if (p.mine && created != null)
              BrgyMapCardRow(glyph: MapIcons.calendar, title: s.reportsSubmittedOn('${s.monthFull(created.month)} ${created.day}, ${created.year}')),
            if (p.mine)
              BrgyMapCardRow(
                glyph: MapIcons.handler,
                title: assigned ? context.tr('A tanod is assigned', 'May naka-assign na tanod') : context.tr('No tanod assigned yet', 'Wala pang tanod'),
                sub: assigned ? context.tr('Assigned to your report', 'Naka-assign sa iyong report') : context.tr('The barangay is reviewing it', 'Sinusuri ng barangay'),
              ),
          ],
          steps: p.mine ? steps.labels : const [],
          stepsOn: steps.on,
          note: p.mine ? null : s.mapPublishedNote,
          action: p.mine ? context.tr('Open this report', 'Buksan ang report') : null,
          onAction: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pushNamed('/report', arguments: p.id);
          },
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    if (mounted) setState(() => _selected = null);
  }

  void _measureCard() {
    if (!mounted) return;
    final h = _cardKey.currentContext?.size?.height;
    if (h != null && (h - _cardHeight).abs() > .5) setState(() => _cardHeight = h);
  }

  // The map edge to edge in the portal's style (widgets/brgy_map.dart,
  // BrgyMapUse.browse): its dock, zoom pair, Layers tile, legend and scale
  // over it; the title card with the live rain at the top; and the eye
  // card at the bottom with its orange button.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final skin = BrgyMapSkin.of(context);
    final pins = _pins ?? const <_Pin>[];
    final shown = _showReports ? pins : const <_Pin>[];
    final fr = _flood;
    final fcol = fr == null || !fr.online ? d.muted : const [Color(0xFF22C55E), Color(0xFFEAB308), Color(0xFFF97316), Color(0xFFDC2626)][fr.level];
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureCard());
    final counts = <ComplaintCategory, int>{};
    for (final p in shown) {
      final c = p.category ?? ComplaintCategory.other;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final kinds = {...ComplaintCategory.values, ...counts.keys};
    return Scaffold(
      backgroundColor: d.bg,
      bottomNavigationBar: const ResidentNavBar(current: ResidentTab.map),
      body: Stack(children: [
        Positioned.fill(
          child: BrgyMap(
            use: BrgyMapUse.browse,
            controller: _map,
            controlsPadding: EdgeInsets.only(bottom: _cardHeight + 14),
            selectedPinId: _selected,
            pins: [
              for (final p in shown)
                BrgyMapPin(
                  id: p.id,
                  point: p.point,
                  muted: !p.mine,
                  // as on the portal's Spatial Distribution: the pin is the
                  // complaint type's colour and symbol; the status is the
                  // dot on its shoulder
                  colour: categoryColour(p.category ?? ComplaintCategory.other),
                  glyph: (p.category ?? ComplaintCategory.other).icon,
                  dot: reportStatusColour(p.status),
                  pulse: p.mine && (p.status == ReportStatus.inProgress || p.status == ReportStatus.assigned || p.status == ReportStatus.offlineInvestigation),
                ),
            ],
            legend: [
              for (final c in kinds)
                BrgyMapLegendEntry(label: context.tr(c.label, c.labelFil), colour: categoryColour(c), glyph: c.icon, count: counts[c] ?? 0),
            ],
            onPinTap: (id) {
              for (final p in pins) {
                if (p.id == id) {
                  unawaited(_openPin(p));
                  return;
                }
              }
            },
          ),
        ),
        if (_loading)
          Positioned.fill(child: Container(color: Colors.black.withValues(alpha: .2), alignment: Alignment.center, child: const CircularProgressIndicator(color: Colors.white))),
        // the title card
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(color: skin.surface(2), borderRadius: BorderRadius.circular(16), boxShadow: skin.elevation(2)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.mapTitle, style: DType.body(d.ink, size: 16, w: FontWeight.w800).copyWith(height: 1.2)),
                  Text(context.tr('Your reports on the barangay map', 'Ang iyong reports sa mapa ng barangay'),
                      style: DType.body(d.muted, size: 12).copyWith(height: 1.25)),
                ]),
              ),
              if (fr != null && fr.online)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: fcol, boxShadow: [BoxShadow(color: fcol.withValues(alpha: .2), spreadRadius: 5)])),
                    const SizedBox(width: 12),
                    Text('${fr.mm!.toStringAsFixed(1)} mm/h', style: DType.body(d.ink, size: 12.5, w: FontWeight.w800)),
                  ]),
                ),
            ]),
          ),
        ),
        // the eye card
        Positioned(
          left: 12,
          right: 12,
          bottom: 14,
          child: Container(
            key: _cardKey,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: skin.surface(2), borderRadius: BorderRadius.circular(18), boxShadow: skin.elevation(2)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_showReports ? s.mapReportsSpotted : s.mapWantToSeeReports, style: DType.body(d.ink, size: 16, w: FontWeight.w800).copyWith(height: 1.2)),
                  const SizedBox(height: 2),
                  Text(_showReports ? s.mapCardBodyShowing : s.mapCardBodyHidden, style: DType.body(d.muted, size: 12.5).copyWith(height: 1.35)),
                ]),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                toggled: _showReports,
                label: context.tr('Show my reports', 'Ipakita ang aking reports'),
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _showReports ? d.btn : DColors.orange,
                      boxShadow: [BoxShadow(color: const Color(0xFFFF9800).withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 6))],
                    ),
                    child: Icon(_showReports ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
