// SmartSumbong — Notifications.
//
// Figma: NOTIFICATION (2260:1781), NO NOTIFICATION (2452:386).
//
// Everything the system tells a resident lands here: status changes on
// their complaints, SLA warnings, and the approval message when the
// barangay verifies their account. The Home bell counts the unread ones.
//
// Marked read on open rather than per row. A resident who opened the
// screen has seen them, and asking them to tap each one to clear a badge
// is a chore that teaches them to ignore the badge.
//
// REBUILT to match Figma during the parity pass (27 Aug 2026). The
// original version used an AppBar and filled navy/light cards — neither
// is in the design, which is a flat list on the plain page background:
// a thin left bar + bold text for a notification worth stopping on, plain
// text with no bar for one that is mostly a status update, a divider
// between rows, and a bottom "Back" pill instead of the AppBar's back
// chevron. Figma's own example rows split roughly along "short and
// current" (bold+bar) vs "longer and already-described" (plain) rather
// than along read/unread, but this app has no server-side notion of
// that distinction — is_read is what exists — so bold+bar here means
// unread, which is the closest honest mapping to what the design is
// pointing at ("this one is new, look at it") without inventing a
// column nothing else reads.
//
// LIVE WHILE OPEN (29 Aug 2026 — see home_screen.dart's header and
// 0046). A channel on this resident's own notifications rows reloads
// the list — through the same _load() pull-to-refresh already used, so
// a freshly-arrived row gets marked read the same way an already-open
// screen implies it was seen — the moment one arrives, instead of only
// when the resident next opens or drags down.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../models/complaint_category.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../theme.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.reportId,
  });

  final String id;
  final String kind;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  /// Set for most kinds (status_change, escalation, sla_warning); null
  /// for an account-level one like verification. Figma's rows are shown
  /// as tappable ("Click here to submit the additional information") —
  /// this is what a tap resolves to when there is somewhere to go.
  final String? reportId;

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
        id: r['id'] as String,
        kind: r['kind'] as String? ?? '',
        message: r['message'] as String? ?? '',
        isRead: r['is_read'] == true,
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
        reportId: r['report_id'] as String?,
      );

  /// escalation and sla_warning are the barangay's own system flagging
  /// something as running late — Figma's one red row (an emergency
  /// dispatch update, from a flow this app has not built yet) is the
  /// closest precedent for treating an urgent kind differently in colour
  /// rather than only in weight.
  bool get isUrgent => kind == 'escalation' || kind == 'sla_warning';
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;

  /// New when this page opened. The server marks them read straight away
  /// (the bell clears), and the live feed then reloads them as read; they
  /// keep their new look and count here until the page closes or Mark all
  /// as read (7 Oct 2026).
  final _fresh = <String>{};
  // report id -> (tracking id, category), for each row's report chip
  Map<String, (String, ComplaintCategory)> _reports = {};
  String? _error;

  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    if (_liveChannel != null) {
      Supabase.instance.client.removeChannel(_liveChannel!);
    }
    super.dispose();
  }

  void _subscribeLive(String uid) {
    if (_liveChannel != null) return;
    _liveChannel = Supabase.instance.client
        .channel('notifications-inbox-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) => _scheduleLiveReload(),
      )
      ..subscribe();
  }

  void _scheduleLiveReload() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    _subscribeLive(uid);

    setState(() => _error = null);
    try {
      final rows = await client
          .from('notifications')
          .select('id, kind, message, is_read, created_at, report_id')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      final list = [for (final r in rows) AppNotification.fromRow(r)];
      final ids = {for (final n in list) if (n.reportId != null) n.reportId!}.toList();
      final reports = <String, (String, ComplaintCategory)>{};
      if (ids.isNotEmpty) {
        try {
          final rr = await client.from('reports').select('id, tracking_id, category').inFilter('id', ids);
          for (final r in rr) {
            reports[r['id'] as String] = (r['tracking_id'] as String? ?? '', ComplaintCategory.parse(r['category'] as String?));
          }
        } catch (_) {}
      }
      if (!mounted) return;
      _fresh.addAll([for (final n in list) if (!n.isRead) n.id]);
      setState(() {
        _items = [
          for (final n in list)
            _fresh.contains(n.id) && n.isRead
                ? AppNotification(id: n.id, kind: n.kind, message: n.message, isRead: false, createdAt: n.createdAt, reportId: n.reportId)
                : n,
        ];
        _reports = reports;
      });

      // Clear the badge. Failing here is not worth telling the resident
      // about — the notifications are on screen either way.
      final unread = [
        for (final n in _items!) if (!n.isRead) n.id,
      ];
      // Marked read on the server (the bell clears), but they keep their
      // "new" look on screen until the resident leaves, so they can see
      // which ones arrived since last time.
      if (unread.isNotEmpty) {
        try {
          await client
              .from('notifications')
              .update({'is_read': true}).inFilter('id', unread);
        } catch (_) {}
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.s.notificationsLoadError);
    }
  }

  // Figma NOTIFICATION / NO NOTIFICATION (2260:1781, 2452:386): the
  // title 28/800 50 from the top of the screen, the list 43 under it at
  // 43 margins, and Back as the frames' 150x45 pill — at the bottom under
  // a list, directly under the message when there is nothing to show.
  // Branch D, 1:1 with the preview's Notifications: back, the 24/800
  // heading and Mark all as read; the All / Unread / My reports chips;
  // then Today and Earlier, each a bordered list of rows — a coloured
  // 40 px icon square, the notice, the time — unread ones tinted with a
  // red dot at the left.
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final items = _items;
    final unread = items?.where((n) => !n.isRead).length ?? 0;
    Widget chip(String k, String label) {
      final on = _filter == k;
      return GestureDetector(
        onTap: () => setState(() => _filter = k),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: on ? d.btn : d.card, borderRadius: BorderRadius.circular(99), border: Border.all(color: on ? d.btn : d.line)),
          child: Text(label, style: DType.body(on ? Colors.white : d.ink2, size: 12.5, w: FontWeight.w700)),
        ),
      );
    }

    bool shown(AppNotification n) => switch (_filter) {
          'unread' => !n.isRead,
          'reports' => n.reportId != null,
          _ => true,
        };
    final now = DateTime.now();
    bool today(AppNotification n) {
      final l = n.createdAt.toLocal();
      return l.year == now.year && l.month == now.month && l.day == now.day;
    }

    Widget group(String title, List<AppNotification> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(title.toUpperCase(), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 1.04, color: d.muted)),
            ),
            Container(
              decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < list.length; i++) _NotificationRow(item: list[i], first: i == 0, report: list[i].reportId == null ? null : _reports[list[i].reportId]),
              ]),
            ),
            const SizedBox(height: 12),
          ]);

    final visible = (items ?? const <AppNotification>[]).where(shown).toList();
    return DPage(
      child: RefreshIndicator(
        onRefresh: _load,
        color: d.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          children: [
            Row(children: [
              const DBack(),
              const SizedBox(width: 10),
              Expanded(child: Text(s.notificationsTitle, style: DType.h2(d.ink).copyWith(fontSize: 24))),
              // Always in the header, as in the preview (7 Oct 2026); muted
              // when there is nothing left to mark.
              TextButton(
                onPressed: unread == 0
                    ? null
                    : () => setState(() {
                          _fresh.clear();
                          _items = [
                          for (final n in _items!)
                            AppNotification(id: n.id, kind: n.kind, message: n.message, isRead: true, createdAt: n.createdAt, reportId: n.reportId),
                          ];
                        }),
                child: Text(context.tr('Mark all as read', 'Basahin lahat'), style: DType.body(unread == 0 ? d.muted : d.link, size: 13, w: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 12),
            if (_error != null)
              DSheet(
                borderColor: DColors.red.withValues(alpha: .5),
                child: Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
              )
            else if (items == null)
              Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: d.accent)))
            else ...[
              Wrap(spacing: 6, runSpacing: 6, children: [
                chip('all', context.tr('All', 'Lahat')),
                chip('unread', context.tr('Unread', 'Hindi pa nababasa') + (unread > 0 ? ' · $unread' : '')),
                chip('reports', context.tr('My reports', 'Aking reports')),
              ]),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 10),
                  child: Text(items.isEmpty ? s.notificationsEmptyTitle : context.tr('You’re all caught up.', 'Wala nang bago.'),
                      textAlign: TextAlign.center, style: DType.body(d.muted, size: 14)),
                )
              else ...[
                group(context.tr('Today', 'Ngayon'), [for (final n in visible) if (today(n)) n]),
                group(context.tr('Earlier', 'Mas maaga'), [for (final n in visible) if (!today(n)) n]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item, this.first = false, this.report});

  final AppNotification item;
  final bool first;
  final (String, ComplaintCategory)? report;

  /// What the notice is, read from its words first and its kind second:
  /// the title, the tile colour and its glyph.
  static (String, Color, IconData) _look(AppNotification n) {
    final m = n.message.toLowerCase();
    final k = n.kind;
    if (k.contains('escalat')) return ('Escalation alert', const Color(0xFF8B5CF6), Icons.north_east_rounded);
    if (k.contains('sla') || k.contains('deadline')) return ('Response time warning', const Color(0xFFF59E0B), Icons.timer_outlined);
    if (k.contains('verif')) {
      // The account kind covers bad news too: say what happened, in the
      // colour that fits it.
      if (m.contains('suspend')) return ('Account suspended', const Color(0xFFD92D2D), Icons.block_rounded);
      if (m.contains('reinstat')) return ('Account reinstated', const Color(0xFF1F8A45), Icons.verified_user_outlined);
      if (m.contains('reject') || m.contains('not approved') || m.contains('declined')) return ('Verification not approved', const Color(0xFFD92D2D), Icons.gpp_bad_outlined);
      if (m.contains('retire')) return ('Account retired', const Color(0xFF6E7489), Icons.logout_rounded);
      return ('Account verification', const Color(0xFF1F8A45), Icons.verified_user_outlined);
    }
    if (m.contains('on the way')) return ('A tanod is on the way', const Color(0xFF0F9D9A), Icons.arrow_forward_rounded);
    if (m.contains('arrived')) return ('The tanod has arrived', const Color(0xFF7BA428), Icons.place_outlined);
    if (m.contains('dispatched') || k.contains('assign') || k.contains('dispatch')) return ('A tanod is on your report', const Color(0xFF356CF9), Icons.shield_outlined);
    if (m.contains('reassign') || k.contains('reroute')) return ('Report reassigned', const Color(0xFF0F9D9A), Icons.swap_horiz_rounded);
    if (m.contains('expected resolution') || m.contains('target')) return ('Target date set', const Color(0xFFF59E0B), Icons.schedule_rounded);
    if (m.contains('resolved') || m.contains('completed')) return ('Your report was resolved', const Color(0xFF1F8A45), Icons.task_alt_rounded);
    if (m.contains('accepted')) return ('Your report was accepted', const Color(0xFF00308F), Icons.check_rounded);
    if (k.contains('message') || k.contains('detail') || m.contains('message')) return ('New message from the barangay', const Color(0xFF8B5CF6), Icons.chat_bubble_outline_rounded);
    if (k.contains('flood') || m.contains('flood') || m.contains('rain')) return ('Flood watch', const Color(0xFF0EA5E9), Icons.water_rounded);
    return ('Report update', const Color(0xFF00308F), Icons.description_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final (title, col, icon) = _look(item);
    final unread = !item.isRead;
    // A resident opens the complaint; a tanod's notifications are about
    // dispatches, which open from the tanod home (one app since branch C).
    final opens = item.reportId != null && AppRoleController.instance.value != AppRole.tanod;
    final track = report?.$1.isNotEmpty == true ? report!.$1 : RegExp(r'BRG-\d{4}-\d{4}').firstMatch(item.message)?.group(0);
    return InkWell(
      onTap: opens ? () => Navigator.of(context).pushNamed('/report', arguments: item.reportId) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        decoration: BoxDecoration(
          color: unread ? Color.alphaBlend(d.link.withValues(alpha: .06), d.card) : null,
          border: first ? null : Border(top: BorderSide(color: d.line)),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          if (unread)
            Positioned(left: -10, top: 0, bottom: 0, child: Center(child: Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE5383B))))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: item.isUrgent ? const Color(0xFFE5383B) : col, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 21, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: DType.body(d.ink, size: 14, w: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(item.message, style: DType.body(d.muted, size: 12.5).copyWith(height: 1.3)),
                if (track != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    if (report != null) ...[
                      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: categoryColour(report!.$2))),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(report == null ? track : '$track · ${report!.$2.label}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink2, size: 11.5, w: FontWeight.w700)),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            Text(_when(context.s, item.createdAt), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 11, color: d.muted)),
          ]),
        ]),
      ),
    );
  }

  /// Today: the clock time; before today: the date.
  static String _when(Strings s, DateTime utc) {
    final l = utc.toLocal();
    final now = DateTime.now();
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
      return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
    }
    return '${s.monthAbbr(l.month)} ${l.day}';
  }
}
