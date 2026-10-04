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

  // Branch D, 1:1 with the preview's Emergency, the layout as the live app
  // has it: the centred heading, then 911 and the fire station as
  // red/orange gradient cards with their own breathing glow and a swipe
  // to call, the barangay's numbers on the blue card as white pill rows
  // (copy and a green call button), and Police / Pasay City as cards that
  // open over the page.
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
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: DCard(
              gradient: _blue(context.d.dark),
              glow: const Color(0xFF0048C8),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(group.name, textAlign: TextAlign.center, style: DType.h3(Colors.white).copyWith(fontSize: 16)),
                const SizedBox(height: 10),
                for (final g in sections) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (sections.length > 1)
                        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 6), child: Text(g.name, style: DType.body(Colors.white, size: 13.5, w: FontWeight.w800))),
                      for (final n in g.numbers) ...[_NumberRow(number: n), if (n != g.numbers.last) const SizedBox(height: 6)],
                    ]),
                  ),
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

List<Color> _blue(bool dark) => dark ? const [Color(0xFF1A2E6E), Color(0xFF13235A), Color(0xFF0A1640)] : const [Color(0xFF0A3BA0), Color(0xFF00308F), Color(0xFF001F63)];

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
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Text(s.emergencyNeedHelp, textAlign: TextAlign.center, style: DType.h1(d.dark ? Colors.white : DColors.brandNavy).copyWith(fontSize: 28, letterSpacing: 0)),
        const SizedBox(height: 4),
        Text(s.emergencyInstructions, textAlign: TextAlign.center, style: DType.body(d.ink2, size: 14).copyWith(height: 1.4)),
        const SizedBox(height: 12),
        if (error != null) ...[
          DSheet(
            borderColor: DColors.red.withValues(alpha: .5),
            child: Text(error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
        ],
        if (stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: d.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(s.emergencyStaleNote, style: DType.body(d.muted, size: 12))),
            ]),
          ),
        for (final c in cards) ...[c, const SizedBox(height: 12)],
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

/// A card's soft halo that breathes (`glowRed` / `glowFire`, 3 s).
class _Breathe extends StatefulWidget {
  const _Breathe({required this.color, required this.child, this.radius = 22});

  final Color color;
  final Widget child;
  final double radius;

  @override
  State<_Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<_Breathe> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: [BoxShadow(color: widget.color.withValues(alpha: .32 + .10 * t), blurRadius: 12 + 4 * t, spreadRadius: 1 + t)],
            ),
            child: child,
          );
        },
        child: widget.child,
      );
}

/// The barangay's own numbers (`.hl`): the blue card, its title centred,
/// each number a white pill row.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.name, required this.numbers});

  final String name;
  final List<HotlineNumber> numbers;

  @override
  Widget build(BuildContext context) {
    return DCard(
      gradient: _blue(context.d.dark),
      glow: const Color(0xFF0048C8),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name, textAlign: TextAlign.center, style: DType.h3(Colors.white).copyWith(fontSize: 16)),
        const SizedBox(height: 10),
        for (final n in numbers) ...[
          _NumberRow(number: n),
          if (n != numbers.last) const SizedBox(height: 8),
        ],
      ]),
    );
  }
}

/// `.num`: a white pill (dark: #22305E) — the number in Inter 16/700, its
/// carrier under it, copy, and a 38 px green call button.
class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.number});

  final HotlineNumber number;

  @override
  Widget build(BuildContext context) {
    final dark = context.d.dark;
    final fg = dark ? Colors.white : const Color(0xFF00308F);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(color: dark ? const Color(0xFF22305E) : Colors.white, borderRadius: BorderRadius.circular(99)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(number.number, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: .16, color: fg)),
            if (number.carrier != null) Text(number.carrier!, style: TextStyle(fontFamily: 'Urbanist', fontSize: 11.5, color: dark ? const Color(0xFF9096AB) : const Color(0xFF6E7489))),
          ]),
        ),
        InkWell(
          onTap: () => _copy(context, number),
          customBorder: const CircleBorder(),
          child: SizedBox(width: 34, height: 34, child: Icon(Icons.content_copy_rounded, size: 18, color: fg)),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          label: context.s.emergencyCallPrompt(number.number),
          excludeSemantics: true,
          child: InkWell(
            onTap: () => _confirmThenDial(context, number),
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1F8A45), boxShadow: [BoxShadow(color: Color(0x591F8A45), blurRadius: 8, offset: Offset(0, 3))]),
              child: const Icon(Icons.call_rounded, color: Colors.white, size: 19),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A labelled number on its own (911, the fire station): `.sos` — a
/// 150° gradient, the label and number on the left, copy on the right in
/// a 36 px rounded square, and the swipe to call.
class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.number});

  final HotlineNumber number;

  @override
  Widget build(BuildContext context) {
    final l = number.label!.toLowerCase();
    final fire = l.contains('fire') || l.contains('sunog') || l.contains('bfp');
    final grad = fire ? const [Color(0xFFFF9A3D), Color(0xFFEF6C00), Color(0xFFB23C00)] : const [Color(0xFFF05454), Color(0xFFD32F2F), Color(0xFF8E1B1B)];
    return _Breathe(
      color: fire ? const Color(0xFFEF6C00) : const Color(0xFFE53935),
      child: DCard(
        gradient: grad,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(number.label!, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                Text(number.number, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w500, fontSize: 12, color: Colors.white.withValues(alpha: .85))),
              ]),
            ),
            InkWell(
              onTap: () => _copy(context, number),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.content_copy_rounded, size: 18, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _SlideToCall(number: number, fire: fire, icon: fire ? Icons.local_fire_department_rounded : Icons.call_rounded),
        ]),
      ),
    );
  }
}

/// `.slide`: a 54 px white track, the label centred with a "›››" after
/// it, and a 46 px knob (green; red on the fire card) that dials when it
/// reaches the end. Let go early and it springs back. A screen reader's
/// double-tap asks to confirm, then dials.
class _SlideToCall extends StatefulWidget {
  const _SlideToCall({required this.number, required this.fire, required this.icon});

  final HotlineNumber number;
  final bool fire;
  final IconData icon;

  @override
  State<_SlideToCall> createState() => _SlideToCallState();
}

class _SlideToCallState extends State<_SlideToCall> with SingleTickerProviderStateMixin {
  static const _knob = 46.0;
  static const _inset = 4.0;

  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
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
    final txt = widget.fire ? const Color(0xFFB23C00) : const Color(0xFF8E1B1B);
    return LayoutBuilder(builder: (context, box) {
      final max = box.maxWidth - _knob - _inset * 2;
      final progress = max <= 0 ? 0.0 : (_dx / max).clamp(0.0, 1.0);
      return Semantics(
        button: true,
        label: s.emergencyCallPrompt(widget.number.label ?? widget.number.number),
        excludeSemantics: true,
        onTap: () => _confirmThenDial(context, widget.number),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 54,
            color: Colors.white.withValues(alpha: .95),
            child: Stack(alignment: Alignment.centerLeft, children: [
              Positioned(left: 0, top: 0, bottom: 0, width: _dx + _knob + _inset, child: ColoredBox(color: const Color(0xFF1F8A45).withValues(alpha: .18))),
              Center(
                child: Opacity(
                  opacity: 1 - progress,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: s.emergencySlideToCall, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: .28, color: txt)),
                    TextSpan(text: '  ›››', style: TextStyle(fontSize: 14, letterSpacing: 2, color: txt.withValues(alpha: .5))),
                  ])),
                ),
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
                      color: widget.fire ? const Color(0xFFE53935) : const Color(0xFF1F8A45),
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 21),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

/// `.grp`: Police and Pasay City — the blue card as one tappable row, the
/// icon, the name 15.5/800 and a chevron, opening the group over the page.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.group});

  final HotlineGroup group;

  @override
  Widget build(BuildContext context) {
    final police = group.name.toLowerCase().contains('police');
    return DCard(
      gradient: _blue(context.d.dark),
      glow: const Color(0xFF0048C8),
      radius: 20,
      onTap: () => Navigator.of(context).push(HotlineGroupScreen.route(group)),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(police ? Icons.local_police_outlined : Icons.phone_in_talk_outlined, color: Colors.white, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(group.name, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 15.5, color: Colors.white))),
        const Text('›', style: TextStyle(fontSize: 22, height: 1, color: Colors.white)),
      ]),
    );
  }
}
