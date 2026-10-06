// SmartSumbong — Notification Preferences.
//
// Added 29 Aug 2026. No Figma frame — there is no design for this screen
// because it never existed as a use case; built to match theme_screen.dart
// and languages_screen.dart's shape, since a resident who has used either
// of those pickers already knows how a row-per-option settings screen in
// this app behaves.
//
// Each row mutes exactly one phone push (migration 0044's
// set_notification_mute RPC) — the in-app notification itself is never
// hidden by any of these toggles, only the buzz. 'verification' is
// deliberately absent from this list: the RPC refuses to mute it, and a
// row that always fails when tapped would be worse than no row.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

/// The mutable notification_kind values, in the order shown. 'verification'
/// is intentionally not here — see the file header and 0044's own comment.
const _mutableKinds = [
  'status_change',
  'assignment',
  'reroute',
  'sla_warning',
  'escalation',
];

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  final _muted = <String>{};
  final _busy = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = context.mounted ? context.s.notifPrefsLoadError : null;
      });
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('muted_notification_kinds')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      final list =
          (row?['muted_notification_kinds'] as List?)?.cast<String>() ?? [];
      setState(() {
        _muted
          ..clear()
          ..addAll(list);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.s.notifPrefsLoadError;
      });
    }
  }

  Future<void> _toggle(String kind, bool mute) async {
    setState(() => _busy.add(kind));
    try {
      await Supabase.instance.client.rpc('set_notification_mute', params: {
        'p_kind': kind,
        'p_muted': mute,
      });
      if (!mounted) return;
      setState(() {
        mute ? _muted.add(kind) : _muted.remove(kind);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.notifPrefsUpdateFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(kind));
    }
  }

  String _label(Strings s, String kind) => switch (kind) {
        'assignment' => s.notifPrefsAssignment,
        'reroute' => s.notifPrefsReroute,
        'status_change' => s.notifPrefsStatusChange,
        'escalation' => s.notifPrefsEscalation,
        'sla_warning' => s.notifPrefsSlaWarning,
        _ => kind,
      };

  // Branch D, 1:1 with the preview's Notification Preferences: back and
  // the h2, the lead line, one bordered box of rows — a coloured 34 px
  // icon square, the label, the green sliding toggle.
  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final s = context.s;
    return DPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Row(children: [
            const DBack(),
            const SizedBox(width: 10),
            Expanded(child: Text(s.notifPrefsTitle, style: DType.h2(d.ink).copyWith(fontSize: 22))),
          ]),
          const SizedBox(height: 14),
          Text(s.notifPrefsSubtitle, style: DType.body(d.ink2, size: 13.5)),
          const SizedBox(height: 14),
          if (_loading)
            Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: d.accent)))
          else if (_error != null)
            DSheet(
              borderColor: DColors.red.withValues(alpha: .5),
              child: Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
            )
          else
            Container(
              decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < _mutableKinds.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: d.line),
                  _PrefRow(
                    kind: _mutableKinds[i],
                    label: _label(s, _mutableKinds[i]),
                    // A row shows ON when the push is allowed — "muted" is
                    // the stored, negative concept, but a switch reads as
                    // "this is turned on".
                    value: !_muted.contains(_mutableKinds[i]),
                    busy: _busy.contains(_mutableKinds[i]),
                    onChanged: (allow) => _toggle(_mutableKinds[i], !allow),
                  ),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({required this.kind, required this.label, required this.value, required this.busy, required this.onChanged});

  final String kind;
  final String label;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  static (Color, IconData) _look(String k) => switch (k) {
        'status_change' => (const Color(0xFF00308F), Icons.check_circle_outline_rounded),
        'assignment' => (const Color(0xFF356CF9), Icons.shield_outlined),
        'reroute' => (const Color(0xFF0F9D9A), Icons.repeat_rounded),
        'sla_warning' => (const Color(0xFFF59E0B), Icons.schedule_rounded),
        'escalation' => (const Color(0xFF8B5CF6), Icons.north_east_rounded),
        _ => (const Color(0xFF0EA5E9), Icons.notifications_none_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final (col, icon) = _look(kind);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 19, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: DType.body(d.ink, size: 14.5, w: FontWeight.w600).copyWith(height: 1.25))),
        const SizedBox(width: 12),
        if (busy)
          const SizedBox(width: 46, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
        else
          Semantics(label: label, toggled: value, child: DToggle(on: value, onTap: () => onChanged(!value))),
      ]),
    );
  }
}

/// `.tog`: 46x28, grey, green when on, a 22 px white knob.
