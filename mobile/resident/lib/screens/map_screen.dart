// SmartSumbong — Barangay 183 Map (the resident's Map tab).
//
// Rebuilt 20 Nov 2026 from the Map tab artifact (Ace approved it on 19 Nov), the way a phone map works:
//
//  * pinch and double-tap to zoom, no +/- buttons; one round "Frame 183" button puts the map back on the barangay's
//    residential centre (brgyCentre, zoom 16: never the OSM centroid over the runway, never a fit to the pins);
//  * Layers, bottom left, opens a bottom sheet of tiles that are on or off: My reports (on), Barangay notices, Places,
//    Dim outside 183 and Rain watch. The eye card is gone; the top box (the title, the line under it and the live rain
//    reading) is exactly what it was;
//  * a row of chips under the top box is the legend and the filter at once: My reports, Notices, then a chip per
//    category with its colour dot and its count. Choosing one narrows what is drawn;
//  * a pin of the resident's own opens a small card at the foot (handle, the category's header with the status pill,
//    "3 concerns · 1 resolved", the track, Open this report). The map pans so the pin stays clear above the card. The
//    handle, or a drag up, expands it into the portal's case card; a tap on the card, or its button, opens the report.
//
// The pins are the resident's own reports only (reports_resident_read), and the incidents the barangay published
// (public_incidents, 0073: category and status, never a person or a word). A public map of every complaint would tell
// anyone which houses reported their neighbours, which the anonymous option exists to prevent.
//
// NOT BUILT HERE. The barangay's notices with a headline, a message, a push and a megaphone badge are a later feature that
// needs the database (the frames M5 to M7 say "Later"). "Notices" on this tab is what the app already read: the incidents
// the barangay published, drawn as before (a soft disc ringed in the category's colour) with the card that says so.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../d/flood_watch.dart';
import '../i18n.dart';
import '../models/barangay_profile.dart';
import '../models/complaint_category.dart';
import '../widgets/brgy_map.dart';
import '../widgets/map_tab_ui.dart';
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

  ComplaintCategory get cat => category ?? ComplaintCategory.other;
}

/// Where the chips of the first group (the layers a pin comes from) narrow to.
enum _Source { mine, notices }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // The barangay's centre, bounds, boundary outline and fog live in widgets/brgy_map.dart, shared with the other maps.
  final _map = BrgyMapController();

  FloodReading? _flood;

  // what was read
  List<_Pin>? _pins;
  bool _loading = true;
  bool _failed = false;
  Map<String, ({int total, int resolved})> _concerns = const {};
  Map<String, DateTime> _updated = const {};

  // the Layers sheet: My reports is on from the first look; Dim outside starts off, as the artifact draws it
  bool _lMine = true;
  bool _lNotices = true;
  bool _lPlaces = true;
  bool _lDim = false;
  bool _lRain = true;

  // the chips: where a pin comes from, and which category
  _Source? _source;
  String? _category;

  // the card
  String? _selected;
  bool _expanded = false;
  bool _needReveal = false;

  // measured after a frame: what the card and the top block cover
  final _slotKey = GlobalKey();
  final _headKey = GlobalKey();
  double _slotH = 0;
  double _headBottom = 0;
  double _mapH = 0;

  @override
  void initState() {
    super.initState();
    FloodReading.read().then((r) {
      if (mounted) setState(() => _flood = r);
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _pins = const [];
          _loading = false;
        });
      }
      return;
    }
    try {
      final rows = await client
          .from('reports')
          .select('id, tracking_id, subject, status, category, created_at, location_label, referred_to, latitude, longitude')
          .eq('resident_id', uid)
          .isFilter('deleted_at', null);

      // The incidents the barangay chose to publish (use case "Monitor Real-Time Map"): category, status and place only.
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
      unawaited(_loadExtras([for (final p in pins) if (p.mine) p.id]));
      // The map opens, and the Frame button returns, on the portal's residential centre at zoom 16 (Ace, 20 Nov: never
      // a fit to the pins, never the OSM centroid): the barangay is the frame, whatever the resident filed.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pins = const [];
        _loading = false;
        _failed = true;
      });
    }
  }

  /// What the card adds to a report: how many concerns and how many are resolved (report_concerns, which a resident may
  /// read), and when it last changed (status_logs). Each is optional: a failure here never blanks the map.
  Future<void> _loadExtras(List<String> ids) async {
    if (ids.isEmpty) return;
    final client = Supabase.instance.client;
    try {
      final rows = await client.from('report_concerns').select('report_id, status').inFilter('report_id', ids);
      final m = <String, ({int total, int resolved})>{};
      for (final r in rows) {
        final id = r['report_id'] as String?;
        if (id == null) continue;
        final was = m[id] ?? (total: 0, resolved: 0);
        m[id] = (total: was.total + 1, resolved: was.resolved + (r['status'] == 'resolved' ? 1 : 0));
      }
      if (mounted) setState(() => _concerns = m);
    } catch (_) {}
    try {
      final rows = await client.from('status_logs').select('report_id, created_at').inFilter('report_id', ids).order('created_at', ascending: false);
      final m = <String, DateTime>{};
      for (final r in rows) {
        final id = r['report_id'] as String?;
        final at = DateTime.tryParse(r['created_at'] as String? ?? '');
        if (id != null && at != null && !m.containsKey(id)) m[id] = at;
      }
      if (mounted) setState(() => _updated = m);
    } catch (_) {}
  }

  // ---------- what is shown --------------------------------------------

  bool _layerOn(_Pin p) => p.mine ? _lMine : _lNotices;

  /// The pins of the layers that are on: what the chips count.
  Iterable<_Pin> get _inLayers => (_pins ?? const <_Pin>[]).where(_layerOn);

  /// The pins drawn: the layers, narrowed by the chips.
  List<_Pin> get _visible => [
        for (final p in _inLayers)
          if ((_source == null || (_source == _Source.mine) == p.mine) && (_category == null || p.cat.wire == _category)) p,
      ];

  bool get _filtering => _source != null || _category != null;

  _Pin? get _selectedPin {
    for (final p in _visible) {
      if (p.id == _selected) return p;
    }
    return null;
  }

  void _tapChip(String id) {
    setState(() {
      if (id == 'mine' || id == 'notices') {
        final s = id == 'mine' ? _Source.mine : _Source.notices;
        _source = _source == s ? null : s;
      } else {
        _category = _category == id ? null : id;
      }
      _dropHiddenSelection();
    });
  }

  void _clearFilter() => setState(() {
        _source = null;
        _category = null;
      });

  /// A pin that is no longer drawn closes its card.
  void _dropHiddenSelection() {
    if (_selected != null && _selectedPin == null) {
      _selected = null;
      _expanded = false;
    }
  }

  bool _isOn(String id) => switch (id) {
        'mine' => _lMine,
        'notices' => _lNotices,
        'places' => _lPlaces,
        'dim' => _lDim,
        _ => _lRain,
      };

  void _toggleLayer(String id) {
    setState(() {
      switch (id) {
        case 'mine':
          _lMine = !_lMine;
          if (!_lMine && _source == _Source.mine) _source = null;
        case 'notices':
          _lNotices = !_lNotices;
          if (!_lNotices && _source == _Source.notices) _source = null;
        case 'places':
          _lPlaces = !_lPlaces;
        case 'dim':
          _lDim = !_lDim;
        default:
          _lRain = !_lRain;
      }
      _dropHiddenSelection();
    });
  }

  Future<void> _openLayers() {
    final s = context.tr;
    return showMapLayersSheet(
      context,
      tiles: [
        MapLayerTile(id: 'mine', name: s('My reports', 'Aking reports'), glyph: MapTabIcons.pin),
        MapLayerTile(id: 'notices', name: s('Barangay notices', 'Mga paunawa ng barangay'), glyph: MapTabIcons.megaphone),
        MapLayerTile(id: 'places', name: s('Places', 'Mga lugar'), glyph: MapTabIcons.hall),
        MapLayerTile(id: 'dim', name: s('Dim outside 183', 'Dimmin ang labas ng 183'), contrast: true),
        MapLayerTile(id: 'rain', name: s('Rain watch', 'Bantay-ulan'), glyph: MapTabIcons.map),
      ],
      isOn: _isOn,
      toggle: _toggleLayer,
    );
  }

  // ---------- the card ---------------------------------------------------

  void _select(String id) {
    setState(() {
      _selected = id;
      _expanded = false;
      _needReveal = true;
    });
  }

  void _closeCard() {
    if (_selected == null) return;
    setState(() {
      _selected = null;
      _expanded = false;
      _needReveal = false;
    });
  }

  void _expand() => setState(() {
        _expanded = true;
        _needReveal = true;
      });

  void _collapse() => setState(() {
        _expanded = false;
        _needReveal = true;
      });

  /// The big card's top, as the artifact draws it: 300 of 844 down the screen.
  double _bigTop(double screenH) => screenH * 300 / 844;

  void _measure() {
    if (!mounted) return;
    var changed = false;
    final slot = _slotKey.currentContext?.size?.height ?? 0;
    if ((slot - _slotH).abs() > .5) {
      _slotH = slot;
      changed = true;
    }
    final head = _headKey.currentContext?.findRenderObject();
    if (head is RenderBox && head.hasSize) {
      final b = head.localToGlobal(Offset.zero).dy + head.size.height;
      if ((b - _headBottom).abs() > .5) {
        _headBottom = b;
        changed = true;
      }
    }
    if (changed) setState(() {});
    if (_needReveal) {
      final p = _selectedPin;
      if (p != null && (_expanded || _slotH > 0)) {
        _needReveal = false;
        final screenH = MediaQuery.sizeOf(context).height;
        final navH = screenH - _mapH;
        // the card hides this much of the map's foot; the top block this much of its head
        final covered = _expanded ? (screenH - _bigTop(screenH) - navH) : _slotH + 12;
        _map.reveal(p.point, coveredTop: _headBottom + 8, coveredBottom: covered);
      }
    }
  }

  void _open(_Pin p) => unawaited(Navigator.of(context).pushNamed('/report', arguments: p.id));

  MapCardData _data(_Pin p) {
    final cat = p.cat;
    final s = context.s;
    final names = reportSteps(context, ReportStatus.inProgress).labels;
    final track = _trackFor(p.status, p.referredTo);
    final label = (p.locationLabel?.trim().isNotEmpty ?? false) ? p.locationLabel!.trim() : null;
    final c = _concerns[p.id];
    final at = _updated[p.id] ?? p.createdAt;
    final String stage;
    if (track.stop != null) {
      stage = track.stopLabel ?? '';
    } else if (p.status.index >= ReportStatus.assigned.index && track.done < 4) {
      stage = names[2];
    } else {
      stage = names[(track.done - 1).clamp(0, 3)];
    }
    return MapCardData(
      colour: categoryColour(cat),
      glyph: cat.icon,
      category: p.mine ? context.tr(cat.label, cat.labelFil) : context.tr('Published by the barangay', 'Inilathala ng barangay'),
      title: p.mine ? p.subject : context.tr(cat.label, cat.labelFil),
      ticket: p.mine ? p.trackingId : null,
      place: p.mine ? (label == null ? BarangayProfile.name : '$label, ${BarangayProfile.name}') : BarangayProfile.name,
      placeSub: '${BarangayProfile.name}, ${BarangayProfile.place}',
      statusLabel: s.reportStatusLabel(p.status.wire),
      statusColour: reportStatusColour(p.status),
      concerns: p.mine && c != null && c.total > 1
          ? context.tr('${c.total} concerns · ${c.resolved} resolved', '${c.total} concern · ${c.resolved} ang nalutas')
          : null,
      track: track,
      names: names,
      updated: p.mine && at != null ? context.tr('$stage · updated ${_ago(at)}', '$stage · na-update ${_ago(at)}') : null,
      note: p.mine ? null : s.mapPublishedNote,
    );
  }

  /// "2 hours ago", in the resident's language, lower case so it reads inside a sentence.
  String _ago(DateTime at) {
    final m = DateTime.now().difference(at).inMinutes;
    final h = m ~/ 60, days = m ~/ 1440;
    return m < 1
        ? context.tr('just now', 'ngayon lang')
        : m < 60
            ? (m == 1 ? context.tr('1 minute ago', '1 minuto ang nakalipas') : context.tr('$m minutes ago', '$m minuto ang nakalipas'))
            : m < 1440
                ? (h == 1 ? context.tr('an hour ago', 'isang oras ang nakalipas') : context.tr('$h hours ago', '$h oras ang nakalipas'))
                : m < 2880
                    ? context.tr('yesterday', 'kahapon')
                    : context.tr('$days days ago', '$days araw ang nakalipas');
  }

  /// The portal's track for a status (see the artifact's Track): Filed done and the barangay's review in progress; a tanod
  /// on it; resolved; or a stop where the case ended.
  MapTrackSpec _trackFor(ReportStatus st, String? office) {
    final referred = office != null && office.isNotEmpty && st.isOngoing;
    if (st == ReportStatus.rejected) return MapTrackSpec(done: 1, stop: 1, stopLabel: context.tr('Rejected', 'Tinanggihan'));
    if (st == ReportStatus.cancelled) return MapTrackSpec(done: 1, stop: 1, stopLabel: context.tr('Cancelled', 'Kinansela'), stopRed: false);
    if (referred) return MapTrackSpec(done: 1, stop: 1, stopLabel: context.tr('Escalated', 'In-escalate'), stopRed: false);
    return switch (st) {
      ReportStatus.pendingReview => const MapTrackSpec(done: 1, now: 1),
      ReportStatus.validated => const MapTrackSpec(done: 2, now: 2),
      ReportStatus.assigned || ReportStatus.inProgress || ReportStatus.offlineInvestigation => const MapTrackSpec(done: 2, now: 2),
      _ => const MapTrackSpec(done: 4),
    };
  }

  // ---------- the screen -----------------------------------------------

  List<MapChipData> _chips(BuildContext context) {
    final inLayers = _inLayers.toList();
    final mine = inLayers.where((p) => p.mine).length;
    final notices = inLayers.length - mine;
    final counts = <String, int>{};
    for (final p in inLayers) {
      counts[p.cat.wire] = (counts[p.cat.wire] ?? 0) + 1;
    }
    // a chip per category on the map, in the catalogue's order; the one chosen stays even when it has none
    final kinds = [
      for (final c in {...ComplaintCategory.values, ...inLayers.map((p) => p.cat)})
        if ((counts[c.wire] ?? 0) > 0 || c.wire == _category) c,
    ];
    final sources = [
      if (_lMine) MapChipData(id: 'mine', label: context.tr('My reports', 'Aking reports'), count: mine, selected: _source == _Source.mine),
      if (_lNotices)
        MapChipData(id: 'notices', label: context.tr('Notices', 'Mga paunawa'), count: notices, glyph: MapTabIcons.megaphone, selected: _source == _Source.notices),
    ];
    return [
      ...sources,
      if (sources.isNotEmpty && kinds.isNotEmpty) const MapChipData.divider(),
      for (final c in kinds)
        MapChipData(id: c.wire, label: context.tr(c.label, c.labelFil), count: counts[c.wire] ?? 0, dot: categoryColour(c), selected: _category == c.wire),
    ];
  }

  /// What sits at the foot of the map when no pin's card does: a state, or nothing.
  Widget? _note(BuildContext context) {
    final pins = _pins;
    if (_loading) return MapNote(title: context.tr('Loading your reports…', 'Nilo-load ang iyong mga report…'), busy: true);
    if (_failed) {
      return MapNote(
        title: context.tr('Your reports could not be read', 'Hindi mabasa ang iyong mga report'),
        body: context.tr('Check your connection and try again.', 'Tingnan ang iyong koneksyon at subukan ulit.'),
        action: context.tr('Try again', 'Subukan ulit'),
        onAction: _load,
      );
    }
    if (pins == null) return null;
    if (!_lMine && !_lNotices) {
      return MapNote(
        title: context.tr('Reports and notices are hidden', 'Nakatago ang mga report at paunawa'),
        body: context.tr('Turn one on in Layers.', 'I-on ang isa sa Mga layer.'),
        action: context.tr('Layers', 'Mga layer'),
        onAction: _openLayers,
      );
    }
    if (_inLayers.isEmpty) {
      return MapNote(
        title: context.tr('No reports yet', 'Wala pang report'),
        body: context.tr('The reports you file show up here as pins.', 'Lalabas dito bilang pin ang mga report na ipapasa mo.'),
        action: context.tr('Report a concern', 'Mag-report ng concern'),
        primary: true,
        onAction: () => unawaited(Navigator.of(context).pushNamed('/submit-report')),
      );
    }
    if (_visible.isEmpty && _filtering) {
      final onlyNotices = _source == _Source.notices && _category == null;
      return MapNote(
        title: onlyNotices ? context.tr('No barangay notices right now', 'Walang paunawa ang barangay ngayon') : context.tr('Nothing matches this filter', 'Walang tugma sa filter na ito'),
        action: context.tr('Show all', 'Ipakita lahat'),
        onAction: _clearFilter,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final skin = BrgyMapSkin.of(context);
    final fr = _flood;
    final fcol = fr == null || !fr.online ? d.muted : const [Color(0xFF22C55E), Color(0xFFEAB308), Color(0xFFF97316), Color(0xFFDC2626)][fr.level];
    final visible = _visible;
    final sel = _selectedPin;
    final note = sel == null ? _note(context) : null;
    final peek = sel != null && !_expanded;
    final bigOn = sel != null && _expanded;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final slotShown = peek || note != null;
    // the buttons sit 12 above a card, and clear of the map's attribution when there is none
    final dock = slotShown ? _slotH + 12 + 12 : 36.0;
    final screenH = MediaQuery.sizeOf(context).height;
    return Stack(children: [
      Scaffold(
        backgroundColor: d.bg,
        bottomNavigationBar: const ResidentNavBar(current: ResidentTab.map),
        body: LayoutBuilder(builder: (context, box) {
          _mapH = box.maxHeight;
          return Stack(children: [
            Positioned.fill(
              child: BrgyMap(
                use: BrgyMapUse.tab,
                controller: _map,
                initialCenter: brgyCentre,
                initialZoom: 16,
                dimOutside: _lDim,
                showPlaces: _lPlaces,
                selectedPinId: sel?.id,
                onMapTap: _closeCard,
                pins: [
                  for (final p in visible)
                    BrgyMapPin(
                      id: p.id,
                      point: p.point,
                      muted: !p.mine,
                      // as on the portal's Spatial Distribution: the pin is the complaint type's colour and symbol; the
                      // status is the dot on its shoulder
                      colour: categoryColour(p.cat),
                      glyph: p.cat.icon,
                      dot: reportStatusColour(p.status),
                      pulse: p.mine && (p.status == ReportStatus.inProgress || p.status == ReportStatus.assigned || p.status == ReportStatus.offlineInvestigation),
                    ),
                ],
                onPinTap: (id) {
                  for (final p in visible) {
                    if (p.id == id) {
                      _select(id);
                      return;
                    }
                  }
                },
              ),
            ),
            // the top box, and under it the chips
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 0,
              right: 0,
              child: Column(key: _headKey, crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      if (_lRain && fr != null && fr.online)
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
                const SizedBox(height: 8),
                MapFilterChips(chips: _chips(context), onTap: _tapChip),
              ]),
            ),
            // Layers on the left, Frame 183 on the right, level with each other
            Positioned(
              left: 14,
              bottom: dock,
              child: MapFab(label: context.tr('Layers', 'Mga layer'), glyph: MapTabIcons.layers, onTap: _openLayers),
            ),
            Positioned(
              right: 14,
              bottom: dock,
              child: MapFab(
                label: context.tr('Frame 183', 'I-frame ang 183'),
                glyph: MapTabIcons.locate,
                round: true,
                accent: true,
                onTap: () => _map.move(brgyCentre, 16),
              ),
            ),
            // the pin's small card, or a state
            if (slotShown)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: ConstrainedBox(
                  key: _slotKey,
                  constraints: BoxConstraints(maxHeight: screenH * .62),
                  child: peek
                      ? _scrollable(
                          MapPeekCard(data: _data(sel), onOpen: () => _open(sel), onExpand: _expand, onClose: _closeCard),
                        )
                      : note!,
                ),
              ),
          ]);
        }),
      ),
      // the expanded card covers the bottom bar too, as the artifact draws it
      if (bigOn)
        Positioned(
          left: 0,
          right: 0,
          top: _bigTop(screenH),
          bottom: 0,
          child: MapBigCard(data: _data(sel), onOpen: () => _open(sel), onCollapse: _collapse, onClose: _closeCard),
        ),
    ]);
  }

  /// A card that may be taller than the room it has (a large text size) scrolls rather than clips.
  Widget _scrollable(Widget card) => SingleChildScrollView(child: card);
}
