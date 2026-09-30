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
      setState(() => _items = [
            for (final r in rows) AppNotification.fromRow(r),
          ]);

      // Clear the badge. Failing here is not worth telling the resident
      // about — the notifications are on screen either way.
      final unread = [
        for (final n in _items!) if (!n.isRead) n.id,
      ];
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
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final empty = _items != null && _items!.isEmpty && _error == null;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: context.colors.navy,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    43,
                    (50 - MediaQuery.paddingOf(context).top).clamp(8.0, 50.0),
                    43,
                    0),
                child: Center(
                  child: Text(s.notificationsTitle,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        height: 43.68 / 28,
                        color: context.colors.navy,
                      )),
                ),
              ),
              Expanded(child: _body(s)),
              if (!empty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 20),
                  child: _BackPill(label: s.notificationsBack),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Strings s) {
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.hint)),
      ]);
    }

    if (_items == null) {
      return Center(child: CircularProgressIndicator(color: context.colors.navy));
    }

    if (_items!.isEmpty) {
      // Figma NO NOTIFICATION (2452:386), copy verbatim: the frame's own
      // 50x50 icon 236 below the title, 20/700 and 16/500 on 20, then
      // Back 106 under the text.
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 73),
        children: [
          const SizedBox(height: 236),
          Center(
            child: Image.asset('assets/images/empty-notifications.png',
                width: 52, height: 52, color: context.colors.navy),
          ),
          const SizedBox(height: 9),
          Text(
            s.notificationsEmptyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              height: 1.2,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.notificationsEmptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 16,
              height: 20 / 16,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 106),
          _BackPill(label: s.notificationsBack),
        ],
      );
    }

    // Rows 23 above and below a 1px navy rule, as in the frame.
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(43, 43, 43, 16),
      itemCount: _items!.length,
      separatorBuilder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 23),
        child: Divider(height: 1, thickness: 1, color: context.colors.navy),
      ),
      itemBuilder: (_, i) => _NotificationRow(item: _items![i]),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    // Bold + left bar reads as "new" in Figma's rows; here that is
    // unread specifically (see the file header for why).
    final emphasise = !item.isRead;
    final color = item.isUrgent ? const Color(0xFFFF4949) : context.colors.navy;

    // The frame's row: a 2px bar 14 in (drawn only when unread, but its
    // space always kept so every message starts 33 in), 16px text at 700
    // unread / 500 read on a 15 line, and the time at 12/500.
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 14),
        Container(
          width: 2,
          height: 31,
          color: emphasise ? color : Colors.transparent,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            item.message,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
              fontSize: 16,
              height: 15 / 16,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            _ago(context.s, item.createdAt),
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              height: 15 / 12,
              color: color,
            ),
          ),
        ),
      ],
    );

    // A resident opens the complaint; a tanod's notifications are about
    // dispatches, which open from the tanod home (one app since branch C).
    if (item.reportId == null ||
        AppRoleController.instance.value == AppRole.tanod) {
      return row;
    }
    return InkWell(
      onTap: () =>
          Navigator.of(context).pushNamed('/report', arguments: item.reportId),
      child: row,
    );
  }

  static String _ago(Strings s, DateTime utc) {
    final d = DateTime.now().difference(utc.toLocal());
    if (d.inMinutes < 1) return s.notificationsJustNow;
    if (d.inMinutes < 60) return s.notificationsMinutesAgo(d.inMinutes);
    if (d.inHours < 24) return s.notificationsHoursAgo(d.inHours);
    if (d.inDays < 7) return s.notificationsDaysAgo(d.inDays);

    final l = utc.toLocal();
    return '${s.monthAbbr(l.month)} ${l.day}';
  }
}

/// The frames' Back: a 150x45 navy pill with a 1px #F3F3F3 edge and the
/// y5 / blur 5 shadow at 30%.
class _BackPill extends StatelessWidget {
  const _BackPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D121212),
                blurRadius: 3.5,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              fixedSize: const Size(150, 45),
              minimumSize: const Size(150, 45),
              padding: EdgeInsets.zero,
              elevation: 0,
              side: BorderSide(color: context.colors.bg),
            ),
            child: Text(label),
          ),
        ),
      );
}
