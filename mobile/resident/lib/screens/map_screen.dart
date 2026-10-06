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
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../models/complaint_category.dart';
import '../widgets/brgy_map.dart';
import '../d/d_theme.dart';
import '../d/d_categories.dart';
import '../d/d_ui.dart';
import '../d/flood_watch.dart';
import '../widgets/resident_nav_bar.dart';
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
      ], top: MediaQuery.paddingOf(context).top + 150, bottom: 300);

  // The Google Maps-style sheet (`.sheet`): a grip, the category colour as
  // a 110 px hero with its chip and a close button, then the subject, the
  // ticket and the status, and View report.
  void _openPin(_Pin p) {
    final d = context.d;
    final s = context.s;
    final cat = p.category;
    final col = cat == null ? DColors.brandNavy : categoryColour(cat);
    final st = reportStatusColour(p.status);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: d.card,
      barrierColor: Colors.black.withValues(alpha: .25),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .78),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: d.line, borderRadius: BorderRadius.circular(5))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: DHero(
              colour: col,
              height: 110,
              radius: 18,
              children: [
                if (cat != null) Positioned(left: 12, bottom: 10, child: DHeroChip(cat.label)),
                Positioned(right: 8, top: 8, child: DHeroButton(icon: Icons.close_rounded, size: 30, onTap: () => Navigator.of(ctx).pop())),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(p.subject, style: DType.body(d.ink, size: 19, w: FontWeight.w800).copyWith(height: 1.25)),
                const SizedBox(height: 10),
                Text.rich(TextSpan(children: [
                  if (p.mine) ...[
                    TextSpan(text: p.trackingId, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: d.link)),
                    TextSpan(text: ' \u00B7 ', style: DType.body(d.muted, size: 13)),
                  ],
                  WidgetSpan(alignment: PlaceholderAlignment.middle, child: Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(shape: BoxShape.circle, color: st))),
                  TextSpan(text: s.reportStatusLabel(p.status.wire), style: DType.body(d.ink, size: 13, w: FontWeight.w700)),
                ])),
                const SizedBox(height: 10),
                FutureBuilder<int>(
                  future: FloodHazard.levelAt(p.point.latitude, p.point.longitude),
                  builder: (context, snap) {
                    final lvl = snap.data ?? 0;
                    final flood = !snap.hasData
                        ? '\u2026'
                        : switch (lvl) {
                            3 => context.tr('High flood hazard', 'Mataas na panganib ng baha'),
                            2 => context.tr('Medium flood hazard', 'Katamtamang panganib ng baha'),
                            1 => context.tr('Low flood hazard', 'Mababang panganib ng baha'),
                            _ => context.tr('Outside the flood zones', 'Labas sa mga bahaing lugar'),
                          };
                    return Column(children: [
                      if (p.mine)
                        DRow(icon: Icons.place_outlined, title: (p.locationLabel?.isNotEmpty ?? false) ? p.locationLabel! : 'Barangay 183', sub: 'Barangay 183, Zone 20, Villamor, Pasay City'),
                      if (p.mine && p.createdAt != null) DRow(icon: Icons.calendar_today_outlined, title: s.reportsSubmittedOn('${s.monthFull(p.createdAt!.toLocal().month)} ${p.createdAt!.toLocal().day}, ${p.createdAt!.toLocal().year}')),
                      if (p.mine)
                        DRow(
                          icon: Icons.shield_outlined,
                          title: p.status.index >= ReportStatus.assigned.index && p.status != ReportStatus.rejected && p.status != ReportStatus.cancelled
                              ? context.tr('A tanod is assigned', 'May naka-assign na tanod')
                              : context.tr('No tanod assigned yet', 'Wala pang tanod'),
                          sub: p.status.index >= ReportStatus.assigned.index && p.status != ReportStatus.rejected && p.status != ReportStatus.cancelled
                              ? context.tr('Assigned to your report', 'Naka-assign sa iyong report')
                              : context.tr('The barangay is reviewing it', 'Sinusuri ng barangay'),
                        ),
                      DRow(icon: Icons.water_rounded, title: flood, sub: 'Project NOAH 100-year flood map'),
                    ]);
                  },
                ),
                if (p.mine) ...[
                  const SizedBox(height: 10),
                  Builder(builder: (context) {
                    final steps = reportSteps(context, p.status, office: p.referredTo);
                    return DStepList(
                      labels: steps.labels,
                      on: steps.on,
                      colour: col,
                      subs: p.createdAt == null ? const {} : {0: '${s.monthFull(p.createdAt!.toLocal().month)} ${p.createdAt!.toLocal().day}, ${p.createdAt!.toLocal().year}'},
                    );
                  }),
                  const SizedBox(height: 4),
                  DButton(context.tr('Open this report', 'Buksan ang report'), expand: true, onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushNamed('/report', arguments: p.id);
                  }),
                ] else ...[
                  const SizedBox(height: 4),
                  Text(s.mapPublishedNote, style: DType.body(d.muted, size: 13)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // Branch D, 1:1 with the preview's Map: the real map edge to edge; a
  // title card with the live rain; the Project NOAH chip; zoom buttons;
  // and the eye card at the bottom with its orange button.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final pins = _pins ?? const <_Pin>[];
    final fr = _flood;
    final fcol = fr == null || !fr.online ? d.muted : const [Color(0xFF22C55E), Color(0xFFEAB308), Color(0xFFF97316), Color(0xFFDC2626)][fr.level];
    Widget dock(Widget child, VoidCallback onTap) => Material(
          color: d.card,
          elevation: 3,
          shadowColor: Colors.black38,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: d.line)),
          child: InkWell(borderRadius: BorderRadius.circular(13), onTap: onTap, child: SizedBox(width: 42, height: 42, child: Center(child: child))),
        );
    Widget dockText(String t) => Text(t, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: d.ink));
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
            attributionBottom: 96,
            pins: [
              if (_showReports)
                for (final p in pins)
                  BrgyMapPin(
                    id: p.id,
                    point: p.point,
                    muted: !p.mine,
                    glyph: categoryGlyph(p.category ?? ComplaintCategory.other),
                    // as on the portal's Spatial Distribution: the pin is the
                    // complaint-type colour; the status is the corner dot
                    bodyColour: categoryColour(p.category ?? ComplaintCategory.other),
                    dotColour: reportStatusColour(p.status),
                    pulse: p.mine && (p.status == ReportStatus.inProgress || p.status == ReportStatus.assigned || p.status == ReportStatus.offlineInvestigation),
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
          Positioned.fill(child: Container(color: Colors.black.withValues(alpha: .2), alignment: Alignment.center, child: const CircularProgressIndicator(color: Colors.white))),
        // the title card and the NOAH chip
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 6))]),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.mapTitle, style: DType.body(d.ink, size: 16, w: FontWeight.w800).copyWith(height: 1.2)),
                    Text(context.tr('Your reports and flood zones', 'Ang iyong reports at bahaing lugar'), style: DType.body(d.muted, size: 12).copyWith(height: 1.25)),
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
            const SizedBox(height: 8),
            _NoahChip(on: _hazards, label: '${s.mapHazardToggle} · Project NOAH', onTap: () => setState(() => _hazards = !_hazards)),
          ]),
        ),
        // the zoom buttons, stacked on the eye card so it never covers them
        Positioned(
          left: 12,
          right: 12,
          bottom: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Column(children: [
            dock(dockText('+'), () => _map.zoomBy(1)),
            const SizedBox(height: 8),
            dock(dockText('−'), () => _map.zoomBy(-1)),
            const SizedBox(height: 8),
            dock(dockText('◎'), () => _map.move(brgyCentre, 16)),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: d.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: d.line),
              boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_showReports ? s.mapReportsSpotted : s.mapWantToSeeReports, style: DType.body(d.ink, size: 16, w: FontWeight.w800).copyWith(height: 1.2)),
                  const SizedBox(height: 2),
                  Text(_showReports ? s.mapCardBodyShowing : s.mapCardBodyHidden, style: DType.body(d.muted, size: 12.5).copyWith(height: 1.35)),
                  if (_showReports && pins.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // two even columns, so the dots line up down the card
                    LayoutBuilder(builder: (context, box) => Wrap(spacing: 10, runSpacing: 4, children: [
                      for (final c in {for (final p in pins) p.category ?? ComplaintCategory.other})
                        SizedBox(
                          width: (box.maxWidth - 10) / 2,
                          child: Row(children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: categoryColour(c))),
                            const SizedBox(width: 5),
                            Expanded(child: Text(c.label, maxLines: 2, style: DType.body(d.muted, size: 11.5))),
                          ]),
                        ),
                    ])),
                  ],
                  if (_hazards) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 10, runSpacing: 4, children: [
                      _swatch(const Color(0xFFFACC15), s.mapHazardLow, d),
                      _swatch(const Color(0xFFF97316), s.mapHazardMedium, d),
                      _swatch(const Color(0xFFDC2626), s.mapHazardHigh, d),
                      Text(s.mapHazardSource, style: DType.body(d.muted, size: 11.5)),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: 12),
              GestureDetector(
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
            ]),
          ),
          ]),
        ),
      ]),
    );
  }

  Widget _swatch(Color c, String label, DColors d) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: DType.body(d.muted, size: 11.5)),
      ]);
}

/// `.msw .noah`, 1:1 with the preview: a 32 px chip on #333438 with a
/// white checkbox; ticked, the blue wave rises through it (translateY 80%
/// to 0, .6 s, cubic-bezier(.4,1.3,.5,1)); unticked it is desaturated to
/// .55 like the preview's `filter: saturate(.55)`.
class _NoahChip extends StatelessWidget {
  const _NoahChip({required this.on, required this.label, required this.onTap});

  final bool on;
  final String label;
  final VoidCallback onTap;

  static const _sat = .55;
  static const _desat = ColorFilter.matrix(<double>[
    0.213 + 0.787 * _sat, 0.715 - 0.715 * _sat, 0.072 - 0.072 * _sat, 0, 0,
    0.213 - 0.213 * _sat, 0.715 + 0.285 * _sat, 0.072 - 0.072 * _sat, 0, 0,
    0.213 - 0.213 * _sat, 0.715 - 0.715 * _sat, 0.072 + 0.928 * _sat, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ColorFiltered(
          colorFilter: on ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : _desat,
          child: Container(
            height: 32,
            padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))]),
            clipBehavior: Clip.antiAlias,
            child: Stack(alignment: Alignment.centerLeft, children: [
              Positioned.fill(
                child: Stack(children: [
                  const Positioned.fill(child: ColoredBox(color: Color(0xFF333438))),
                  Positioned.fill(
                    child: AnimatedSlide(
                      offset: Offset(0, on ? 0 : .8),
                      duration: const Duration(milliseconds: 600),
                      curve: const Cubic(.4, 1.3, .5, 1),
                      // 200% wide like the preview's svg: an infinite
                      // OverflowBox gives the painter no size, so the wave
                      // never drew on the phone.
                      child: LayoutBuilder(
                        builder: (_, c) => OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: c.maxWidth * 2,
                          maxWidth: c.maxWidth * 2,
                          child: const SizedBox.expand(child: CustomPaint(painter: _WavePainter())),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: on ? Colors.white : null, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white.withValues(alpha: .8), width: 2)),
                ),
                const SizedBox(width: 7),
                Text(label, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white)),
              ]),
            ]),
          ),
        ),
      );
}

/// The preview's wave: viewBox 400x44 stretched to fill, #1A73E8 below the
/// crest and a 2.5 white line along it.
class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 400, size.height / 44);
    final crest = Path()
      ..moveTo(0, 6)
      ..cubicTo(40, 1, 60, 1, 100, 6)
      ..cubicTo(140, 11, 160, 11, 200, 6)
      ..cubicTo(240, 1, 260, 1, 300, 6)
      ..cubicTo(340, 11, 360, 11, 400, 6);
    final fill = Path.from(crest)
      ..lineTo(400, 44)
      ..lineTo(0, 44)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0xFF1A73E8));
    canvas.drawPath(crest, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}
