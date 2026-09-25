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
import '../theme.dart';
import '../widgets/figma_ui.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

/// The mutable notification_kind values, in the order shown. 'verification'
/// is intentionally not here — see the file header and 0044's own comment.
const _mutableKinds = [
  'assignment',
  'reroute',
  'status_change',
  'escalation',
  'sla_warning',
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

  // No frame of its own: laid out as the translated settings pickers
  // (LANGUAGES) — the title 28/800 at 50, the 16/600 rows with the
  // design's switch on a 66 pitch, and the 150x45 Back pill.
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.s;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(30, figmaTop(context, 50), 30, 24),
          child: Column(
            children: [
              FigmaTitle(s.notifPrefsTitle),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Text(
                  s.notifPrefsSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    height: 18 / 14,
                    color: c.navy,
                  ),
                ),
              ),
              const SizedBox(height: 22),

              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: CircularProgressIndicator(color: c.navy),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.hint)),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
                  child: Column(
                    children: [
                      for (final kind in _mutableKinds)
                        _PrefRow(
                          label: _label(s, kind),
                          // A row shows ON when the push is allowed —
                          // "muted" is the stored/negative concept, but a
                          // resident reads a switch as "this is turned
                          // on," so the toggle itself speaks in the
                          // positive.
                          value: !_muted.contains(kind),
                          busy: _busy.contains(kind),
                          onChanged: (allow) => _toggle(kind, !allow),
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),
              FigmaBackPill(label: s.notifPrefsBack),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({
    required this.label,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 66),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: c.navy,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            SizedBox(
              width: 48,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: c.navy),
                ),
              ),
            )
          else
            Semantics(
              label: label,
              child: FigmaSwitch(value: value, onChanged: onChanged),
            ),
        ],
      ),
    );
  }
}
