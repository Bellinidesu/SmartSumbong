// SmartSumbong — Notifications (tanod).
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tanod_strings.dart';
import '../../theme.dart';
import '../../widgets/figma_ui.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
        id: r['id'] as String,
        kind: r['kind'] as String? ?? '',
        message: r['message'] as String? ?? '',
        isRead: r['is_read'] == true,
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  /// The three kinds in notification_kind read differently to a
  /// resident: a status change is news, an SLA warning is the barangay
  /// telling on itself, and a dispatch note is somebody on their way.
  IconData get icon => switch (kind) {
        'sla_warning' => Icons.schedule,
        'dispatch' => Icons.directions_walk,
        _ => Icons.notifications_none_rounded,
      };

  /// Drawn red, as the resident list draws its warnings.
  bool get isUrgent => kind == 'escalation' || kind == 'sla_warning';
}

class TanodNotificationsScreen extends StatefulWidget {
  const TanodNotificationsScreen({super.key});

  @override
  State<TanodNotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<TanodNotificationsScreen> {
  List<AppNotification>? _items;
  String? _error;

  // Live while open (8 Sep 2026 — mirrors resident's notifications_
  // screen.dart / this app's own tanod_home_screen.dart). A channel on
  // this tanod's own notifications rows reloads the list through the
  // same _load() pull-to-refresh already used, so a freshly-arrived row
  // gets marked read the moment it arrives instead of only on the next
  // manual open or pull.
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
        .channel('tanod-notifications-$uid')
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
          .select('id, kind, message, is_read, created_at')
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
      setState(() => _error = context.ts.notificationsLoadError);
    }
  }

  // Figma TANOD - NOTIFICATION / NO NOTIFICATION: the title 28/800 at
  // y=50, rows 43 in split by 1px ink rules with 23 either side, and the
  // 150x45 Back pill.
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final empty = _items != null && _items!.isEmpty && _error == null;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: context.colors.navy,
          child: Column(
            children: [
              Padding(
                padding:
                    EdgeInsets.fromLTRB(43, figmaTop(context, 50), 43, 0),
                child: FigmaTitle(s.notificationsTitle),
              ),
              Expanded(child: _body(context)),
              if (!empty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 20),
                  child: FigmaBackPill(label: s.notificationsBack),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = context.ts;
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.hint)),
      ]);
    }

    if (_items == null) {
      return Center(
          child: CircularProgressIndicator(color: context.colors.navy));
    }

    if (_items!.isEmpty) {
      // The frame's own 50x50 icon 236 below the title, 20/700 and
      // 16/500, then Back 106 under the text.
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 50),
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
          Center(child: FigmaBackPill(label: s.notificationsBack)),
        ],
      );
    }

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

  // The frame's row: a 2px bar 14 in (drawn only while unread — this one
  // viewing, even though the row has just been marked read — but its
  // space always kept), 16px text at 700 unread / 500 read, the time at
  // 12/500.
  @override
  Widget build(BuildContext context) {
    final emphasise = !item.isRead;
    final color = item.isUrgent ? kFigmaRed : context.colors.navy;
    return Row(
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
            _ago(context, item.createdAt),
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
  }

  static String _ago(BuildContext context, DateTime utc) {
    final s = context.ts;
    final d = DateTime.now().difference(utc.toLocal());
    if (d.inMinutes < 1) return s.notificationsJustNow;
    if (d.inMinutes < 60) return s.notificationsMinutesAgo(d.inMinutes);
    if (d.inHours < 24) {
      return d.inHours == 1
          ? s.notificationsAnHourAgo
          : s.notificationsHoursAgo(d.inHours);
    }
    if (d.inDays == 1) return s.notificationsYesterday;
    if (d.inDays < 7) return s.notificationsDaysAgo(d.inDays);

    final l = utc.toLocal();
    return '${s.monthAbbr(l.month)} ${l.day}, ${l.year}';
  }
}
