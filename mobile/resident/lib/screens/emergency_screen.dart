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
import '../theme.dart';
import '../widgets/figma_ui.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar:
          const ResidentNavBar(current: ResidentTab.emergency),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: context.colors.navy,
          child: _HotlineList(
            groups: _groups,
            error: _error,
            stale: _stale,
          ),
        ),
      ),
    );
  }
}

/// A `link` group opened over the Emergency page — Police Villamor
/// Substation S59, or Pasay City Hotlines with its five headings.
///
/// Figma EMERGENCY - PASAY draws this as one tall navy card (316 wide,
/// radius 25) floating over the Emergency page faded to 30%, headings
/// 16/700 centred, rows inset 13, and a 106x40 light Back at its foot —
/// so it is opened as a see-through route rather than a new page.
class HotlineGroupScreen extends StatelessWidget {
  const HotlineGroupScreen({super.key, required this.group});

  final HotlineGroup group;

  static Route<void> route(HotlineGroup group) => PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: const Color(0x00000000),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (context, animation, secondary) =>
            HotlineGroupScreen(group: group),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  @override
  Widget build(BuildContext context) {
    // A group that has children shows those; one that does not shows its
    // own numbers under its own name.
    final sections = group.children.isNotEmpty
        ? group.children
        : <HotlineGroup>[group];

    return Scaffold(
      backgroundColor: context.colors.bg.withValues(alpha: 0.7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 20, 40, 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 23, 13, 33),
              decoration: BoxDecoration(
                color: context.colors.navy,
                borderRadius: BorderRadius.circular(25),
                boxShadow: kFigmaShadow,
              ),
              child: Column(
                children: [
                  for (final g in sections) ...[
                    _Heading(g.name, size: 16),
                    const SizedBox(height: 10),
                    for (final n in g.numbers) ...[
                      _NumberRow(number: n),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 3),
                  FigmaDialogPill(
                    label: context.s.emergencyBack,
                    onPressed: () => Navigator.of(context).pop(),
                    filled: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- shared list --------------------------------------

/// Figma EMERGENCY: "Need help?" 28/800 at 50, the 16/600 instructions,
/// then the barangay's groups in its order. A group's unlabelled numbers
/// sit as rows in its navy card; a labelled number (911, Fire Protection)
/// gets a card of its own with the frame's Slide to Call; a `link` group
/// is a navy row that opens the group. Cards 325 wide, 12 apart.
class _HotlineList extends StatelessWidget {
  const _HotlineList({
    required this.groups,
    required this.error,
    required this.stale,
  });

  final List<HotlineGroup>? groups;
  final String? error;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (groups == null && error == null) {
      return Center(child: CircularProgressIndicator(color: context.colors.navy));
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
      padding: EdgeInsets.fromLTRB(41, figmaTop(context, 50), 41, 24),
      children: [
        FigmaTitle(s.emergencyNeedHelp),
        Text(
          s.emergencyInstructions,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w600,
            fontSize: 16,
            height: 20 / 16,
            color: context.colors.navy,
          ),
        ),
        const SizedBox(height: 33),

        if (error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.hint.withValues(alpha: 0.08),
              border: Border.all(color: context.colors.hint),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Text(error!,
                style: TextStyle(color: context.colors.hint, fontSize: 13)),
          ),
          const SizedBox(height: 12),
        ],

        if (stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.cloud_off, size: 14, color: context.colors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.emergencyStaleNote,
                    style: TextStyle(fontSize: 11, color: context.colors.muted),
                  ),
                ),
              ],
            ),
          ),

        for (final c in cards) ...[
          c,
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// A navy card's heading: 15/700 (16 on the Pasay card) light, centred.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.size = 15});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Urbanist',
          fontWeight: FontWeight.w700,
          fontSize: size,
          height: 20 / 15,
          color: context.colors.bg,
        ),
      );
}

/// The frame's group card: navy, radius 25, the heading 8 down, then the
/// numbers as 53-tall light rows 10 apart, 16 in from the card's sides.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.name, required this.numbers});

  final String name;
  final List<HotlineNumber> numbers;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 17),
      decoration: BoxDecoration(
        color: context.colors.navy,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          _Heading(name),
          const SizedBox(height: 10),
          for (final n in numbers) ...[
            _NumberRow(number: n),
            if (n != numbers.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

Future<void> _copy(BuildContext context, HotlineNumber number) async {
  await Clipboard.setData(ClipboardData(text: number.dialable));
  if (!context.mounted) return;
  final s = context.s;
  await showFigmaDialog<void>(
    context,
    builder: (dialogContext) => _PillDialog(
      message: s.emergencyNumberCopied(number.number),
      buttonLabel: s.emergencyBack,
      onButton: () => Navigator.of(dialogContext).pop(),
    ),
  );
}

Future<void> _dial(BuildContext context, HotlineNumber number) async {
  final uri = Uri(scheme: 'tel', path: number.dialable);
  if (!await launchUrl(uri)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.s.emergencyDiallerFailed(number.number)),
        backgroundColor: context.colors.navy,
      ),
    );
  }
}

/// Figma EMERGENCY - CONFIRMATION FOR MANUAL: the pill is the action.
/// Both actions on a manual row confirm first — a misdial to an
/// emergency line wastes somebody's time at the other end.
Future<void> _confirmThenDial(BuildContext context, HotlineNumber number) async {
  final s = context.s;
  final go = await showFigmaDialog<bool>(
    context,
    builder: (dialogContext) => _PillDialog(
      message: s.emergencyCallPrompt(number.number),
      onMessage: () => Navigator.of(dialogContext).pop(true),
      buttonLabel: s.emergencyCancel,
      onButton: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  if (go != true || !context.mounted) return;
  await _dial(context, number);
}

/// The frame's copy glyph: 15x18, navy.
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.number, required this.colour});

  final HotlineNumber number;
  final Color colour;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () => _copy(context, number),
        icon: Icon(Icons.content_copy_outlined, size: 18, color: colour),
        tooltip: context.s.emergencyCopyNumberTooltip,
        visualDensity: VisualDensity.compact,
      );
}

/// One manual number: a 53-tall light row, radius 25 — the number 15/700
/// and its carrier 10/500 20 in, the copy glyph, and the 31px green call
/// circle 15 from the right.
class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.number});

  final HotlineNumber number;

  @override
  Widget build(BuildContext context) {
    final navy = context.colors.navy;
    return Container(
      constraints: const BoxConstraints(minHeight: 53),
      padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
      decoration: BoxDecoration(
        color: context.colors.bg,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  number.number,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 18 / 15,
                    color: navy,
                  ),
                ),
                if (number.carrier != null)
                  Text(
                    number.carrier!,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                      height: 12 / 10,
                      color: navy,
                    ),
                  ),
              ],
            ),
          ),
          _CopyButton(number: number, colour: navy),
          Semantics(
            button: true,
            label: context.s.emergencyCallPrompt(number.number),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => _confirmThenDial(context, number),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Container(
                  width: 31,
                  height: 31,
                  decoration: const BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call, color: Colors.white, size: 17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _green = Color(0xFF058F00);
const _red = Color(0xFFFF4949);

/// A labelled number on its own: the frame's 911 and Fire Protection
/// cards — navy, radius 25, 95 tall, the label 15/700 with the copy glyph
/// at the right, and the 302x44 Slide to Call track under it.
class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.number});

  final HotlineNumber number;

  @override
  Widget build(BuildContext context) {
    final fire = number.label!.toLowerCase().contains('fire') ||
        number.label!.toLowerCase().contains('sunog');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 11),
      decoration: BoxDecoration(
        color: context.colors.navy,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  number.label!,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 20 / 15,
                    color: context.colors.bg,
                  ),
                ),
              ),
              _CopyButton(number: number, colour: context.colors.bg),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _SlideToCall(
              number: number,
              knob: fire ? _red : _green,
              icon: fire ? Icons.local_fire_department : Icons.call,
            ),
          ),
        ],
      ),
    );
  }
}

/// The frame's Slide to Call: a 44-tall light track with a 39px knob.
/// Dragging the knob to the far end dials — the slide is itself the
/// confirmation, which is the point of it on an emergency line. Let go
/// early and it springs back. For a screen reader, double-tapping the
/// control asks to confirm, then dials.
class _SlideToCall extends StatefulWidget {
  const _SlideToCall({
    required this.number,
    required this.knob,
    required this.icon,
  });

  final HotlineNumber number;
  final Color knob;
  final IconData icon;

  @override
  State<_SlideToCall> createState() => _SlideToCallState();
}

class _SlideToCallState extends State<_SlideToCall>
    with SingleTickerProviderStateMixin {
  static const _knob = 39.0;
  static const _inset = 2.5;

  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));

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
          height: 44,
          decoration: BoxDecoration(
            color: context.colors.bg,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Opacity(
                  opacity: 1 - progress,
                  child: Text(
                    s.emergencySlideToCall,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      color: context.colors.navy,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                child: Opacity(
                  opacity: 1 - progress,
                  child: Icon(Icons.chevron_right,
                      size: 18, color: context.colors.navy),
                ),
              ),
              Positioned(
                left: _inset + _dx,
                child: GestureDetector(
                  onHorizontalDragStart: (_) => _back.stop(),
                  onHorizontalDragUpdate: (d) => setState(
                      () => _dx = (_dx + d.delta.dx).clamp(0.0, max)),
                  onHorizontalDragEnd: (_) => _release(max),
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      color: widget.knob,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// The chevron rows that open Police and Pasay City: navy, radius 25, 53
/// tall, the icon 20 in and the name 15/700 at 51.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.group});

  final HotlineGroup group;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.navy,
      borderRadius: BorderRadius.circular(25),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Navigator.of(context).push(HotlineGroupScreen.route(group)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 53),
          padding: const EdgeInsets.fromLTRB(20, 8, 14, 8),
          child: Row(
            children: [
              Icon(
                switch (group.name.toLowerCase()) {
                  final n when n.contains('police') =>
                    Icons.directions_car_filled,
                  _ => Icons.phone_outlined,
                },
                color: context.colors.bg,
                size: 22,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  group.name,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 20 / 15,
                    color: context.colors.bg,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: context.colors.bg, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma EMERGENCY - COPY NUMBERS / - CONFIRMATION FOR MANUAL: a 300-wide
/// navy card, radius 50, 2px #252525 edge, with a light 239x40 pill over
/// a navy 239x40 button, 13 apart. On the call confirmation the pill is
/// the action ("Call 0927 126 9625") and Cancel the way out; on the copy
/// confirmation the pill only reports, and Back dismisses.
///
/// The frames mask the digits as "09** *** ****". That is placeholder
/// artwork, not a requirement: the number is the thing being confirmed,
/// so the real one is shown.
class _PillDialog extends StatelessWidget {
  const _PillDialog({
    required this.message,
    required this.buttonLabel,
    required this.onButton,
    this.onMessage,
  });

  final String message;
  final String buttonLabel;
  final VoidCallback onButton;

  /// When set, the pill is the confirming action.
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const text = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 16,
    );
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(50),
        boxShadow: kFigmaShadow,
      ),
      child: Text(message,
          textAlign: TextAlign.center, style: text.copyWith(color: c.navy)),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 25),
        decoration: BoxDecoration(
          color: c.navy,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: const Color(0xFF252525), width: 2),
          boxShadow: kFigmaShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onMessage == null)
              Semantics(liveRegion: true, child: pill)
            else
              Semantics(
                button: true,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(onTap: onMessage, child: pill),
                ),
              ),
            const SizedBox(height: 13),
            DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(50)),
                boxShadow: kFigmaShadow,
              ),
              child: OutlinedButton(
                onPressed: onButton,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.bg,
                  backgroundColor: c.navy,
                  side: BorderSide(color: c.bg),
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  textStyle: text,
                ),
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
