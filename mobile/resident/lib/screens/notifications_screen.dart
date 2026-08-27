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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: context.colors.navy,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 24, 30, 8),
                child: Center(
                  child: Text(s.notificationsTitle,
                      style: t.headlineLarge?.copyWith(fontSize: 28)),
                ),
              ),
              Expanded(child: _body(s)),
              Padding(
                padding: const EdgeInsets.fromLTRB(43, 0, 43, 16),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(s.notificationsBack),
                ),
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
      // Figma NO NOTIFICATION (2452:386), copy verbatim.
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        children: [
          const SizedBox(height: 100),
          Icon(Icons.mark_chat_unread_outlined,
              size: 56, color: context.colors.navy.withValues(alpha: 0.6)),
          const SizedBox(height: 20),
          Text(
            s.notificationsEmptyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.notificationsEmptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.35, color: context.colors.muted),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(30, 8, 30, 16),
      itemCount: _items!.length,
      separatorBuilder: (context, __) => Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Divider(height: 1, color: context.colors.navy),
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

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (emphasise) ...[
          Container(width: 2, height: 34, color: color),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            item.message,
            style: TextStyle(
              fontFamily: emphasise ? 'Poppins' : null,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
              fontSize: 13,
              height: 1.35,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _ago(context.s, item.createdAt),
          style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.75)),
        ),
      ],
    );

    if (item.reportId == null) return row;
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
