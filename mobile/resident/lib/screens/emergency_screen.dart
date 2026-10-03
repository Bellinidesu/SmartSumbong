// SmartSumbong — Emergency.
//
// Figma: EMERGENCY, EMERGENCY - POLICE, EMERGENCY - PASAY,
// EMERGENCY - CONFIRMATION FOR MANUAL, EMERGENCY - COPY NUMBERS.
//
// A directory, not a dispatch. "Below are emergency services. View and
// select the number you want to copy or dial." The resident's phone
// makes the call; the barangay is not in the loop and nothing is
// written. That is View list of Emergency Service Hotline in the use
// case, and it is deliberately the whole of it — the second Emergency
// flow in the Figma file (press-to-alert, responder on the way) predates
// the panel narrowing this system to complaints, and building it would
// mean a second dispatch path beside the one that exists.
//
// OFFLINE. The numbers come from hotline_groups / hotline_numbers, which
// the barangay maintains through the admin portal, and are cached to
// disk after every successful load. The moment a resident most needs a
// fire hotline is not reliably the moment they have signal, so a stale
// list beats an empty screen. The cache is only ever replaced by a
// successful fetch, never cleared on failure.
//
// The table is readable without a session (0025), so this screen also
// works for someone whose account is still pending verification.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../widgets/resident_nav_bar.dart';

const _cacheKey = 'hotlines_v1';

class HotlineNumber {
  const HotlineNumber({
    required this.number,
    this.label,
    this.carrier,
  });

  final String number;
  final String? label;
  final String? carrier;

  /// Digits only, plus a leading + if present. The barangay types the
  /// number the way it appears on their signage; the dialler wants it
  /// without the spaces.
  String get dialable => number.replaceAll(RegExp(r'[^0-9+]'), '');

  Map<String, dynamic> toJson() =>
      {'number': number, 'label': label, 'carrier': carrier};

  factory HotlineNumber.fromJson(Map<String, dynamic> j) => HotlineNumber(
        number: j['number'] as String,
        label: j['label'] as String?,
        carrier: j['carrier'] as String?,
      );
}

class HotlineGroup {
  HotlineGroup({
    required this.id,
    required this.name,
    required this.display,
    required this.numbers,
    required this.children,
  });

  final String id;
  final String name;

  /// 'inline' renders its numbers here; 'link' shows a chevron row that
  /// opens the group on its own screen.
  final String display;

  final List<HotlineNumber> numbers;
  final List<HotlineGroup> children;

  bool get isLink => display == 'link';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'display': display,
        'numbers': [for (final n in numbers) n.toJson()],
        'children': [for (final c in children) c.toJson()],
      };

  factory HotlineGroup.fromJson(Map<String, dynamic> j) => HotlineGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        display: j['display'] as String? ?? 'inline',
        numbers: [
          for (final n in (j['numbers'] as List? ?? []))
            HotlineNumber.fromJson(n as Map<String, dynamic>),
        ],
        children: [
          for (final c in (j['children'] as List? ?? []))
            HotlineGroup.fromJson(c as Map<String, dynamic>),
        ],
      );
}

// ---------- loading ------------------------------------------

Future<List<HotlineGroup>> _fetchHotlines() async {
  final client = Supabase.instance.client;

  final groups = await client
      .from('hotline_groups')
      .select('id, parent_id, name, display, sort_order')
      .eq('is_active', true)
      // postgrest-dart orders descending unless told otherwise; the
      // barangay's sort_order is meant low-first (Barangay 183 on top).
      .order('sort_order', ascending: true);

  final numbers = await client
      .from('hotline_numbers')
      .select('group_id, label, number, carrier, sort_order')
      .eq('is_active', true)
      .order('sort_order', ascending: true);

  final byGroup = <String, List<HotlineNumber>>{};
  for (final n in numbers) {
    (byGroup[n['group_id'] as String] ??= []).add(HotlineNumber(
      number: n['number'] as String,
      label: n['label'] as String?,
      carrier: n['carrier'] as String?,
    ));
  }

  List<HotlineGroup> build(String? parent) => [
        for (final g in groups.where((g) => g['parent_id'] == parent))
          HotlineGroup(
            id: g['id'] as String,
            name: g['name'] as String,
            display: g['display'] as String? ?? 'inline',
            numbers: byGroup[g['id'] as String] ?? const [],
            children: build(g['id'] as String),
          ),
      ];

  return build(null);
}

// ---------- screen -------------------------------------------

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  List<HotlineGroup>? _groups;
  bool _stale = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Show whatever was last seen immediately, then try to refresh. A
    // resident opening this screen should never wait on the network to
    // see a number they could already have dialled.
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null && mounted && _groups == null) {
      try {
        final decoded = jsonDecode(cached) as List;
        setState(() {
          _groups = [
            for (final g in decoded)
              HotlineGroup.fromJson(g as Map<String, dynamic>),
          ];
          _stale = true;
        });
      } catch (_) {
        // Corrupt cache is not worth reporting; the fetch below replaces it.
      }
    }

    try {
      final fresh = await _fetchHotlines();
      if (!mounted) return;
      setState(() {
        _groups = fresh;
        _stale = false;
        _error = null;
      });
      await prefs.setString(
        _cacheKey,
        jsonEncode([for (final g in fresh) g.toJson()]),
      );
    } catch (_) {
      if (!mounted) return;
      // Never clear the cache on failure — a stale hotline beats none.
      setState(() {
        _error = _groups == null ? context.s.emergencyLoadError : null;
        _stale = _groups != null;
      });
    }
  }

  // Branch D: the preview's Emergency — gradient cards with a soft glow of
  // their own colour (911 red, fire orange, the barangay navy), slide to
  // call on the labelled numbers, and the link groups as cards that open
  // over the page. The contour fades up from the bottom.
  @override
  Widget build(BuildContext context) {
    return DPage(
      bottomBar: const ResidentNavBar(current: ResidentTab.emergency),
      child: RefreshIndicator(
        onRefresh: _load,
        color: context.d.accent,
        child: _HotlineList(groups: _groups, error: _error, stale: _stale),
      ),
    );
  }
}

/// A `link` group (Police Villamor Substation S59, Pasay City Hotlines)
/// opened over the Emergency page as one card, its sub-headings and
/// numbers inside, Back at its foot.
class HotlineGroupScreen extends StatelessWidget {
  const HotlineGroupScreen({super.key, required this.group});

  final HotlineGroup group;

  static Route<void> route(HotlineGroup group) => PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondary) => HotlineGroupScreen(group: group),
        transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(animation), child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final sections = group.children.isNotEmpty ? group.children : <HotlineGroup>[group];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: DCard(
              glow: const Color(0xFF3B6BD8),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(group.name, textAlign: TextAlign.center, style: DType.h2(Colors.white)),
                const SizedBox(height: 14),
                for (final g in sections) ...[
                  if (sections.length > 1) ...[
                    Text(g.name.toUpperCase(), style: DType.label(Colors.white.withValues(alpha: .75))),
                    const SizedBox(height: 8),
                  ],
                  for (final n in g.numbers) ...[
                    _NumberRow(number: n),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                ],
                DButton(context.s.emergencyBack, kind: DButtonKind.white, expand: true, onTap: () => Navigator.of(context).pop()),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _HotlineList extends StatelessWidget {
  const _HotlineList({required this.groups, required this.error, required this.stale});

  final List<HotlineGroup>? groups;
  final String? error;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    if (groups == null && error == null) {
      return Center(child: CircularProgressIndicator(color: d.accent));
    }

    final cards = <Widget>[];
    for (final g in groups ?? const <HotlineGroup>[]) {
      if (g.isLink) {
        cards.add(_LinkRow(group: g));
        continue;
      }
      final plain = [for (final n in g.numbers) if (n.label == null) n];
      final labelled = [for (final n in g.numbers) if (n.label != null) n];
      if (plain.isNotEmpty) cards.add(_GroupCard(name: g.name, numbers: plain));
      for (final n in labelled) {
        cards.add(_SlideCard(number: n));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text(s.emergencyNeedHelp, style: DType.h1(d.accent).copyWith(fontSize: 30)),
        const SizedBox(height: 6),
        Text(s.emergencyInstructions, style: DType.body(d.muted, size: 14.5)),
        const SizedBox(height: 20),
        if (error != null) ...[
          DSheet(
            borderColor: DColors.red.withValues(alpha: .5),
            child: Text(error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
        ],
        if (stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: d.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(s.emergencyStaleNote, style: DType.body(d.muted, size: 12))),
            ]),
          ),
        for (final c in cards) ...[c, const SizedBox(height: 16)],
      ],
    );
  }
}

Future<void> _copy(BuildContext context, HotlineNumber number) async {
  await Clipboard.setData(ClipboardData(text: number.dialable));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.s.emergencyNumberCopied(number.number))));
}

Future<void> _dial(BuildContext context, HotlineNumber number) async {
  final uri = Uri(scheme: 'tel', path: number.dialable);
  if (!await launchUrl(uri)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.s.emergencyDiallerFailed(number.number))));
  }
}

/// Both actions on a manual row confirm first — a misdial to an
/// emergency line wastes somebody's time at the other end.
Future<void> _confirmThenDial(BuildContext context, HotlineNumber number) async {
  final s = context.s;
  final go = await showDDialog(
    context,
    title: s.emergencyCallPrompt(number.number),
    body: number.label ?? number.carrier,
    primary: s.emergencyCallPrompt(number.number),
    primaryKind: DButtonKind.green,
    secondary: s.emergencyCancel,
    icon: Icons.call_rounded,
    iconColor: DColors.greenVivid,
  );
  if (go != true || !context.mounted) return;
  await _dial(context, number);
}

/// The barangay's own numbers: a navy card with a soft blue glow, each
/// number a white row with copy and a green call button.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.name, required this.numbers});

  final String name;
  final List<HotlineNumber> numbers;

  @override
  Widget build(BuildContext context) {
    return DCard(
      glow: const Color(0xFF3B6BD8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 10), child: Text(name, style: DType.h3(Colors.white))),
        for (final n in numbers) ...[
          _NumberRow(number: n),
          if (n != numbers.last) const SizedBox(height: 8),
        ],
      ]),
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.number});

  final HotlineNumber number;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF141B34);
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(number.number, style: DType.mono(ink, size: 15.5)),
            if (number.carrier != null) Text(number.carrier!, style: DType.body(const Color(0xFF6E7489), size: 11.5)),
          ]),
        ),
        IconButton(
          onPressed: () => _copy(context, number),
          icon: const Icon(Icons.content_copy_rounded, size: 19, color: Color(0xFF00308F)),
          tooltip: context.s.emergencyCopyNumberTooltip,
        ),
        Semantics(
          button: true,
          label: context.s.emergencyCallPrompt(number.number),
          excludeSemantics: true,
          child: InkWell(
            onTap: () => _confirmThenDial(context, number),
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DColors.greenVivid,
                boxShadow: [BoxShadow(color: DColors.greenVivid.withValues(alpha: .4), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A labelled number on its own (911, the fire station): a gradient card
/// in its own colour with a soft glow, copy at the right, slide to call.
class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.number});

  final HotlineNumber number;

  @override
  Widget build(BuildContext context) {
    final l = number.label!.toLowerCase();
    final fire = l.contains('fire') || l.contains('sunog') || l.contains('bfp');
    final grad = fire ? const [Color(0xFFFF8A1F), Color(0xFFD9480F)] : const [Color(0xFFE53935), Color(0xFF8E1B1B)];
    return DCard(
      gradient: grad,
      glow: grad[0],
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(number.label!, style: DType.h3(Colors.white).copyWith(fontSize: 18)),
              Text(number.number, style: DType.mono(Colors.white.withValues(alpha: .85), size: 13)),
            ]),
          ),
          IconButton(
            onPressed: () => _copy(context, number),
            icon: const Icon(Icons.content_copy_rounded, size: 19, color: Colors.white),
            tooltip: context.s.emergencyCopyNumberTooltip,
          ),
        ]),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _SlideToCall(number: number, tint: grad[1], icon: fire ? Icons.local_fire_department_rounded : Icons.call_rounded),
        ),
      ]),
    );
  }
}

/// Slide to call: drag the white knob to the far end and it dials — the
/// slide is itself the confirmation, which is the point of it on an
/// emergency line. Let go early and it springs back. A screen reader's
/// double-tap asks to confirm, then dials.
class _SlideToCall extends StatefulWidget {
  const _SlideToCall({required this.number, required this.tint, required this.icon});

  final HotlineNumber number;
  final Color tint;
  final IconData icon;

  @override
  State<_SlideToCall> createState() => _SlideToCallState();
}

class _SlideToCallState extends State<_SlideToCall> with SingleTickerProviderStateMixin {
  static const _knob = 44.0;
  static const _inset = 4.0;

  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => setState(() => _dx = _from * (1 - _back.value)));

  double _dx = 0;
  double _from = 0;
  bool _firing = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _springBack() {
    _from = _dx;
    _back.forward(from: 0);
  }

  Future<void> _release(double max) async {
    if (_dx >= max * 0.85 && !_firing) {
      _firing = true;
      setState(() => _dx = max);
      HapticFeedback.mediumImpact();
      await _dial(context, widget.number);
      _firing = false;
      if (mounted) _springBack();
    } else {
      _springBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return LayoutBuilder(builder: (context, box) {
      final max = box.maxWidth - _knob - _inset * 2;
      final progress = max <= 0 ? 0.0 : (_dx / max).clamp(0.0, 1.0);
      return Semantics(
        button: true,
        label: s.emergencyCallPrompt(widget.number.label ?? widget.number.number),
        excludeSemantics: true,
        onTap: () => _confirmThenDial(context, widget.number),
        child: Container(
          height: 52,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(99)),
          child: Stack(alignment: Alignment.centerLeft, children: [
            // the run behind the knob fills as it slides
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _dx + _knob + _inset * 2,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.white.withValues(alpha: .22), borderRadius: BorderRadius.circular(99))),
            ),
            Center(
              child: Opacity(
                opacity: 1 - progress,
                child: Text(s.emergencySlideToCall,
                    style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
              ),
            ),
            Positioned(
              right: 16,
              child: Opacity(opacity: 1 - progress, child: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 20, color: Colors.white70)),
            ),
            Positioned(
              left: _inset + _dx,
              child: GestureDetector(
                onHorizontalDragStart: (_) => _back.stop(),
                onHorizontalDragUpdate: (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, max)),
                onHorizontalDragEnd: (_) => _release(max),
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .2), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Icon(widget.icon, color: widget.tint, size: 22),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

/// Police and Pasay City: a navy card that opens the group over the page.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.group});

  final HotlineGroup group;

  @override
  Widget build(BuildContext context) {
    final police = group.name.toLowerCase().contains('police');
    return DCard(
      onTap: () => Navigator.of(context).push(HotlineGroupScreen.route(group)),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .15)),
          child: Icon(police ? Icons.local_police_rounded : Icons.phone_in_talk_rounded, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(group.name, style: DType.h3(Colors.white).copyWith(fontSize: 16))),
        const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
      ]),
    );
  }
}
