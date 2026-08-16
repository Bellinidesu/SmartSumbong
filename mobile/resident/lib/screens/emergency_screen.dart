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

import '../theme.dart';
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
      .order('sort_order');

  final numbers = await client
      .from('hotline_numbers')
      .select('group_id, label, number, carrier, sort_order')
      .eq('is_active', true)
      .order('sort_order');

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
        _error = _groups == null
            ? 'Could not load the emergency numbers. Check your connection '
                'and pull down to try again.'
            : null;
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
          color: Tokens.navy,
          child: _HotlineList(
            title: 'Need help?',
            groups: _groups,
            error: _error,
            stale: _stale,
          ),
        ),
      ),
    );
  }
}

/// A `link` group opened on its own screen — Police Villamor Substation
/// S59, or Pasay City Hotlines with its five headings.
class HotlineGroupScreen extends StatelessWidget {
  const HotlineGroupScreen({super.key, required this.group});

  final HotlineGroup group;

  @override
  Widget build(BuildContext context) {
    // A group that has children shows those. One that does not shows its 
    // own numbers — as a card, not as the link row it was on the
    // previous screen, or tapping it would push this screen again.
    final groups = group.children.isNotEmpty
        ? group.children
        : <HotlineGroup>[
            HotlineGroup(
              id: group.id,
              name: group.name,
              display: 'inline',
              numbers: group.numbers,
              children: const [],
            ),
          ];
        
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: _HotlineList(
                title: 'Need help?',
                groups: groups,
                error: null,
                stale: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 44, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- shared list --------------------------------------

class _HotlineList extends StatelessWidget {
  const _HotlineList({
    required this.title,
    required this.groups,
    required this.error,
    required this.stale,
  });

  final String title;
  final List<HotlineGroup>? groups;
  final String? error;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    if (groups == null && error == null) {
      return const Center(child: CircularProgressIndicator(color: Tokens.navy));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
      children: [
        Text(title,
            textAlign: TextAlign.center,
            style: t.headlineLarge?.copyWith(fontSize: 28)),
        const SizedBox(height: 8),
        Text(
          'Below are emergency services. View and select the number you '
          'want to copy or dial.',
          textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(fontSize: 14, height: 1.25),
        ),
        const SizedBox(height: 20),

        if (error != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Tokens.hint.withValues(alpha: 0.08),
              border: Border.all(color: Tokens.hint),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(error!,
                style: const TextStyle(color: Tokens.hint, fontSize: 13)),
          ),

        if (stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, size: 14, color: Tokens.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Showing the last numbers saved on this phone.',
                    style: const TextStyle(fontSize: 11, color: Tokens.muted),
                  ),
                ),
              ],
            ),
          ),

        for (final g in groups ?? const <HotlineGroup>[]) ...[
          if (g.isLink)
            _LinkRow(group: g)
          else
            _GroupCard(group: g),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// A navy card: the group name, then one row per number.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final HotlineGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Tokens.navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D121212),
            blurRadius: 2.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              group.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Tokens.bg,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final n in group.numbers) ...[
            _NumberRow(number: n),
            if (n != group.numbers.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// One number: label above if it has one, carrier beneath, then copy and
/// call. Both actions confirm first — a misdial to an emergency line
/// wastes somebody's time at the other end.
class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.number});

  final HotlineNumber number;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: number.dialable));
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _ConfirmSheet(
        message: '${number.number} copied',
        buttonLabel: 'Back',
        onButton: () => Navigator.of(context).pop(),
      ),
    );
  }

  Future<void> _call(BuildContext context) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmSheet(
        message: 'Call ${number.number}',
        onMessage: () => Navigator.of(context).pop(true),
        buttonLabel: 'Cancel',
        onButton: () => Navigator.of(context).pop(false),
      ),
    );
    if (go != true || !context.mounted) return;

    final uri = Uri(scheme: 'tel', path: number.dialable);
    if (!await launchUrl(uri)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open the dialler. The number is '
              '${number.number}.'),
          backgroundColor: Tokens.navy,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: Tokens.field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (number.label != null)
                  Text(
                    number.label!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Tokens.navy,
                    ),
                  ),
                Text(
                  number.number,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Tokens.navy,
                  ),
                ),
                if (number.carrier != null)
                  Text(
                    number.carrier!,
                    style: const TextStyle(fontSize: 9, color: Tokens.muted),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_rounded, size: 18, color: Tokens.navy),
            tooltip: 'Copy number',
            visualDensity: VisualDensity.compact,
          ),
          InkWell(
            onTap: () => _call(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFF25D366),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chevron rows that open Police and Pasay City on their own screens.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.group});

  final HotlineGroup group;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HotlineGroupScreen(group: group),
      )),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Tokens.navy,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D121212),
              blurRadius: 2.5,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              switch (group.name.toLowerCase()) {
                final n when n.contains('police') => Icons.local_police_outlined,
                _ => Icons.phone_in_talk_outlined,
              },
              color: Tokens.bg,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                group.name,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Tokens.bg,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Tokens.bg, size: 20),
          ],
        ),
      ),
    );
  }
}

/// The navy pill dialog from EMERGENCY - CONFIRMATION and
/// EMERGENCY - COPY NUMBERS.
/// The navy card from EMERGENCY - CONFIRMATION FOR MANUAL and
/// EMERGENCY - COPY NUMBERS.
///
/// Both frames are the same shape: a white pill, then one button under
/// it. What differs is whether the pill is the action. On the call
/// confirmation it is — "Call 0927 126 9625" is what you tap to dial,
/// and Cancel is the way out. On the copy confirmation the pill only
/// reports what happened, and Back dismisses it.
///
/// The frames mask the digits as "O9** *** ****". That is placeholder
/// artwork, not a requirement: the number is the one thing the resident
/// is being asked to confirm, and in an emergency dialling the wrong
/// hotline because it was hidden is the failure this dialog exists to
/// prevent. The real number is shown.
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
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
    final pill = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Tokens.field,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Tokens.navy,
        ),
      ),
    );

    return Dialog(
      backgroundColor: Tokens.navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onMessage == null)
              pill
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onButton,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tokens.bg,
                  side: const BorderSide(color: Tokens.bg),
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
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
