// SmartSumbong — live preview (developer mode, 0160).
//
// A super admin in the portal's Control Room can show their unsaved edits on a real phone. The phone pairs with a one-time code
// (preview_pair), then listens on a private channel the portal sends its draft to. While paired the real screens show the draft instead
// of what the barangay has published; ending it (or the code running out) puts the published copy back. The phone only listens: nothing
// here writes to the database, and a banner says all the time that what is on screen is not published.
//
// Who gets here: anyone can tap the version line in Settings seven times, but the server only answers a code a logged-in super admin made,
// the code works once, for 30 minutes, five wrong tries lock the person out for 15 minutes, and all of it is off unless the
// `live_preview` switch is on in the portal.

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_ui.dart' show DTr;
import '../models/complaint_catalogue.dart';

class LivePreview {
  LivePreview._();

  /// What the portal last sent (null before the first draft, and when not paired).
  static final ValueNotifier<Map<String, dynamic>?> draft = ValueNotifier(null);

  /// True from a successful pairing until it ends.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static RealtimeChannel? _channel;
  static Timer? _expiry;

  /// Trades the code for the channel. null: paired. Otherwise why not: 'invalid', 'locked', 'off' or 'error'.
  static Future<String?> pair(String code) async {
    try {
      final device = kIsWeb ? 'browser' : defaultTargetPlatform.name;
      final r = await Supabase.instance.client.rpc('preview_pair', params: {'p_code': code.replaceAll(RegExp(r'[\s-]'), ''), 'p_device': device});
      if (r is! Map) return 'error';
      if (r['ok'] != true) return (r['reason'] as String?) ?? 'invalid';
      final channel = r['channel'] as String?;
      if (channel == null || channel.isEmpty) return 'error';
      _listen(channel, DateTime.tryParse('${r['expires_at']}'));
      return null;
    } catch (_) {
      return 'error';
    }
  }

  static void _listen(String name, DateTime? expires) {
    end(restore: false);
    final client = Supabase.instance.client;
    final ch = client.channel('pv:$name', opts: const RealtimeChannelConfig(self: false));
    ch.onBroadcast(event: 'draft', callback: (m) => _take(m)).subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        ch.sendBroadcastMessage(event: 'hello', payload: {'at': DateTime.now().millisecondsSinceEpoch});
      }
    });
    _channel = ch;
    active.value = true;
    if (expires != null) {
      final left = expires.difference(DateTime.now());
      _expiry = Timer(left.isNegative ? Duration.zero : left, end);
    }
  }

  /// A broadcast is {event, payload: {...}, type}; take the payload, or the map itself when it already is the draft.
  static void _take(Map<String, dynamic> m) {
    final p = m['payload'];
    final d = p is Map ? Map<String, dynamic>.from(p) : (m.containsKey('cats') ? m : null);
    if (d == null) return;
    draft.value = d;
    final cats = d['cats'];
    if (cats is List) ComplaintCatalogue.applyDraft(cats);
    rebuildAll();
  }

  /// Back to what the barangay has published.
  static void end({bool restore = true}) {
    _expiry?.cancel();
    _expiry = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      ch.unsubscribe();
      Supabase.instance.client.removeChannel(ch);
    }
    final was = active.value;
    active.value = false;
    draft.value = null;
    if (restore && was) {
      ComplaintCatalogue.loadCached().whenComplete(() {
        ComplaintCatalogue.refresh();
        rebuildAll();
      });
    }
  }

  /// Every screen reads its data again: the draft is not state any screen owns.
  static void rebuildAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }
}

/// The banner across the top while a phone is paired: what is on screen is not published.
class LivePreviewBanner extends StatelessWidget {
  const LivePreviewBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LivePreview.active,
      builder: (context, on, _) {
        if (!on) return child;
        return Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Material(
                color: const Color(0xFFFF9800),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('PREVIEW: not published', 'PREVIEW: hindi pa nailalathala'),
                            style: const TextStyle(color: Color(0xFF2B1A00), fontWeight: FontWeight.w800, fontSize: 12.5),
                          ),
                        ),
                        TextButton(
                          onPressed: () => LivePreview.end(),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF2B1A00), visualDensity: VisualDensity.compact),
                          child: Text(context.tr('End', 'Tapusin'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Asks for the code. Opened by tapping the version line in Settings seven times.
Future<void> showLivePreviewDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CodeDialog(),
  );
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    if (_code.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final why = await LivePreview.pair(_code.text);
    if (!mounted) return;
    if (why == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _problem = switch (why) {
        'locked' => context.tr('Too many tries. Wait a few minutes.', 'Masyadong maraming subok. Maghintay ng ilang minuto.'),
        'off' => context.tr('This is not available right now.', 'Hindi ito magagamit ngayon.'),
        'error' => context.tr('Could not reach the system. Check your connection.', 'Hindi maabot ang sistema. Suriin ang koneksyon.'),
        _ => context.tr('That code is not valid.', 'Hindi valid ang code na iyon.'),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Preview code', 'Code ng preview')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Type the code a super admin shows in the Control Room.', 'I-type ang code na ipinapakita ng super admin sa Control Room.')),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            maxLength: 9,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 22, letterSpacing: 3, fontWeight: FontWeight.w800),
            decoration: InputDecoration(counterText: '', errorText: _problem),
            onSubmitted: (_) => _pair(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(context.tr('Cancel', 'Kanselahin'))),
        FilledButton(onPressed: _busy ? null : _pair, child: Text(context.tr('Show', 'Ipakita'))),
      ],
    );
  }
}
